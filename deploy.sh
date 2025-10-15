#!/bin/bash
# -----------------------------------------------------------------------------
# NSM Deployment Script (nsm-deploy.sh)
# 作用: 自动下载 manager.sh, 配置系统环境, 并创建 nsm 别名
# -----------------------------------------------------------------------------

# 配置参数
REPO_URL="https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main" # 您的 GitHub 仓库路径
MANAGER_URL="$REPO_URL/manager.sh"
MANAGER_PATH="/usr/local/bin/nsm" # 核心脚本的安装路径
NGINX_CONF="/etc/nginx/nginx.conf"
CONFIG_FILE="/etc/nginx/conf.d/nsm/nsm-stream.conf"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：此脚本必须使用root权限运行！请使用sudo。${NC}"
    exit 1
fi

echo -e "\n--- Nginx Stream Manager (NSM) 一键部署脚本 ---"

# 1. 下载 manager.sh
echo -e "\n${YELLOW}--- 1. 下载核心脚本 ---${NC}"
echo "正在下载 manager.sh 到 $MANAGER_PATH..."
if curl -fsSL "$MANAGER_URL" -o "$MANAGER_PATH"; then
    echo -e "${GREEN}✅ 下载成功。${NC}"
    chmod +x "$MANAGER_PATH"
else
    echo -e "${RED}❌ 错误：下载失败。请检查网络或 GitHub 路径。${NC}"
    exit 1
fi

# 2. 检查 Nginx
echo -e "\n${YELLOW}--- 2. Nginx 检查 ---${NC}"
if ! command -v nginx &> /dev/null; then
    echo -e "${RED}❌ 错误：Nginx 未安装。请先手动安装 Nginx。${NC}"
    exit 1
fi

# 2.5 检查基础工具链
echo -e "\n${YELLOW}--- 2.5 基础工具链检查 ---${NC}"
if ! command -v sed &> /dev/null || ! command -v grep &> /dev/null || ! command -v awk &> /dev/null; then
    echo -e "${YELLOW}警告：检测到基本工具(sed/grep/awk)可能缺失或不可用，尝试安装 coreutils...${NC}"
    if command -v apt &> /dev/null; then
        sudo apt update
        sudo apt install -y coreutils sed grep gawk
    elif command -v yum &> /dev/null; then
        sudo yum install -y coreutils sed grep gawk
    else
        echo -e "${RED}致命错误：无法自动安装核心工具。请手动安装 sed, grep, 和 awk。${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✅ 核心工具链就绪。${NC}"

# 3. 配置 Nginx 主文件 (运行 manager.sh 中的初始化函数)
echo -e "\n${YELLOW}--- 3. 配置 Nginx 主文件 ---${NC}"
# 这一步是为了让 manager.sh 自己去检查和修复配置，我们直接运行其初始化部分
# 临时运行 manager.sh 的初始化函数，确保配置目录和 include 语句存在
echo "正在执行 NSM 初始化配置..."
$MANAGER_PATH init_config_dir 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}警告：NSM 初始化配置步骤失败。请手动检查权限或配置文件。${NC}"
fi

# 确保 Stream SSL 模块加载 (解决 ssl_preread 问题)
if ! grep -q "load_module .*ngx_stream_ssl_module\.so;" "$NGINX_CONF"; then
    echo "尝试自动加载 ngx_stream_ssl_module.so..."
    # 使用 manager.sh 中的 install_components 逻辑进行修复
    $MANAGER_PATH install_components 2>/dev/null
fi


# 4. 创建 nsm 命令别名
echo -e "\n${YELLOW}--- 4. 创建快捷命令 ---${NC}"
# 使用 alias，并确保它能通过 source 加载
NSM_ALIAS="alias nsm='sudo $MANAGER_PATH'"
BASHRC="$HOME/.bashrc"

if ! grep -q "alias nsm=" "$BASHRC"; then
    echo "$NSM_ALIAS" >> "$BASHRC"
    echo -e "${GREEN}✅ 'nsm' 命令已添加到 $BASHRC。${NC}"
else
    # 替换旧的别名（如果存在，确保使用最新的路径）
    sed -i "/alias nsm=/c\\$NSM_ALIAS" "$BASHRC"
    echo -e "${GREEN}✅ 'nsm' 命令已存在并更新。${NC}"
fi

# 5. 完成部署
echo -e "\n${GREEN}--- 部署完成！---${NC}"
echo "请运行 ${CYAN}source $BASHRC${NC} 或重新连接 SSH，然后执行 ${CYAN}nsm${NC} 启动管理器。"
