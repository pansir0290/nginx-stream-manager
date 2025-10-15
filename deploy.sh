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

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
        # 安装基础依赖、Nginx、以及端口检测工具
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
        # 注意：CentOS 的 Nginx 官方包通常默认包含 Stream 模块
        
    else
        log_error "不支持的操作系统 ($OS)。请手动安装 Nginx, curl, vim, net-tools，并确保 Stream 模块已启用。"
        exit 1
    fi
}

# 核心自愈功能：清除配置冲突
cleanup_nginx_config() {
    log_info "正在清理 Nginx 主配置文件中的重复或错误的 load_module 指令..."
    
    # 查找并删除所有包含 "load_module" 且指向 "stream" 模块的行。
    # Stream 模块现在由包管理器自动加载，手动添加会导致冲突。
    # 使用 # 作为 sed 分隔符，避免与路径中的 / 冲突。
    if sudo grep -q "load_module .*ngx_stream.*\.so;" "$NGINX_CONF"; then
        sudo sed -i '/load_module .*ngx_stream.*\.so;/d' "$NGINX_CONF"
        log_success "已从 $NGINX_CONF 清理掉冲突的 Stream 模块加载指令。"
        
        # 尝试重载 Nginx，如果成功则一切正常
        log_info "尝试重载 Nginx 服务以应用配置清理..."
        if sudo systemctl reload nginx 2>/dev/null; then
            log_success "Nginx 服务重载成功。环境已就绪。"
        else
            log_error "Nginx 重载失败。请运行 'sudo nginx -t' 手动检查配置错误。"
            return 1
        fi
    else
        log_info "未检测到冲突的 Stream 模块加载指令，跳过清理。"
    fi
    return 0
}

# 下载并安装 manager.sh
install_manager_script() {
    log_info "正在从 GitHub 下载最新的 $MANAGER_SCRIPT..."
    
    # 下载脚本到临时文件
    if ! sudo curl -fsSL "$REPO_RAW_URL/$MANAGER_SCRIPT" -o "$INSTALL_PATH.tmp"; then
        log_error "下载 $MANAGER_SCRIPT 失败，请检查网络和仓库路径。"
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
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "/root/.bashrc"
        "/root/.zshrc"
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
        log_warning "未能将别名添加到任何已知的 shell 配置文件中。"
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
