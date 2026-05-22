#!/usr/bin/env bash
# ===============================================================
# OpenClaw 大模型配置切换脚本
# ===============================================================
# 功能：为 OpenClaw 主网关和 Rescue 网关配置 DeepSeek 大模型
# 用法：
#   ./configure-openclaw-model.sh [选项]
#
# 示例：
#   交互式配置（推荐）：
#     ./configure-openclaw-model.sh
#
#   快速配置（所有 agent 使用同一模型）：
#     ./configure-openclaw-model.sh \
#       --api-key sk-xxx \
#       --model deepseek-v4-flash
#
#   自定义配置（区分 lead 和普通 agent）：
#     ./configure-openclaw-model.sh \
#       --api-key sk-xxx \
#       --lead-model deepseek-v4-pro \
#       --model deepseek-v4-flash \
#       --lead-agent pm01
#
#   自定义 API 地址：
#     ./configure-openclaw-model.sh \
#       --api-key sk-xxx \
#       --base-url https://api.deepseek.com/v1 \
#       --model deepseek-v4-flash
# ===============================================================

set -euo pipefail

# ---------- 配置 ----------
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
RESCUE_CONFIG="$HOME/.openclaw-rescue/openclaw.json"

# 默认值
DEFAULT_BASE_URL="https://api.deepseek.com/v1"
DEFAULT_LEAD_MODEL="deepseek-v4-pro"
DEFAULT_MODEL="deepseek-v4-flash"
DEFAULT_LEAD_AGENT="pm01"

# ---------- 颜色输出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------- 帮助 ----------
usage() {
    sed -n '/^# ====/,/^# ====/p' "$0" | head -n -1
    echo ""
    echo "选项："
    echo "  -k, --api-key KEY    DeepSeek API Key（必填）"
    echo "  -u, --base-url URL   API 地址（默认: $DEFAULT_BASE_URL）"
    echo "  -m, --model NAME     普通 agent 模型名（默认: $DEFAULT_MODEL）"
    echo "  -l, --lead-model NAME 主 agent 模型名（默认: $DEFAULT_LEAD_MODEL）"
    echo "  -a, --lead-agent ID  使用 lead-model 的 agent ID（默认: $DEFAULT_LEAD_AGENT）"
    echo "  -e, --exclude IDS    不修改的 agent ID 列表（逗号分隔）"
    echo "  -f, --force          跳过确认提示"
    echo "  -h, --help           显示此帮助"
    exit 0
}

# ---------- 解析参数 ----------
API_KEY=""
BASE_URL="$DEFAULT_BASE_URL"
MODEL="$DEFAULT_MODEL"
LEAD_MODEL="$DEFAULT_LEAD_MODEL"
LEAD_AGENT="$DEFAULT_LEAD_AGENT"
EXCLUDE=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--api-key)     API_KEY="$2"; shift 2 ;;
        -u|--base-url)    BASE_URL="$2"; shift 2 ;;
        -m|--model)       MODEL="$2"; shift 2 ;;
        -l|--lead-model)  LEAD_MODEL="$2"; shift 2 ;;
        -a|--lead-agent)  LEAD_AGENT="$2"; shift 2 ;;
        -e|--exclude)     EXCLUDE="$2"; shift 2 ;;
        -f|--force)       FORCE=true; shift ;;
        -h|--help)        usage ;;
        *)                err "未知选项: $1"; usage ;;
    esac
done

# ---------- 前置检查 ----------
check_deps() {
    local missing=false
    for cmd in python3 jq; do
        if ! command -v "$cmd" &>/dev/null; then
            err "缺少依赖: $cmd"
            missing=true
        fi
    done
    $missing && exit 1
}

check_configs() {
    local missing=false
    for cfg in "$OPENCLAW_CONFIG" "$RESCUE_CONFIG"; do
        if [[ ! -f "$cfg" ]]; then
            err "配置文件不存在: $cfg"
            missing=true
        fi
    done
    $missing && exit 1
}

backup_configs() {
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    cp "$OPENCLAW_CONFIG" "${OPENCLAW_CONFIG}.bak.${ts}"
    cp "$RESCUE_CONFIG" "${RESCUE_CONFIG}.bak.${ts}"
    ok "已备份: ${OPENCLAW_CONFIG}.bak.${ts}"
    ok "已备份: ${RESCUE_CONFIG}.bak.${ts}"
}

# ---------- 核心修改 ----------
update_config() {
    local config_file="$1"
    local api_key="$2"
    local base_url="$3"
    local model="$4"
    local lead_model="$5"
    local lead_agent="$6"
    local exclude="$7"

    info "修改: $config_file"

    python3 -c "
import json, sys

with open('$config_file', 'r') as f:
    cfg = json.load(f)

model_id = '$model'
lead_model_id = '$lead_model'
lead_agent_id = '$lead_agent'
exclude_list = [x.strip() for x in '$exclude'.split(',') if x.strip()]

# 1. 添加 DeepSeek provider
deepseek_provider = {
    'deepseek': {
        'baseUrl': '$base_url',
        'apiKey': '$api_key',
        'api': 'openai-completions',
        'models': [
            {
                'id': lead_model_id,
                'name': lead_model_id,
                'reasoning': False,
                'input': ['text'],
                'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
                'contextWindow': 65536,
                'maxTokens': 8192
            },
            {
                'id': model_id,
                'name': model_id,
                'reasoning': False,
                'input': ['text'],
                'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
                'contextWindow': 1000000,
                'maxTokens': 65536
            }
        ]
    }
}

cfg.setdefault('models', {}).setdefault('providers', {}).update(deepseek_provider)

# 2. 更新 defaults
defaults = cfg.setdefault('agents', {}).setdefault('defaults', {})
defaults['model'] = {
    'primary': f'deepseek/{model_id}',
    'fallbacks': ['bailian/glm-5', 'bailian/qwen3.5-plus']
}
available_models = defaults.setdefault('models', {})
available_models[f'deepseek/{model_id}'] = {}
available_models[f'deepseek/{lead_model_id}'] = {}

# 3. 更新每个 agent 的模型
for agent in cfg.setdefault('agents', {}).setdefault('list', []):
    aid = agent.get('id', '')
    if aid in exclude_list:
        print(f'  [SKIP] {aid} (已排除)')
        continue
    if aid == lead_agent_id:
        agent['model'] = f'deepseek/{lead_model_id}'
        print(f'  [LEAD] {aid} -> deepseek/{lead_model_id}')
    else:
        agent['model'] = f'deepseek/{model_id}'
        print(f'  [OK]   {aid} -> deepseek/{model_id}')

with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)

print(f'  => 配置已写入: $config_file')
" || { err "修改失败: $config_file"; return 1; }

    ok "已更新: $config_file"
}

# ---------- 验证 ----------
validate() {
    local config_file="$1"
    python3 -c "
import json
with open('$config_file', 'r') as f:
    d = json.load(f)
providers = d.get('models', {}).get('providers', {})
if 'deepseek' not in providers:
    print('  ✗ DeepSeek provider 未找到')
    sys.exit(1)
ds = providers['deepseek']
print(f'  ✓ API: {ds[\"baseUrl\"]}')
for m in ds.get('models', []):
    print(f'  ✓ 模型: {m[\"id\"]} (ctx={m[\"contextWindow\"]})')
agents = d.get('agents', {}).get('list', [])
models = {}
for a in agents:
    models[a['model']] = models.get(a['model'], 0) + 1
for m, c in models.items():
    print(f'  ✓ {m}: {c} agent(s)')
" 2>/dev/null || { err "验证失败"; return 1; }
}

# ---------- 交互式配置 ----------
interactive() {
    echo ""
    echo "=============================="
    echo " OpenClaw 模型配置向导"
    echo "=============================="
    echo ""

    if [[ -z "$API_KEY" ]]; then
        read -r -p "请输入 DeepSeek API Key: " API_KEY
    fi

    if [[ -z "$API_KEY" ]]; then
        err "API Key 不能为空"
        exit 1
    fi

    echo ""
    echo "当前配置:"
    echo "  1) Base URL:     $BASE_URL"
    echo "  2) Lead Agent:   $LEAD_AGENT -> $LEAD_MODEL"
    echo "  3) 其他 Agent:   -> $MODEL"
    echo ""

    if ! $FORCE; then
        read -r -p "确认执行以上配置？(Y/n): " confirm
        confirm="${confirm:-Y}"
        if [[ "$confirm" != "Y" && "$confirm" != "y" && "$confirm" != "yes" ]]; then
            info "已取消"
            exit 0
        fi
    fi
}

# ---------- 主流程 ----------
main() {
    echo ""
    echo "========================================"
    echo " OpenClaw 模型配置脚本"
    echo "========================================"

    check_deps
    check_configs

    # 交互模式
    if [[ -z "$API_KEY" ]]; then
        interactive
    elif ! $FORCE; then
        echo ""
        echo "即将执行: Base URL=$BASE_URL, 模型=$MODEL, Lead模型=$LEAD_MODEL"
        read -r -p "确认执行？(Y/n): " confirm
        confirm="${confirm:-Y}"
        if [[ "$confirm" != "Y" && "$confirm" != "y" ]]; then
            info "已取消"
            exit 0
        fi
    fi

    # 备份
    echo ""
    info "备份原配置文件..."
    backup_configs

    # 修改主配置
    echo ""
    info "更新主网关配置..."
    update_config "$OPENCLAW_CONFIG" "$API_KEY" "$BASE_URL" "$MODEL" "$LEAD_MODEL" "$LEAD_AGENT" "$EXCLUDE"

    # 修改救援配置
    echo ""
    info "更新 Rescue 网关配置..."
    update_config "$RESCUE_CONFIG" "$API_KEY" "$BASE_URL" "$MODEL" "$LEAD_MODEL" "$LEAD_AGENT" "$EXCLUDE"

    # 验证
    echo ""
    info "验证主网关配置..."
    validate "$OPENCLAW_CONFIG"
    echo ""
    info "验证 Rescue 网关配置..."
    validate "$RESCUE_CONFIG"

    # 完成
    echo ""
    echo "========================================"
    echo -e "${GREEN}配置完成！${NC}"
    echo "========================================"
    echo ""
    echo "修改了以下配置文件:"
    echo "  - $OPENCLAW_CONFIG"
    echo "  - $RESCUE_CONFIG"
    echo ""
    echo "备份文件:"
    echo "  - ${OPENCLAW_CONFIG}.bak.*"
    echo "  - ${RESCUE_CONFIG}.bak.*"
    echo ""
    echo "如需重启 gateway 使配置生效，请运行:"
    echo "  openclaw gateway restart"
    echo ""
}

main "$@"
