#!/bin/bash

# --- 脚本配置 ---
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_SERVICE="nginx"
MANAGER_URL="https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/manager.sh"
MANAGER_PATH="/usr/local/bin/nsm"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- 核心函数：配置 Nginx 主配置文件 ---
configure_nginx_main_conf() {
    echo -e "\n--- 检查并配置 Nginx 主配置文件 ---"
    
    # 1. 检查 stream 块是否存在
    if ! grep -q "stream {" "$MAIN_CONF"; then
        echo -e "${YELLOW}警告: Nginx 主配置 ($MAIN_CONF) 中缺少 'stream {}' 块，尝试添加。${NC}"
        # 在 http 块之前添加 stream 块
        # 使用 sed 在 'http {' 之前插入 stream 块和 include
        sudo sed -i '/http {/i\
stream {\
    include /etc/nginx/conf.d/stream_proxy.conf;\
}\
' "$MAIN_CONF"
        echo -e "${GREEN}'stream {}' 块已添加到 $MAIN_CONF。${NC}"
    fi

    # 2. 确保 stream_proxy.conf 文件被 include 进 stream 块
    if ! grep -q "include /etc/nginx/conf.d/stream_proxy.conf;" "$MAIN_CONF"; then
        echo -e "${YELLOW}警告: 确保 stream_proxy.conf 被正确 include...${NC}"
        
        # 尝试在 stream { 块的内部添加 include
        if grep -q "stream {" "$MAIN_CONF"; then
            # 在 stream { 的下一行添加 include
            sudo sed -i '/stream {/a\    include /etc/nginx/conf.d/stream_proxy.conf;' "$MAIN_CONF"
            echo -e "${GREEN}已将 'include /etc/nginx/conf.d/stream_proxy.conf;' 添加到 stream 块中。${NC}"
        fi
    fi

    # 3. 添加全局超时配置 (如果不存在)
    # 使用较宽松的检查，避免重复添加，并防止与用户的现有配置冲突
    if ! grep -q "proxy_connect_timeout" "$MAIN_CONF"; then
        echo "Nginx 主配置 ($MAIN_CONF) 中缺少全局超时配置，尝试添加..."
        # 在 stream { 块内添加默认超时设置
        sudo sed -i '/stream {/a\    proxy_connect_timeout 20s;\n    proxy_timeout 5m;' "$MAIN_CONF"
        echo -e "${GREEN}全局超时配置已添加。${NC}"
    else
        echo "Nginx 主配置 ($MAIN_CONF) 中已存在 'stream' 块。正在检查全局超时配置..."
    fi

    # 4. 【新修复】检查并添加 Stream SSL 模块加载 (解决 ssl_preread 错误)
    # 查找是否有任何形式的 ngx_stream_ssl_module.so 加载指令
    if ! grep -q "load_module .*ngx_stream_ssl_module\.so;" "$MAIN_CONF"; then
        echo -e "${YELLOW}警告: Nginx Stream SSL 模块未加载，正在尝试添加。${NC}"
        
        # 尝试在 'worker_processes auto;' 之后添加 load_module 指令
        # 默认使用 Debian/Ubuntu 系统中最常见的路径
        SSL_MODULE_LINE="load_module /usr/lib/nginx/modules/ngx_stream_ssl_module.so;"
        
        # 查找 worker_processes 行，并在其后添加模块加载
        if grep -q "worker_processes" "$MAIN_CONF"; then
            sudo sed -i "/worker_processes/a\ ${SSL_MODULE_LINE}" "$MAIN_CONF"
            echo -e "${GREEN}Stream SSL 模块加载指令已添加到 $MAIN_CONF。${NC}"
        else
            echo -e "${RED}错误: 无法定位添加 load_module 的位置，请手动检查 $MAIN_CONF。${NC}"
        fi
    else
        echo -e "${GREEN}Nginx Stream SSL 模块加载指令已存在。${NC}"
    fi
}


# --- 部署函数 ---
deploy() {
    echo -e "\n--- Nginx Stream Manager (nsm) Deployment Script ---"
    
    # 检查是否以 root 权限运行
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须使用 root 权限 (sudo) 运行。${NC}"
        exit 1
    fi

    echo -e "\n--- Nginx 依赖检查 ---"
    if ! command -v nginx &> /dev/null; then
        echo -e "${RED}错误：Nginx 未安装。请先安装 Nginx。${NC}"
        exit 1
    fi

    # 创建配置目录和空文件
    sudo mkdir -p /etc/nginx/conf.d
    sudo touch "$CONFIG_FILE"
    echo "清理旧的 stream_proxy.conf 文件中的残留内容..."
    sudo truncate -s 0 "$CONFIG_FILE"

    # 检查 UDP 模块是否在 Nginx 主配置中被 include 或加载
    if ! grep -qE "load_module .*ngx_stream_udp_module\.so;|stream \{.*udp" "$MAIN_CONF"; then
        echo -e "${YELLOW}警告：已确认您的 Nginx 版本不支持 Stream UDP。${NC}"
        echo -e "${YELLOW}   脚本已配置为仅监听 TCP 端口，以确保配置通过。${NC}"
    fi

    # 下载 manager.sh
    echo "Downloading manager.sh from GitHub..."
    if sudo curl -fsSL "$MANAGER_URL" -o "$MANAGER_PATH"; then
        echo "Script downloaded successfully to $MANAGER_PATH"
        echo "Setting executable permissions..."
        sudo chmod +x "$MANAGER_PATH"
    else
        echo -e "${RED}错误：下载 manager.sh 失败。请检查网络连接。${NC}"
        exit 1
    fi

    # 配置 Nginx 主配置
    configure_nginx_main_conf

    echo -e "\n--- 部署后清理与服务启动准备 ---"
    
    # 清空规则文件中的残留内容
    echo "清空规则文件 $CONFIG_FILE 中的残留内容..."
    sudo truncate -s 0 "$CONFIG_FILE"

    # 尝试重启 Nginx 服务
    echo "尝试重启 Nginx 服务以加载新的 stream 模块配置..."
    if sudo systemctl restart "$NGINX_SERVICE" 2>/dev/null; then
        echo -e "${GREEN}Nginx 服务重启成功，已加载 Stream 模块。${NC}"
    elif sudo service "$NGINX_SERVICE" restart 2>/dev/null; then
        echo -e "${GREEN}Nginx 服务重启成功，已加载 Stream 模块。${NC}"
    else
        echo -e "${YELLOW}警告：Nginx 服务重启失败（可能是首次安装）。请手动检查。${NC}"
    fi

    # 添加 nsm 别名到 ~/.bashrc (如果不存在)
    if ! grep -q "alias nsm=" "$HOME/.bashrc"; then
        echo "alias nsm='sudo $MANAGER_PATH'" >> "$HOME/.bashrc"
        echo -e "${GREEN}已将 'nsm' 别名添加到 ~/.bashrc。${NC}"
    else
        echo "'nsm' alias already exists in $HOME/.bashrc. Skipping addition."
    fi

    echo -e "\n--- Deployment Complete! ---"
    echo -e "${GREEN}✅ The setup is complete.${NC} Nginx 服务已尝试重启。"
    echo -e "💡 To start the manager, run the original 'one-click' command to start the menu:"
    echo -e "   sudo curl -fsSL $MANAGER_URL | bash; source ~/.bashrc; nsm"
}

# --- 脚本开始 ---
deploy