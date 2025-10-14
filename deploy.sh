#!/bin/bash

# --- Configuration ---
REPO_URL="pansir0290/nginx-stream-manager"
MANAGER_SCRIPT="manager.sh"
TARGET_PATH="/usr/local/bin/nsm"
MAIN_CONF="/etc/nginx/nginx.conf"
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf" # 规则文件路径

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Nginx Stream Manager (nsm) Deployment Script ---${NC}"

# --- 检查 Nginx 依赖和清理 ---
check_nginx_dependency() {
    echo -e "\n${GREEN}--- Nginx 依赖检查 ---${NC}"

    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}警告：Nginx 未安装。请先运行 'sudo apt install nginx -y' 安装。${NC}"
        return
    fi
    
    # 清理旧的错误配置，使用正确的 tee 命令
    echo "清理旧的 stream_proxy.conf 文件中的残留内容..."
    sudo tee "$CONFIG_FILE" < /dev/null > /dev/null

    # 提示用户当前的 UDP 限制
    echo -e "${YELLOW}警告：已确认您的 Nginx 版本不支持 Stream UDP。${NC}"
    echo -e "   脚本已配置为仅监听 TCP 端口，以确保配置通过。${NC}"
}
# --- 检查函数结束 ---


# --- 自动化配置 Nginx 主配置的函数 (添加全局超时指令) ---
configure_nginx_main() {
    echo -e "\n${GREEN}--- 检查并配置 Nginx 主配置文件 ---${NC}"

    if ! command -v nginx &> /dev/null; then
        return
    fi
    
    # 1. 检查 stream 块是否已存在于主配置
    if grep -q "^stream {" "$MAIN_CONF"; then
        echo -e "${GREEN}Nginx 主配置 ($MAIN_CONF) 中已存在 'stream' 块。正在添加全局超时配置...${NC}"

        # 检查是否已存在全局超时配置，避免重复添加
        if ! grep -q "proxy_connect_timeout" "$MAIN_CONF"; then
            echo "添加全局 Stream 超时配置..."
            # 使用 sed 在 stream { 后的第一行插入超时配置
            sudo sed -i '/^stream {/a \    proxy_connect_timeout 20s;\n    proxy_timeout 5m;' "$MAIN_CONF"
        fi
        
        return
    fi

    echo "未检测到顶级 'stream' 块。正在自动插入配置..."
    # 插入配置时，同时包含超时指令和 include
    STREAM_CONFIG="stream {\n    proxy_connect_timeout 20s;\n    proxy_timeout 5m;\n    include /etc/nginx/conf.d/stream_proxy.conf;\n}"

    # 2. 寻找插入点：在 events {} 块的闭合 '}' 之后插入
    EVENTS_START_LINE=$(grep -n "^events {" "$MAIN_CONF" | head -n 1 | cut -d: -f1)
    
    if [ -n "$EVENTS_START_LINE" ]; then
        EVENTS_END_LINE=$(sed -n "${EVENTS_START_LINE},\$p" "$MAIN_CONF" | grep -n "}" | head -n 1 | cut -d: -f1)
        
        if [ -n "$EVENTS_END_LINE" ]; then
            END_OF_EVENTS=$((EVENTS_START_LINE + EVENTS_END_LINE - 1))
            
            # 插入 stream 块和空行
            sudo sed -i "${END_OF_EVENTS}a\\${STREAM_CONFIG}" "$MAIN_CONF"
            sudo sed -i "${END_OF_EVENTS}a\\" "$MAIN_CONF"
            
            echo -e "${GREEN}'stream' 块已成功插入到 $MAIN_CONF 中。${NC}"
            return
        fi
    fi
    
    echo -e "${RED}错误：无法在 $MAIN_CONF 中定位插入点，请手动配置 Nginx。${NC}"
}

# --- 部署后清理和启动准备 ---
post_deployment_cleanup() {
    echo -e "\n${GREEN}--- 部署后清理与服务启动准备 ---${NC}"
    
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}Nginx 未安装，跳过服务操作。${NC}"
        return
    fi

    # 1. 确保清空残留配置 (双重保险)
    echo "清空规则文件 ${CONFIG_FILE} 中的残留内容..."
    sudo tee "$CONFIG_FILE" < /dev/null > /dev/null
    
    # 2. 立即重启 Nginx 服务 (加载新的 nginx.conf 配置)
    echo "尝试重启 Nginx 服务以加载新的 stream 模块配置..."
    if sudo systemctl restart nginx; then
        echo -e "${GREEN}Nginx 服务重启成功，已加载 Stream 模块。${NC}"
    else
        echo -e "${RED}警告：Nginx 服务重启失败！请检查 ${MAIN_CONF} 文件语法。${NC}"
    fi
}


# --- 脚本主要流程 ---

# 0. Nginx 兼容性检查和清理
check_nginx_dependency

# 1. 检查下载器 (curl/wget)
DOWNLOADER=""
if command -v wget &> /dev/null; then
    DOWNLOADER="sudo wget -qO"
elif command -v curl &> /dev/null; then
    DOWNLOADER="sudo curl -fsSL -o"
else 
    echo -e "${RED}ERROR: wget or curl not found. Please install one to proceed.${NC}"
    exit 1
fi 

# 2. 下载主管理脚本 
DOWNLOAD_URL="https://raw.githubusercontent.com/${REPO_URL}/main/${MANAGER_SCRIPT}"
echo "Downloading ${MANAGER_SCRIPT} from GitHub..."

if $DOWNLOADER "$TARGET_PATH" "$DOWNLOAD_URL"; then 
    echo -e "${GREEN}Script downloaded successfully to $TARGET_PATH${NC}"
else 
    echo -e "${RED}ERROR: Script download failed. Check network or GitHub URL: $DOWNLOAD_URL${NC}"
    exit 1
fi 

# 3. 设置执行权限
echo "Setting executable permissions..."
sudo chmod +x "$TARGET_PATH"

# 4. 自动化配置 Nginx 主配置 (插入 stream {} 和全局超时)
configure_nginx_main

# 5. 执行部署后清理和重启 Nginx
post_deployment_cleanup

# 6. 设置用户友好函数 (nsm)
ALIAS_COMMAND="nsm() { sudo $TARGET_PATH \"\$@\"; }"
ALIAS_CHECK="nsm()"

# 自动检测并选择 Shell 配置文件
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
else
    SHELL_CONFIG="$HOME/.bashrc"
fi

if [ ! -f "$SHELL_CONFIG" ]; then 
    touch "$SHELL_CONFIG"
fi

if ! grep -q "$ALIAS_CHECK" "$SHELL_CONFIG"; then 
    echo "Adding 'nsm' function to $SHELL_CONFIG..."
    echo -e "\n# Nginx Stream Manager alias\n$ALIAS_COMMAND" >> "$SHELL_CONFIG"
else 
    echo "'nsm' function already exists in $SHELL_CONFIG. Skipping addition."
fi 

# 7. 提示用户下次如何启动 
echo -e "\n${GREEN}--- Deployment Complete! ---${NC}"
echo "✅ The setup is complete. Nginx 服务已尝试重启。"
echo -e "💡 To start the manager, run the original 'one-click' command to start the menu:"
echo -e "    ${YELLOW}sudo curl -fsSL https://raw.githubusercontent.com/${REPO_URL}/main/deploy.sh | bash; source $SHELL_CONFIG; nsm${NC}"

exit 0