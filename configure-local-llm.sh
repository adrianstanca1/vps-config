#!/bin/bash
set -euo pipefail
echo "============================================"
echo "  Configuring all tools to use local Ollama"
echo "============================================"

BEST_MODEL="qwen3.5:latest"
FAST_MODEL="qwen2.5:7b"
REASONING_MODEL="deepseek-r1:7b"
OLLAMA_URL="http://127.0.0.1:11434"

# ─────────────────────────────────────────────────
# 1. HERMES — Switch primary model to local Ollama
# ─────────────────────────────────────────────────
echo ""
echo "[1/6] Configuring Hermes..."

# Backup
cp /root/.hermes/config.yaml /root/.hermes/config.yaml.bak.$(date +%s)

# Use python3 to do a surgical YAML edit (replace model section)
python3 << 'PYEOF'
import re

with open("/root/.hermes/config.yaml", "r") as f:
    content = f.read()

# Replace the model section at the top
old_model = re.compile(
    r'^model:\n  default: .*\n  provider: .*\n  base_url: .*\n  api_mode: .*',
    re.MULTILINE
)
new_model = """model:
  default: qwen3.5:latest
  provider: custom:ollama
  base_url: http://127.0.0.1:11434/v1
  api_mode: chat_completions"""

content = old_model.sub(new_model, content)

# Also update delegation section if it exists
content = re.sub(
    r"(delegation:\n  model: )'[^']*'",
    r"\g<1>'qwen3.5:latest'",
    content
)
content = re.sub(
    r"(delegation:\n  model: .*\n  provider: )'[^']*'",
    r"\g<1>'custom:ollama'",
    content
)
content = re.sub(
    r"(delegation:\n  model: .*\n  provider: .*\n  base_url: )'[^']*'",
    r"\g<1>'http://127.0.0.1:11434/v1'",
    content
)

with open("/root/.hermes/config.yaml", "w") as f:
    f.write(content)

print("  ✓ Hermes primary model → qwen3.5:latest via local Ollama")
PYEOF

# Verify
echo "  Hermes model config now:"
head -5 /root/.hermes/config.yaml | sed 's/^/    /'

# ─────────────────────────────────────────────────
# 2. CLAUDE CODE — Set model to use Ollama
# ─────────────────────────────────────────────────
echo ""
echo "[2/6] Configuring Claude Code..."

cp /root/.claude.json /root/.claude.json.bak.$(date +%s)

python3 << 'PYEOF'
import json

with open("/root/.claude.json", "r") as f:
    d = json.load(f)

# Set model to use local Ollama model
d["model"] = "gemma4"
d["advisorModel"] = "qwen3.5:latest"

# Ensure projects use local models
for proj_key in d.get("projects", {}):
    proj = d["projects"][proj_key]
    if "model" not in proj or proj.get("model") in [None, ""]:
        proj["model"] = "gemma4"

with open("/root/.claude.json", "w") as f:
    json.dump(d, f, indent=2)

print("  ✓ Claude Code model → gemma4, advisor → qwen3.5:latest")
PYEOF

# ─────────────────────────────────────────────────
# 3. OPENCODE — Configure for Ollama
# ─────────────────────────────────────────────────
echo ""
echo "[3/6] Configuring OpenCode..."

mkdir -p /root/.config/opencode

cat > /root/.config/opencode/opencode.json << 'OCEOF'
{
  "provider": "ollama",
  "model": "qwen3.5:latest",
  "providers": {
    "ollama": {
      "apiKey": "ollama",
      "baseURL": "http://127.0.0.1:11434/v1",
      "models": {
        "qwen3.5:latest": {
          "contextLength": 32768,
          "maxTokens": 8192
        },
        "gemma4:latest": {
          "contextLength": 32768,
          "maxTokens": 8192
        },
        "deepseek-r1:7b": {
          "contextLength": 131072,
          "maxTokens": 8192
        },
        "qwen2.5:7b": {
          "contextLength": 32768,
          "maxTokens": 8192
        }
      }
    }
  }
}
OCEOF
echo "  ✓ OpenCode → qwen3.5:latest via Ollama"

# ─────────────────────────────────────────────────
# 4. OPENCLAW — Add all available models
# ─────────────────────────────────────────────────
echo ""
echo "[4/6] Configuring OpenClaw..."

cp /root/.openclaw/openclaw.json /root/.openclaw/openclaw.json.bak.$(date +%s)

python3 << 'PYEOF'
import json

with open("/root/.openclaw/openclaw.json", "r") as f:
    d = json.load(f)

# Update models to include all available Ollama models
ollama_models = [
    {
        "id": "qwen3.5:latest",
        "name": "Qwen 3.5 (Local)",
        "reasoning": True,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 32768,
        "maxTokens": 8192,
        "api": "ollama"
    },
    {
        "id": "gemma4:latest",
        "name": "Gemma 4 (Local)",
        "reasoning": False,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 32768,
        "maxTokens": 8192,
        "api": "ollama"
    },
    {
        "id": "deepseek-r1:7b",
        "name": "DeepSeek R1 7B (Local)",
        "reasoning": True,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 131072,
        "maxTokens": 8192,
        "api": "ollama"
    },
    {
        "id": "qwen2.5:7b",
        "name": "Qwen 2.5 7B (Local)",
        "reasoning": False,
        "input": ["text"],
        "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
        "contextWindow": 32768,
        "maxTokens": 8192,
        "api": "ollama"
    }
]

d["models"]["providers"]["ollama"]["models"] = ollama_models
d["models"]["providers"]["ollama"]["baseUrl"] = "http://127.0.0.1:11434"
d["models"]["providers"]["ollama"]["apiKey"] = "ollama-local"
d["models"]["providers"]["ollama"]["api"] = "ollama"

with open("/root/.openclaw/openclaw.json", "w") as f:
    json.dump(d, f, indent=2)

# Also update the separate models.json
models_data = {
    "providers": {
        "ollama": {
            "baseUrl": "http://127.0.0.1:11434",
            "apiKey": "ollama-local",
            "api": "ollama",
            "models": ollama_models
        }
    }
}

with open("/root/.openclaw/agents/main/agent/models.json", "w") as f:
    json.dump(models_data, f, indent=2)

print("  ✓ OpenClaw → 4 local models (qwen3.5, gemma4, deepseek-r1:7b, qwen2.5:7b)")
PYEOF

# ─────────────────────────────────────────────────
# 5. CODEX — Make Ollama the default profile
# ─────────────────────────────────────────────────
echo ""
echo "[5/6] Configuring Codex..."

cp /root/.codex/config.toml /root/.codex/config.toml.bak.$(date +%s)

cat > /root/.codex/config.toml << 'CDEOF'
[profiles.default]
openai_base_url = "http://127.0.0.1:11434/v1/"
forced_login_method = "api"
model_provider = "ollama"

[profiles.ollama-launch]
openai_base_url = "http://127.0.0.1:11434/v1/"
forced_login_method = "api"
model_provider = "ollama-launch"

[model_providers.ollama]
name = "Ollama (Local)"
base_url = "http://127.0.0.1:11434/v1/"

[model_providers.ollama-launch]
name = "Ollama"
base_url = "http://127.0.0.1:11434/v1/"
CDEOF
echo "  ✓ Codex default profile → Ollama local"

# ─────────────────────────────────────────────────
# 6. CORTEXBUILD .env — Update to best model
# ─────────────────────────────────────────────────
echo ""
echo "[6/6] Updating CortexBuild .env..."

# Update production env
if [ -f /var/www/cortexbuild-ultimate/.env ]; then
    cp /var/www/cortexbuild-ultimate/.env /var/www/cortexbuild-ultimate/.env.bak.$(date +%s)
    sed -i 's/OLLAMA_MODEL=.*/OLLAMA_MODEL="qwen3.5:latest"/' /var/www/cortexbuild-ultimate/.env
    echo "  ✓ CortexBuild production → qwen3.5:latest"
fi

# ─────────────────────────────────────────────────
# 7. Set global env vars in .bashrc
# ─────────────────────────────────────────────────
echo ""
echo "[BONUS] Setting global environment variables..."

# Remove old entries if any
sed -i '/^export OLLAMA_HOST=/d' /root/.bashrc 2>/dev/null
sed -i '/^export OLLAMA_MODEL=/d' /root/.bashrc 2>/dev/null
sed -i '/^export OPENAI_API_BASE=/d' /root/.bashrc 2>/dev/null
sed -i '/^export OPENAI_API_KEY=ollama/d' /root/.bashrc 2>/dev/null

cat >> /root/.bashrc << 'ENVEOF'

# === Local LLM Configuration (Ollama) ===
export OLLAMA_HOST="http://127.0.0.1:11434"
export OLLAMA_MODEL="qwen3.5:latest"
export OPENAI_API_BASE="http://127.0.0.1:11434/v1"
export OPENAI_API_KEY="ollama-local"
ENVEOF
echo "  ✓ Global env vars set in .bashrc"

echo ""
echo "============================================"
echo "  All tools configured for local Ollama!"
echo "============================================"
echo ""
echo "Models available:"
echo "  • qwen3.5:latest  (9.7B, best quality)"
echo "  • gemma4:latest   (9.6GB, multimodal)"
echo "  • deepseek-r1:7b  (7B, reasoning)"
echo "  • qwen2.5:7b      (7B, fast)"
echo ""
echo "Endpoint: http://127.0.0.1:11434"
echo "External: http://72.62.132.43:11435"
