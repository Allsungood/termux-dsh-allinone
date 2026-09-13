#!/usr/bin/env bash
# ==============================================================================
# install.sh — 一键安装 Termux All-in-One 环境到 Termux
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/yourname/termux-dsh-allinone/main/scripts/setup-all.sh | bash -s -- -y
#   bash install.sh              # 交互式
#   bash install.sh -y           # 非交互式
# ==============================================================================
set -euo pipefail

REPO="yourname/termux-dsh-allinone"
BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

AUTO_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) AUTO_YES=1 ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
    shift
done

ask_yes_no() {
    local prompt="$1"
    if [ "$AUTO_YES" = "1" ]; then
        log_info "[auto-yes] $prompt"
        return 0
    fi
    local ans
    while true; do
        read -rp "$prompt [Y/n]: " ans
        case "${ans,,}" in
            ""|y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

main() {
    echo "=================================================="
    echo "  Termux All-in-One 一键安装程序"
    echo "  dsh + openclaw + ollama + 开发工具链"
    echo "=================================================="
    echo

    # 检查是否在 Termux 中
    if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX/bin" ]; then
        log_error "此脚本必须在 Termux 中运行！"
        log_error "请从 F-Droid 安装 Termux: https://f-droid.org/packages/com.termux/"
        exit 1
    fi

    log_info "检测到 Termux 环境: $PREFIX"

    # 更新包列表
    log_info "更新包列表..."
    pkg update -y

    # 安装基础依赖
    log_info "安装基础依赖..."
    pkg install -y git curl wget proot-distro

    # 克隆或更新仓库
    INSTALL_DIR="$HOME/termux-dsh-allinone"
    if [ -d "$INSTALL_DIR/.git" ]; then
        log_info "更新现有仓库..."
        cd "$INSTALL_DIR"
        git pull origin "$BRANCH"
    else
        log_info "克隆仓库..."
        git clone --branch "$BRANCH" "https://github.com/$REPO.git" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

    # 运行完整设置
    log_info "开始环境配置..."
    export DSH_ASSUME_YES=1
    export DSH_APPROVE_POLICY=never
    bash "$INSTALL_DIR/scripts/setup-all.sh" -y

    echo
    echo "=================================================="
    log_success "安装完成！"
    echo "=================================================="
    echo
    echo "可用命令:"
    echo "  dsh web --port 3080       # DeepSeek Harness Web UI"
    echo "  openclawx setup           # OpenClaw 首次配置"
    echo "  openclawx onboarding      # 配置 API Key"
    echo "  openclawx start           # 启动 OpenClaw 网关"
    echo "  ollama serve              # 启动 Ollama 服务"
    echo "  ollama pull llama3.2:1b   # 下载模型"
    echo
    echo "建议：重启 Termux 或运行 'source ~/.bashrc' 使 PATH 生效"
}

main "$@"