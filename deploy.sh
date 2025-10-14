#!/bin/bash

# --- Configuration ---
# 确保这里使用你的实际仓库地址，格式为 "用户名/仓库名"
# 例如：REPO_URL="pansir0290/nginx-stream-manager" 
REPO_URL="pansir0290/nginx-stream-manager"  
MANAGER_SCRIPT="manager.sh"
TARGET_PATH="/usr/local/bin/nsm" # 统一使用 nsm 作为执行名称

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Nginx Stream Manager (nsm) Deployment Script ---${NC}"

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

# 5. Set user-friendly function (nsm) 
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

# 6. 立即执行管理器 (跳过 source 步骤) 
# echo -e "\n${GREEN}--- Deployment Complete! Launching Manager Now ---${NC}" 
# # 直接以 sudo 权限运行管理脚本 
# sudo "$TARGET_PATH" # <--- 注释掉这一行，或者直接删除

# 提示用户下次如何启动 
echo -e "\n${GREEN}--- Deployment Complete! ---${NC}"
echo "✅ The setup is complete."
echo -e "💡 To use the command 'nsm' in future sessions, you need to execute:"
echo -e "   ${YELLOW}source $SHELL_CONFIG${NC}"
echo "   (or simply open a new terminal session)"
echo -e "🚀 Then, run the manager with: ${GREEN}nsm${NC}"

exit 0 