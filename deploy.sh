#!/bin/bash

# --- Configuration ---
# 确保这里使用你的实际仓库地址，格式为 "用户名/仓库名"
REPO_URL="pansir0290/nginx-stream-manager"  
MANAGER_SCRIPT="manager.sh"
TARGET_PATH="/usr/local/bin/nsm" # 统一使用 nsm 作为执行名称
MAIN_CONF="/etc/nginx/nginx.conf"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Nginx Stream Manager (nsm) Deployment Script ---${NC}"

# --- 新增的自动化配置 Nginx 主配置的函数 ---
configure_nginx_main() {
    echo -e "\n${GREEN}--- 检查并配置 Nginx 主配置文件 ---${NC}"

    # 1. 检查 Nginx 是否安装 (如果未安装，直接跳过此配置步骤)
    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}警告: Nginx 未安装。跳过主配置修改。${NC}"
        return
    fi
    
    # 2. 检查 stream 块是否已存在于主配置
    if grep -q "^stream {" "$MAIN_CONF"; then
        echo -e "${GREEN}Nginx 主配置 ($MAIN_CONF) 中已存在 'stream' 块。跳过修改。${NC}"
        return
    fi

    echo "未检测到 'stream' 块。正在自动插入配置..."

    # 3. 构造要插入的 stream 块
    STREAM_CONFIG="stream {\n    include /etc/nginx/conf.d/stream_proxy.conf;\n}"

    # 4. 寻找插入点：在 events {} 块的闭合 '}' 之后插入
    #    这个方法比寻找 http {} 块更可靠
    
    # 找到第一个 'events {' 块的闭合 '}' 所在行
    EVENTS_END_LINE=$(grep -n -A 100 "^events {" "$MAIN_CONF" | grep -n "}" | head -n 1 | cut -d: -f1)
    
    if [ -n "$EVENTS_END_LINE" ] && [ "$EVENTS_END_LINE" -gt 0 ]; then
        # 找到 'events {}' 块的闭合 '}' 的实际行号
        START_LINE=$(grep -n "^events {" "$MAIN_CONF" | head -n 1 | cut -d: -f1)
        # 计算 events 块结束的行号
        END_OF_EVENTS=$((START_LINE + EVENTS_END_LINE - 1))
        
        # 使用 sed 在 events 块结束行的下一行插入 stream 块
        sudo sed -i "${END_OF_EVENTS}a\\${STREAM_CONFIG}" "$MAIN_CONF"

        # 添加空行以保持格式清晰 (在插入的 stream 块后添加一行空行)
        sudo sed -i "${END_OF_EVENTS}a\\" "$MAIN_CONF"

        echo -e "${GREEN}'stream' 块已成功插入到 $MAIN_CONF 中。${NC}"
    else
        echo -e "${RED}错误：无法在 $MAIN_CONF 中找到 'events {}' 块，请手动配置 Nginx。${NC}"
    fi
}
# --- 自动化配置函数结束 ---


# 1. 检查 Nginx 依赖 (Warning only) 
if ! command -v nginx &> /dev/null; then
    echo -e "${YELLOW}WARNING: Nginx does not seem to be installed. Please install it manually (e.g., apt install nginx -y).${NC}"
fi

# 2. Check for downloader (curl/wget) 
DOWNLOADER=""
if command -v wget &> /dev/null; then
    DOWNLOADER="sudo wget -qO"
elif command -v curl &> /dev/null; then
    DOWNLOADER="sudo curl -fsSL -o"
else 
    echo -e "${RED}ERROR: wget or curl not found. Please install one to proceed.${NC}"
    exit 1
fi 

# 3. Download the main management script 
DOWNLOAD_URL="https://raw.githubusercontent.com/${REPO_URL}/main/${MANAGER_SCRIPT}"
echo "Downloading ${MANAGER_SCRIPT} from GitHub..."

# Execute the download 
if $DOWNLOADER "$TARGET_PATH" "$DOWNLOAD_URL"; then 
    echo -e "${GREEN}Script downloaded successfully to $TARGET_PATH${NC}"
else 
    echo -e "${RED}ERROR: Script download failed. Check network or GitHub URL: $DOWNLOAD_URL${NC}"
    exit 1
fi 

# 4. Set executable permissions 
echo "Setting executable permissions..."
sudo chmod +x "$TARGET_PATH"

# 5. 自动化配置 Nginx 主配置 (新步骤)
configure_nginx_main

# 6. Set user-friendly function (nsm) 
ALIAS_COMMAND="nsm() { sudo $TARGET_PATH \"\$@\"; }"
ALIAS_CHECK="nsm()"

# 自动检测并选择 Shell 配置文件
if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
    echo "Detected Zsh. Using $SHELL_CONFIG for 'nsm' function."
elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
    echo "Detected Bash. Using $SHELL_CONFIG for 'nsm' function."
else
    # 默认使用 bashrc
    SHELL_CONFIG="$HOME/.bashrc"
    echo "Defaulting to $SHELL_CONFIG for 'nsm' function."
fi


if [ ! -f "$SHELL_CONFIG" ]; then 
    echo "Creating $SHELL_CONFIG file..."
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
echo "✅ The setup is complete."
echo -e "💡 To use the command 'nsm' in future sessions, you need to execute:"
echo -e "   ${YELLOW}source $SHELL_CONFIG${NC}"
echo "   (or simply open a new terminal session)"
echo -e "🚀 Then, run the manager with: ${GREEN}nsm${NC}"

exit 0