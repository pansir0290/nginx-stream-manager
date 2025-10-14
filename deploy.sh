#!/bin/bash

# --- Configuration ---
REPO_URL="pansir0290/nginx-stream-manager"
MANAGER_SCRIPT="manager.sh"
TARGET_PATH="/usr/local/bin/nsm"
MAIN_CONF="/etc/nginx/nginx.conf"
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf" # 新增：用于检查和清理

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}--- Nginx Stream Manager (nsm) Deployment Script ---${NC}"

# --- 新增函数：检查并提示升级 Nginx ---
check_and_prompt_nginx_upgrade() {
    echo -e "\n${GREEN}--- Nginx 依赖检查与 UDP 支持验证 ---${NC}"

    if ! command -v nginx &> /dev/null; then
        echo -e "${YELLOW}警告：Nginx 未安装。请先运行 'sudo apt install nginx -y' 安装。${NC}"
        return
    fi
    
    # 清理旧的错误配置，以防测试失败
    echo "清理旧的 stream_proxy.conf 文件中的残留内容..."
    sudo > "$CONFIG_FILE"

    # 尝试用一个仅包含 TCP 监听的临时配置来测试 Nginx 是否能正常工作
    echo "测试 Nginx 基础配置..."
    if ! nginx -t &> /dev/null; then
        echo -e "${RED}严重错误：Nginx 基础配置测试失败，请在继续前手动检查 /etc/nginx/nginx.conf.${NC}"
        exit 1
    fi
    
    # 尝试用 UDP 监听配置来测试 Nginx 是否支持 UDP
    echo "    server { listen 12345 udp; proxy_pass 127.0.0.1:12345; }" | sudo tee -a "$CONFIG_FILE" > /dev/null
    
    echo "测试 Nginx 是否支持 Stream UDP..."
    if nginx -t &> /dev/null; then
        echo -e "${GREEN}✅ Nginx 版本支持 Stream UDP 转发。${NC}"
    else
        echo -e "${RED}❌ Nginx 配置测试失败，错误信息表明不支持 'udp' 参数。${NC}"
        echo "   这通常是 Nginx 缺少编译参数 (--with-stream_udp) 或版本过旧导致的。"
        echo -e "   ${YELLOW}请手动运行以下命令升级 Nginx，然后重新运行本脚本：${NC}"
        echo -e "   ${YELLOW}    sudo apt update && sudo apt upgrade nginx -y${NC}"
        # 退出，让用户解决依赖问题
        exit 1
    fi
    
    # 清理临时测试配置
    sudo > "$CONFIG_FILE"
}

# --- 自动化配置 Nginx 主配置的函数 (保留并优化) ---
configure_nginx_main() {
    echo -e "\n${GREEN}--- 检查并配置 Nginx 主配置文件 ---${NC}"

    if ! command -v nginx &> /dev/null; then
        return
    fi
    
    # 1. 检查 stream 块是否已存在于主配置
    if grep -q "^stream {" "$MAIN_CONF"; then
        echo -e "${GREEN}Nginx 主配置 ($MAIN_CONF) 中已存在 'stream' 块。跳过修改。${NC}"
        return
    fi

    echo "未检测到顶级 'stream' 块。正在自动插入配置..."
    STREAM_CONFIG="stream {\n    include /etc/nginx/conf.d/stream_proxy.conf;\n}"

    # 2. 寻找插入点：在 events {} 块的闭合 '}' 之后插入
    
    # 找到包含 'events {' 的行号
    EVENTS_START_LINE=$(grep -n "^events {" "$MAIN_CONF" | head -n 1 | cut -d: -f1)
    
    if [ -n "$EVENTS_START_LINE" ]; then
        # 从 events 开始行向下找到第一个 '}'，即 events 块的闭合行
        EVENTS_END_LINE=$(sed -n "${EVENTS_START_LINE},\$p" "$MAIN_CONF" | grep -n "}" | head -n 1 | cut -d: -f1)
        
        if [ -n "$EVENTS_END_LINE" ]; then
            # 计算 events 块结束的实际行号
            END_OF_EVENTS=$((EVENTS_START_LINE + EVENTS_END_LINE - 1))
            
            # 使用 sed 在 events 块结束行的下一行插入 stream 块
            # 使用 'a\\' 插入新行
            sudo sed -i "${END_OF_EVENTS}a\\${STREAM_CONFIG}" "$MAIN_CONF"
            # 插入一个空行保持格式
            sudo sed -i "${END_OF_EVENTS}a\\" "$MAIN_CONF"
            
            echo -e "${GREEN}'stream' 块已成功插入到 $MAIN_CONF 中。${NC}"
            return
        fi
    fi
    
    echo -e "${RED}错误：无法在 $MAIN_CONF 中定位插入点，请手动配置 Nginx。${NC}"
}


# --- 脚本主要流程 ---

# 0. Nginx 兼容性检查和升级提示 (新前置步骤)
check_and_prompt_nginx_upgrade

# 1. 检查 Nginx 依赖 (Warning only) - 已合并到 check_and_prompt_nginx_upgrade

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

# 5. 自动化配置 Nginx 主配置 (确保顶级 stream {} 存在)
configure_nginx_main

# 6. Set user-friendly function (nsm) 
# ... (保持不变) ...

# 自动检测并选择 Shell 配置文件
ALIAS_COMMAND="nsm() { sudo $TARGET_PATH \"\$@\"; }"
ALIAS_CHECK="nsm()"
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
echo -e "💡 要启动管理器，请先执行 ${YELLOW}source $SHELL_CONFIG${NC}，然后运行 ${GREEN}nsm${NC}"
echo -e "    或者，使用最初的 '一键启动' 命令启动菜单："
echo -e "    ${YELLOW}sudo curl -fsSL https://raw.githubusercontent.com/${REPO_URL}/main/deploy.sh | bash; source $SHELL_CONFIG; nsm${NC}"

exit 0