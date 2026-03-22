#!/usr/bin/env python3
"""
Ollama MCP Server - Provides Claude Code with Ollama LLM access.
Serves qwen2.5-coder:7b for code, deepseek-r1:7b for reasoning, nomic-embed-text for embeddings.
"""

import json
import sys
import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent
from mcp.server.server import NotificationOptions
from contextlib import asynccontextmanager

OLLAMA_HOST = "http://localhost:11434"

# Model configurations
MODELS = {
    "qwen2.5-coder:7b": {
        "description": "Code generation, completions, refactoring",
        "default_prompt": "You are an expert programmer. Write clean, efficient code."
    },
    "deepseek-r1:7b": {
        "description": "Chain-of-thought reasoning and problem solving",
        "default_prompt": "You are an expert at reasoning through complex problems step by step."
    },
    "nomic-embed-text": {
        "description": "Text embeddings for semantic search",
        "default_prompt": "Generate embeddings for semantic search."
    }
}

async def list_models() -> list[dict]:
    """Fetch models from Ollama."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.get(f"{OLLAMA_HOST}/api/tags")
            resp.raise_for_status()
            data = resp.json()
            return [m["name"] for m in data.get("models", [])]
        except Exception as e:
            return [f"Error: {e}"]


async def generate_response(model: str, prompt: str, stream: bool = False) -> dict:
    """Generate a response from Ollama."""
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            resp = await client.post(
                f"{OLLAMA_HOST}/api/generate",
                json={"model": model, "prompt": prompt, "stream": stream}
            )
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            return {"error": str(e)}


async def chat_response(model: str, messages: list, stream: bool = False) -> dict:
    """Chat completion with Ollama."""
    async with httpx.AsyncClient(timeout=120.0) as client:
        try:
            resp = await client.post(
                f"{OLLAMA_HOST}/api/chat",
                json={"model": model, "messages": messages, "stream": stream}
            )
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            return {"error": str(e)}


async def embeddings_response(model: str, prompt: str) -> dict:
    """Generate embeddings with Ollama."""
    async with httpx.AsyncClient(timeout=60.0) as client:
        try:
            resp = await client.post(
                f"{OLLAMA_HOST}/api/embeddings",
                json={"model": model, "prompt": prompt}
            )
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            return {"error": str(e)}


@asynccontextmanager
async def server_lifespan(server: Server):
    """Manage server lifecycle."""
    print("Ollama MCP Server starting...", file=sys.stderr)
    models = await list_models()
    print(f"Available models: {models}", file=sys.stderr)
    yield


async def main():
    server = Server("ollama-mcp")

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="list_ollama_models",
                description="List all models available in local Ollama instance",
                inputSchema={
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            ),
            Tool(
                name="generate_code",
                description="Generate code using qwen2.5-coder:7b - best for code completion, refactoring, explaining code",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "prompt": {
                            "type": "string",
                            "description": "The code-related prompt or request"
                        }
                    },
                    "required": ["prompt"]
                }
            ),
            Tool(
                name="reasoning",
                description="Use deepseek-r1:7b chain-of-thought reasoning for complex problem solving and debugging",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "problem": {
                            "type": "string",
                            "description": "The complex problem or question to reason through"
                        }
                    },
                    "required": ["problem"]
                }
            ),
            Tool(
                name="embed_text",
                description="Generate text embeddings using nomic-embed-text for semantic search",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "text": {
                            "type": "string",
                            "description": "Text to generate embeddings for"
                        }
                    },
                    "required": ["text"]
                }
            ),
            Tool(
                name="ollama_chat",
                description="Chat completion with a specified model",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "model": {
                            "type": "string",
                            "enum": ["qwen2.5-coder:7b", "deepseek-r1:7b", "mistral:7b"],
                            "description": "Model to use for chat"
                        },
                        "message": {
                            "type": "string",
                            "description": "User message"
                        },
                        "system": {
                            "type": "string",
                            "description": "Optional system prompt"
                        }
                    },
                    "required": ["model", "message"]
                }
            )
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        if name == "list_ollama_models":
            models = await list_models()
            return [TextContent(type="text", text=json.dumps(models, indent=2))]

        elif name == "generate_code":
            response = await generate_response("qwen2.5-coder:7b", arguments["prompt"])
            if "error" in response:
                return [TextContent(type="text", text=f"Error: {response['error']}")]
            return [TextContent(type="text", text=response.get("response", "No response"))]

        elif name == "reasoning":
            response = await chat_response(
                "deepseek-r1:7b",
                [{"role": "user", "content": arguments["problem"]}]
            )
            if "error" in response:
                return [TextContent(type="text", text=f"Error: {response['error']}")]
            return [TextContent(type="text", text=response.get("message", {}).get("content", "No response"))]

        elif name == "embed_text":
            response = await embeddings_response("nomic-embed-text", arguments["text"])
            if "error" in response:
                return [TextContent(type="text", text=f"Error: {response['error']}")]
            return [TextContent(type="text", text=json.dumps(response.get("embedding", []), indent=2))]

        elif name == "ollama_chat":
            system = arguments.get("system", "You are a helpful assistant.")
            messages = [{"role": "system", "content": system},
                       {"role": "user", "content": arguments["message"]}]
            response = await chat_response(arguments["model"], messages)
            if "error" in response:
                return [TextContent(type="text", text=f"Error: {response['error']}")]
            return [TextContent(type="text", text=response.get("message", {}).get("content", "No response"))]

        return [TextContent(type="text", text=f"Unknown tool: {name}")]

    options = NotificationOptions()
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(options)
        )


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
