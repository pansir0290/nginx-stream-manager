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
        sudo mkdir -p /etc/nginx/conf.d
    fi
    
    # 确保 stream 配置文件存在
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "创建空的 Stream 规则文件: $CONFIG_FILE"
        sudo touch "$CONFIG_FILE"
    fi

    # 提醒主配置文件的 include
    if ! grep -q "include /etc/nginx/conf.d/\*.conf;" "$MAIN_CONF"; then
        echo -e "${YELLOW}警告：Nginx 主配置 ($MAIN_CONF) 可能缺少 'include /etc/nginx/conf.d/*.conf;'$NC"
    fi
}

# --- 核心修改：使用 echo >&2 隔离警告，确保输出的配置干净 ---
generate_config_block() {
    local LISTEN_PORT=$1
    local TARGET_ADDR=$2
    local USE_SSL=$3
    local SSL_NAME=$4
    local CONFIG_BLOCK=""

    # 警告信息必须输出到标准错误流 (>&2)，以确保它不会被捕获到 CONFIG_BLOCK 变量中
    echo -e "${YELLOW}警告: 规则将仅监听 TCP 端口（UDP已注释）。${NC}" >&2
    
    local UDP_LINE="# Nginx不支持UDP: listen ${LISTEN_PORT} udp;"
    
    # 构建配置块，使用 \n 和 tab 缩进
    CONFIG_BLOCK="\n    server {\n        listen ${LISTEN_PORT};\n${UDP_LINE}\n        proxy_connect_timeout 20s;\n        proxy_timeout 5m;\n        # 规则标识符: ${LISTEN_PORT} -> ${TARGET_ADDR}"

    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        CONFIG_BLOCK+="\n        ssl_preread on;\n        proxy_ssl_name ${SSL_NAME};"
    fi

    CONFIG_BLOCK+="\n        proxy_pass ${TARGET_ADDR};\n    }"
    
    # 返回生成的配置块
    echo -e "$CONFIG_BLOCK"
}
# --- 核心修改结束 ---

# --- 功能 1: 添加规则 ---
add_rule() {
    echo -e "\n${GREEN}--- 添加新的转发规则 ---${NC}"
    read -r -p "请输入监听端口 (例如: 55203): " LISTEN_PORT
    
    if [ -z "$LISTEN_PORT" ]; then echo -e "${RED}错误：监听端口不能为空。${NC}"; return; fi
    
    if grep -q "listen ${LISTEN_PORT};" "$CONFIG_FILE"; then
        echo -e "${RED}错误：端口 ${LISTEN_PORT} 的规则已存在，请勿重复添加。${NC}"
        return
    fi

    read -r -p "请输入目标地址 (IP:Port, 例如: 31.56.123.199:55203): " TARGET_ADDR
    
    if [[ ! "$TARGET_ADDR" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]{1,5}$ ]]; then
        echo -e "${RED}错误：目标地址格式无效。必须是 IP:Port (例如: 1.1.1.1:443)。${NC}"
        return
    fi
    
    read -r -p "是否启用 SSL 预读 (ssl_preread on)? (y/n): " USE_SSL

    local SSL_NAME=""
    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        read -r -p "请输入 proxy_ssl_name (例如: yahoo.com 或 your_domain.com): " SSL_NAME
        if [ -z "$SSL_NAME" ]; then
            SSL_NAME="default_sni" 
            echo -e "${YELLOW}使用默认 proxy_ssl_name: ${SSL_NAME}${NC}" >&2 # 同样将此警告输出到 stderr
        fi
    fi

    # 捕获 generate_config_block 的输出 (配置块)
    CONFIG_BLOCK=$(generate_config_block "$LISTEN_PORT" "$TARGET_ADDR" "$USE_SSL" "$SSL_NAME")

    # 将配置块追加到文件末尾
    echo -e "$CONFIG_BLOCK" | sudo tee -a "$CONFIG_FILE" > /dev/null
    
    echo -e "${GREEN}端口 ${LISTEN_PORT} 的规则已成功添加到 $CONFIG_FILE。${NC}"
    read -r -p "是否立即应用配置并重载 Nginx? (y/n): " APPLY_NOW
    if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
        apply_config
    fi
}

# --- 功能 2: 查看规则 ---
view_rules() {
    echo -e "\n${GREEN}--- 当前 Stream 转发配置 (${CONFIG_FILE}) ---${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        if [ "$(grep -c "server {" "$CONFIG_FILE")" -eq 0 ]; then
             echo "当前未配置任何转发规则。"
             return
        fi

        awk '
        /server \{/ {
            count++; 
            print "\n--- 规则 " count " ---"
            print $0
            next
        }
        {
            print $0
        }' "$CONFIG_FILE"
        
    else
        echo -e "${RED}错误：配置文件未找到。${NC}"
    fi
    echo ""
}

# --- 功能 3: 删除规则 ---
delete_rule() {
    view_rules
    
    if [ "$(grep -c "server {" "$CONFIG_FILE")" -eq 0 ]; then
        echo -e "${RED}没有可供删除的转发规则。${NC}"
        return
    fi
    
    read -r -p "请输入要删除规则的监听端口: " PORT_TO_DELETE
    
    if [ -z "$PORT_TO_DELETE" ]; then echo -e "${RED}错误：端口号不能为空。${NC}"; return; fi

    LISTEN_LINE=$(grep -n "listen ${PORT_TO_DELETE};" "$CONFIG_FILE" | cut -d: -f1 | head -n 1)

    if [ -z "$LISTEN_LINE" ]; then
        echo -e "${RED}错误：未找到监听端口 ${PORT_TO_DELETE} 的规则。${NC}"
        return
    fi

    SERVER_START=$(sed -n "1,${LISTEN_LINE}p" "$CONFIG_FILE" | grep -n "server {" | tail -n 1 | cut -d: -f1)
    SERVER_END_OFFSET=$(sed -n "${SERVER_START},\$p" "$CONFIG_FILE" | grep -n "}" | head -n 1 | cut -d: -f1)
    SERVER_END=$((SERVER_START + SERVER_END_OFFSET - 1))
    
    if [ -n "$SERVER_START" ] && [ "$SERVER_END" ] && [ "$SERVER_START" -lt "$SERVER_END" ]; then
        echo -e "${GREEN}正在删除端口 ${PORT_TO_DELETE} 的规则块 (行 $SERVER_START 到 $SERVER_END)...${NC}"
        
        sudo sed -i "${SERVER_START},${SERVER_END}d" "$CONFIG_FILE"
        
        echo -e "${GREEN}规则已删除。${NC}"
        read -r -p "是否立即应用配置并重载 Nginx? (y/n): " APPLY_NOW
        if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
            apply_config
        fi
    else
        echo -e "${RED}错误：无法定位完整的 server 块。请手动检查文件。${NC}"
    fi
}

# --- 功能 4: 应用配置并重载 Nginx ---
apply_config() {
    echo -e "\n${GREEN}--- 测试 Nginx 配置 ---${NC}"
    
    if nginx -t 2>&1 | grep -q "syntax is ok"; then
        echo -e "${GREEN}配置测试成功! 正在重载 Nginx...${NC}"
        if sudo systemctl reload "$NGINX_SERVICE"; then
            echo -e "${GREEN}Nginx 重载成功，新规则已生效。${NC}"
        else
            echo -e "${RED}错误：Nginx 重载失败。请检查系统日志 (例如: journalctl -xe)。${NC}"
        fi
    else
        echo -e "${RED}配置测试失败。新配置未应用。${NC}"
        sudo nginx -t
    fi
}

# --- 主菜单 ---
main_menu() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须使用 root 权限 (sudo) 运行。${NC}"
        exit 1
    fi
    
    setup_environment

    while true; do
        echo -e "\n${GREEN}=============================================${NC}"
        echo -e "${GREEN} Nginx Stream 转发管理器 (v1.0) ${NC}"
        echo -e "${GREEN}=============================================${NC}"
        echo "1. 添加新的转发规则"
        echo "2. 查看当前转发规则"
        echo "3. 删除转发规则 (按监听端口)"
        echo "4. 应用配置并重载 Nginx (使更改生效)"
        echo "5. 退出"
        echo -e "${GREEN}=============================================${NC}"
        
        read -r -p "请选择操作 [1-5]: " CHOICE

        case "$CHOICE" in
            1) add_rule ;;
            2) view_rules ;;
            3) delete_rule ;;
            4) apply_config ;;
            5) echo "感谢使用管理器。再见！"; exit 0 ;;
            *) echo -e "${RED}无效输入，请选择 1 到 5 之间的数字。${NC}" ;;
        esac
    done
}

# --- 脚本开始 ---
main_menu