#!/bin/bash

# --- 脚本配置 ---
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_SERVICE="nginx"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# --- 辅助函数 ---

setup_environment() {
    echo -e "${GREEN}--- 检查环境和 Nginx 配置 ---${NC}"

    if ! command -v nginx &> /dev/null; then
        echo -e "${RED}错误：Nginx 未安装。退出。${NC}"
        exit 1
    fi

    # 确保 /etc/nginx/conf.d 存在
    if [ ! -d "/etc/nginx/conf.d" ]; then
        echo "创建配置目录 /etc/nginx/conf.d"
        mkdir -p /etc/nginx/conf.d
    fi
    
    # 确保 stream 配置文件存在，但不写入 stream {} 块
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "创建空的 Stream 规则文件: $CONFIG_FILE"
        sudo touch "$CONFIG_FILE"
    fi

    # 提醒主配置文件的 include (现在主要由 deploy.sh 负责，但保留提醒)
    if ! grep -q "include /etc/nginx/conf.d/\*.conf;" "$MAIN_CONF"; then
        echo -e "${YELLOW}警告：Nginx 主配置 ($MAIN_CONF) 可能缺少 'include /etc/nginx/conf.d/*.conf;'$NC"
    fi
}

generate_config_block() {
    local LISTEN_PORT=$1
    local TARGET_ADDR=$2
    local USE_SSL=$3
    local SSL_NAME=$4
    local UDP_LINE=""

    # 运行时测试 Nginx 是否支持 UDP 参数
    local TEMP_TEST_CONF="/tmp/nsm_udp_test.conf"
    
    # 尝试用一个简单的 UDP 配置来测试 Nginx 是否能通过配置测试
    # 注意：使用 sudo 执行 nginx -t 是必要的，因为 nsm 也是用 sudo 运行的
    
    # 确保 /tmp 目录存在且可写
    if [ ! -d "/tmp" ]; then mkdir -p /tmp; fi

    # 构造一个包含 UDP 监听的临时完整 stream 块
    echo "stream { server { listen 12345 udp; proxy_pass 127.0.0.1:12345; } }" > "$TEMP_TEST_CONF"
    
    # 使用 sudo 权限测试配置
    if sudo nginx -t -c "$TEMP_TEST_CONF" &> /dev/null; then
        # 如果配置测试成功，说明支持 UDP
        UDP_LINE="        listen ${LISTEN_PORT} udp;"
        # echo -e "${YELLOW}提示: Nginx 当前支持 UDP 监听。${NC}" # 在运行时避免过多输出
    else
        # 如果配置测试失败，说明不支持 UDP
        echo -e "${YELLOW}警告: Nginx 不支持 UDP 监听（配置测试失败）。规则将仅监听 TCP。${NC}"
        UDP_LINE="# Nginx不支持UDP: listen ${LISTEN_PORT} udp;"
    fi
    
    sudo rm -f "$TEMP_TEST_CONF" # 清理临时文件

    # 使用 Tab 缩进，与 Nginx 配置风格保持一致
    cat << EOF

    server {
        listen ${LISTEN_PORT};
${UDP_LINE}
        proxy_connect_timeout 20s;
        proxy_timeout 5m;
        
        #