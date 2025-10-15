#!/bin/bash
# -----------------------------------------------------------------------------
# Nginx Stream Manager (NSM) 部署脚本
# 功能：自动检测OS、安装依赖、安装Nginx Stream模块、清理配置冲突、
#      下载 manager.sh 并设置 nsm 命令别名。
# -----------------------------------------------------------------------------

set -e # 遇到任何错误立即退出

# 配置参数
REPO_RAW_URL="https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main"
MANAGER_SCRIPT="manager.sh"
INSTALL_PATH="/usr/local/bin/nsm"
NGINX_CONF="/etc/nginx/nginx.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数定义
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否以root运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本必须使用root权限运行！请使用 'sudo $0' 重新执行。"
        exit 1
    fi
}

# 操作系统检测
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/centos-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

# 核心功能：安装所有依赖并处理 Stream 模块问题
install_dependencies() {
    local OS
    OS=$(detect_os)
    log_info "检测到操作系统: $OS"
    log_info "正在安装系统依赖项..."

    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        sudo apt update
        
        # 🎯 核心清理步骤：解决已知的 Nginx 包冲突和旧版本 ABI 问题
        log_info "正在检查并清理可能存在的旧版/冲突 Nginx 包以解决依赖问题..."
        
        # 目标：移除导致冲突的旧版 nginx-common 和可能破碎的 libnginx-mod-stream
        sudo apt remove -y nginx-common libnginx-mod-stream &>/dev/null || true
        
        # 强制解决依赖问题（例如修复 held broken packages）
        sudo apt -f install -y &>/dev/null || true
        
        # 重新运行更新，确保包信息最新
        sudo apt update
        
        # 安装基础依赖、Nginx、以及端口检测工具
        # 这会安装最新的 nginx-common 和 nginx 核心包，解决冲突
        sudo apt install -y curl vim sudo nginx net-tools iproute2

        # 核心修复: 确保安装 libnginx-mod-stream 包，包含 Stream SSL 模块
        log_info "正在检查并安装 Nginx Stream 模块..."
        if ! dpkg -l | grep -q "libnginx-mod-stream"; then
            sudo apt install -y libnginx-mod-stream
            log_success "Nginx Stream 模块安装完成。"
        else
            log_info "Nginx Stream 模块已安装。"
        fi

    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        # CentOS/RHEL 常用命令（假设 Nginx 已启用 EPEL 或官方源）
        sudo yum install -y curl vim sudo nginx net-tools iproute2
        # 或使用 dnf
        # sudo dnf install -y curl vim sudo nginx net-tools iproute2
    else
        log_error "不支持的操作系统 ($OS)。请手动安装 Nginx, curl, vim, net-tools，并确保 Stream 模块已启用。"
        exit 1
    fi
}

# 核心自愈功能：清除配置冲突并重载 Nginx
cleanup_nginx_config() {
    log_info "正在清理 Nginx 主配置文件中的重复或错误的 load_module 指令..."
    
    local NEEDS_CLEANUP=0
    # 查找所有包含 "load_module" 且指向 "stream" 模块的行
    if sudo grep -q "load_module .*ngx_stream.*\.so;" "$NGINX_CONF"; then
        NEEDS_CLEANUP=1
        
        # 使用 sed 清理冲突的指令
        sudo sed -i '/load_module .*ngx_stream.*\.so;/d' "$NGINX_CONF"
        log_success "已从 $NGINX_CONF 清理掉冲突的 Stream 模块加载指令。"
    else
        log_info "未检测到冲突的 Stream 模 块 加 载 指 令 ， 跳 过 清 理 。"
    fi
    
    # 无论是否清理，都要尝试重载 Nginx，确保新安装的模块被加载
    log_info "尝试重载 Nginx 服务以确保环境就绪..."
    if sudo systemctl reload nginx 2>/dev/null; then
        log_success "Nginx 服务重载成功。环境已就绪。"
        return 0
    else
        log_error "Nginx 重载失败。请立即运行 'sudo nginx -t' 手动检查配置错误。部署脚本终止。"
        return 1
    fi
}

# 下载并安装 manager.sh
install_manager_script() {
    log_info "正在从 GitHub 下载最新的 $MANAGER_SCRIPT..."
    
    # 下载脚本到临时文件
    if ! sudo curl -fsSL "$REPO_RAW_URL/$MANAGER_SCRIPT" -o "$INSTALL_PATH.tmp"; then
        log_error "下载 $MANAGER_SCRIPT 失败，请检查网络和仓库路径。脚本终止。"
        exit 1
    fi

    # 移动到安装路径并赋予执行权限
    sudo mv "$INSTALL_PATH.tmp" "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
    log_success "Nginx Stream Manager 已安装到 $INSTALL_PATH"
}

# 设置 nsm 别名
setup_alias() {
    local ALIAS_CMD="alias nsm='sudo $INSTALL_PATH'"
    local PROFILE_FILES=(
        "/root/.bashrc"
        "/root/.zshrc"
        "$HOME/.bashrc"
        "$HOME/.zshrc"
    )

    log_info "正在设置 'nsm' 别名..."

    local found=0
    for file in "${PROFILE_FILES[@]}"; do
        if [ -f "$file" ]; then
            if ! grep -q "alias nsm=" "$file"; then
                echo -e "\n$ALIAS_CMD" | sudo tee -a "$file" > /dev/null
                log_info "别名已添加到 $file"
                found=1
            fi
        fi
    done

    if [ "$found" -eq 0 ]; then
        log_warning "未能将别名添加到任何已知的 shell 配置文件中。请手动添加别名或直接运行 'sudo $INSTALL_PATH'"
    fi

    log_success "部署完成！请运行 'source ~/.bashrc' (或 ~/.zshrc) 后再运行 'nsm' 启动管理工具。"
}

# ==================================
# 主执行逻辑
# ==================================

check_root
install_dependencies

# 只有在依赖安装和环境清理成功后，才下载主脚本
if cleanup_nginx_config; then
    install_manager_script
    setup_alias
fi

exit 0
