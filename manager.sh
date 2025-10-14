#!/bin/bash

# --- Script Configuration ---
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_SERVICE="nginx"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---

setup_environment() {
    echo -e "${GREEN}--- Checking Environment and Nginx Configuration ---${NC}"

    if ! command -v nginx &> /dev/null; then
        echo -e "${RED}ERROR: Nginx is not installed. Exiting.${NC}"
        exit 1
    fi

    # 确保 /etc/nginx/conf.d 存在
    if [ ! -d "/etc/nginx/conf.d" ]; then
        echo "Creating config directory /etc/nginx/conf.d"
        mkdir -p /etc/nginx/conf.d
    fi
    
    # 确保 stream 配置文件的存在和正确结构
    # 检查文件是否存在，或文件存在但缺少 stream {} 块
    if [ ! -f "$CONFIG_FILE" ] || ! grep -q "^stream {" "$CONFIG_FILE"; then
        echo "Creating initial Stream configuration file: $CONFIG_FILE"
        {
            echo "stream {"
            echo "}"
        } | tee "$CONFIG_FILE" > /dev/null
    fi

    # 提醒主配置文件的 include
    if ! grep -q "include /etc/nginx/conf.d/\*.conf;" "$MAIN_CONF"; then
        echo -e "${YELLOW}WARNING: Nginx main config ($MAIN_CONF) may be missing 'include /etc/nginx/conf.d/*.conf;'$NC"
        echo -e "${YELLOW}请确保 Nginx 主配置正确加载了 Stream 模块和 conf.d 目录下的配置文件。${NC}"
    fi
}

generate_config_block() {
    local LISTEN_PORT=$1
    local TARGET_ADDR=$2
    local USE_SSL=$3
    local SSL_NAME=$4

    # 使用 Tab 缩进，与 Nginx 配置风格保持一致
    cat << EOF
    server {
        listen ${LISTEN_PORT};
        listen ${LISTEN_PORT} udp;
        proxy_connect_timeout 20s;
        proxy_timeout 5m;
        
        # Rule Identifier: ${LISTEN_PORT} -> ${TARGET_ADDR}
EOF

    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        cat << EOF
        ssl_preread on;
        proxy_ssl_name ${SSL_NAME};
EOF
    fi

    cat << EOF
        proxy_pass ${TARGET_ADDR};
    }
EOF
}

# --- Feature 1: Add Rule ---
add_rule() {
    echo -e "\n${GREEN}--- Add New Forwarding Rule ---${NC}"
    read -r -p "Enter Listen Port (e.g., 55203): " LISTEN_PORT
    
    # 检查端口是否为空
    if [ -z "$LISTEN_PORT" ]; then
        echo -e "${RED}Listen Port cannot be empty.${NC}"
        return
    fi
    
    # 检查规则是否已存在
    if grep -q "listen ${LISTEN_PORT};" "$CONFIG_FILE"; then
        echo -e "${RED}Rule for port ${LISTEN_PORT} already exists in $CONFIG_FILE. Skipping.${NC}"
        return
    fi

    read -r -p "Enter Target Address (IP:Port, e.g., 31.56.123.199:55203): " TARGET_ADDR
    
    # 检查目标地址格式
    if [[ ! "$TARGET_ADDR" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{1,5}$ ]]; then
        echo -e "${RED}Invalid Target Address format. Must be IP:Port (e.g., 1.1.1.1:443).${NC}"
        return
    fi
    
    read -r -p "Enable SSL Preread? (y/n): " USE_SSL

    local SSL_NAME=""
    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        read -r -p "Enter proxy_ssl_name (e.g., yahoo.com or your_domain.com): " SSL_NAME
        if [ -z "$SSL_NAME" ]; then
            SSL_NAME="default_sni" # 提供一个默认值
            echo -e "${YELLOW}Using default proxy_ssl_name: ${SSL_NAME}${NC}"
        fi
    fi

    CONFIG_BLOCK=$(generate_config_block "$LISTEN_PORT" "$TARGET_ADDR" "$USE_SSL" "$SSL_NAME")

    # 查找 stream {} 块的最后一个 '}' 所在行
    # 这里使用 grep 查找最后一个 '}'，以确保插入到 stream {} 块内部的末尾
    local END_LINE=$(grep -n "^}" "$CONFIG_FILE" | tail -n 1 | cut -d: -f1)
    
    if [ -n "$END_LINE" ] && [ "$END_LINE" -gt 1 ]; then
        # 在最后一个 '}' 之前插入配置块
        echo "$CONFIG_BLOCK" | sed -i "$((END_LINE - 1))r /dev/stdin" "$CONFIG_FILE"
        echo -e "${GREEN}Rule for port ${LISTEN_PORT} added to $CONFIG_FILE.${NC}"
        read -r -p "Apply config and reload Nginx now? (y/n): " APPLY_NOW
        if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
            apply_config
        fi
    else
        echo -e "${RED}ERROR: Could not find '}' to insert config. Check $CONFIG_FILE manually.${NC}"
    fi
}

# --- Feature 2: View Rules ---
view_rules() {
    echo -e "\n${GREEN}--- Current Stream Forwarding Configuration (${CONFIG_FILE}) ---${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        # 使用 awk 排除 stream {} 块的起始和结束行，只显示 server 块内容，并添加索引
        if [ "$(grep -c "server {" "$CONFIG_FILE")" -eq 0 ]; then
             echo "No forwarding rules currently configured."
             return
        fi

        awk '
        /^stream \{/ {next} 
        /^\}$/ {next} 
        /server \{/ {
            count++; 
            print "\n--- RULE " count " ---"
            print $0
            next
        }
        # 移除 server {} 块的缩进并打印
        {
            print $0
        }' "$CONFIG_FILE"
        
    else
        echo -e "${RED}Configuration file not found.${NC}"
    fi
    echo ""
}

# --- Feature 3: Delete Rule ---
delete_rule() {
    view_rules
    
    if [ "$(grep -c "server {" "$CONFIG_FILE")" -eq 0 ]; then
        echo -e "${RED}No forwarding rules to delete.${NC}"
        return
    fi
    
    read -r -p "Enter Listen Port of the rule to delete: " PORT_TO_DELETE
    
    if [ -z "$PORT_TO_DELETE" ]; then
        echo -e "${RED}Port number cannot be empty.${NC}"
        return
    fi

    # 1. 检查规则是否存在，并找到 listen 行
    LISTEN_LINE=$(grep -n "listen ${PORT_TO_DELETE};" "$CONFIG_FILE" | cut -d: -f1 | head -n 1)

    if [ -z "$LISTEN_LINE" ]; then
        echo -e "${RED}Rule listening on port ${PORT_TO_DELETE} not found.${NC}"
        return
    fi

    # 2. 找到包含 LISTEN_LINE 的 server {} 块的起始和结束行
    
    # 从文件开头到 LISTEN_LINE 向上查找最近的 "server {" 所在行号
    SERVER_START=$(sed -n "1,${LISTEN_LINE}p" "$CONFIG_FILE" | grep -n "server {" | tail -n 1 | cut -d: -f1)

    # 从 SERVER_START 开始，向下查找第一个 "}"
    # 这里用 tac 和 sed 的组合可以更精确地找到匹配的 '}'，但为了兼容性，使用基于行号的方法
    
    # 查找 SERVER_START 行之后的第一个 '}'
    SERVER_END_OFFSET=$(sed -n "${SERVER_START},\$p" "$CONFIG_FILE" | grep -n "}" | head -n 1 | cut -d: -f1)
    
    # 计算实际的结束行号
    SERVER_END=$((SERVER_START + SERVER_END_OFFSET - 1))
    
    if [ -n "$SERVER_START" ] && [ -n "$SERVER_END" ] && [ "$SERVER_START" -lt "$SERVER_END" ]; then
        echo -e "${GREEN}Deleting rule block for port ${PORT_TO_DELETE} from line $SERVER_START to $SERVER_END...${NC}"
        
        # 删除行范围
        sed -i "${SERVER_START},${SERVER_END}d" "$CONFIG_FILE"
        
        echo -e "${GREEN}Rule deleted.${NC}"
        read -r -p "Apply config and reload Nginx now? (y/n): " APPLY_NOW
        if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
            apply_config
        fi
    else
        echo -e "${RED}Deletion failed: Could not locate complete server block (Start: $SERVER_START, End: $SERVER_END). Check file manually.${NC}"
    fi
}

# --- Feature 4: Apply Config and Reload Nginx ---
apply_config() {
    echo -e "\n${GREEN}--- Testing Nginx Configuration ---${NC}"
    # 使用 -t 检查配置，并将错误和警告输出到 stderr，如果成功则只输出成功的消息
    if nginx -t 2>&1 | grep -q "syntax is ok"; then
        echo -e "${GREEN}Config test successful! Reloading Nginx...${NC}"
        if systemctl reload "$NGINX_SERVICE"; then
            echo -e "${GREEN}Nginx reloaded, new rules are active.${NC}"
        else
            echo -e "${RED}ERROR: Nginx reload failed. Check system logs for details (e.g., journalctl -xe).${NC}"
        fi
    else
        echo -e "${RED}Config test failed. New config NOT applied.${NC}"
        # 再次运行，以便用户查看具体的错误信息
        nginx -t
    fi
}

# --- Main Menu ---
main_menu() {
    # 检查是否以 root 权限运行
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}ERROR: This script must be run with root privileges (sudo).${NC}"
        exit 1
    fi
    
    # Setup environment (creates files if needed)
    setup_environment

    while true; do
        echo -e "\n${GREEN}=============================================${NC}"
        echo -e "${GREEN} Nginx Stream Manager (v1.0) ${NC}"
        echo -e "${GREEN}=============================================${NC}"
        echo "1. Add New Forwarding Rule"
        echo "2. View Current Forwarding Rules"
        echo "3. Delete Forwarding Rule (by Listen Port)"
        echo "4. Apply Config and Reload Nginx (Make changes live)"
        echo "5. Exit"
        echo -e "${GREEN}=============================================${NC}"
        
        read -r -p "Select an operation [1-5]: " CHOICE

        case "$CHOICE" in
            1) add_rule ;;
            2) view_rules ;;
            3) delete_rule ;;
            4) apply_config ;;
            5) echo "Thank you for using the manager. Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid input, please select a number between 1 and 5.${NC}" ;;
        esac
    done
}

# --- Script Start ---
main_menu