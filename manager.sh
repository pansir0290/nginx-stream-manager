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

# --- 辅助函数：环境检查 ---
setup_environment() {
    echo -e "\n${GREEN}--- 检查环境和 Nginx 配置 ---${NC}"

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
    if ! grep -q "include /etc/nginx/conf.d/*.conf;" "$MAIN_CONF"; then
        echo -e "${YELLOW}警告：Nginx 主配置 ($MAIN_CONF) 可能缺少 'include /etc/nginx/conf.d/*.conf;'$NC"
    fi
}

# --- 核心函数：生成配置块 (已移除超时指令和 UDP 监听) ---
generate_config_block() {
    local LISTEN_PORT=$1
    local TARGET_ADDR=$2
    local USE_SSL=$3
    local SSL_NAME=$4
    local CONFIG_BLOCK=""

    # 警告信息必须输出到标准错误流 (>&2)，以确保它不会被捕获到 CONFIG_BLOCK 变量中
    echo -e "${YELLOW}警告: 规则将仅监听 TCP 端口（UDP已注释）。${NC}" >&2
    
    local UDP_LINE="# Nginx不支持UDP: listen ${LISTEN_PORT} udp;"
    
    # 构建配置块，注意：移除了 proxy_connect_timeout 和 proxy_timeout
    CONFIG_BLOCK="\n    server {\n        listen ${LISTEN_PORT};\n${UDP_LINE}\n        # 超时指令已在 /etc/nginx/nginx.conf 的 stream {} 块中全局设置\n        # 规则标识符: ${LISTEN_PORT} -> ${TARGET_ADDR}"

    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        CONFIG_BLOCK+="\n        ssl_preread on;"
        CONFIG_BLOCK+="\n        proxy_ssl_name ${SSL_NAME};"
    fi

    CONFIG_BLOCK+="\n        proxy_pass ${TARGET_ADDR};\n    }"
    
    # 返回生成的配置块
    echo -e "$CONFIG_BLOCK"
}

# --- 功能 1: 配置 SELinux ---
configure_selinux() {
    echo -e "\n${GREEN}--- 配置 SELinux 策略 ---${NC}"
    
    if ! command -v getenforce &> /dev/null; then
        echo -e "${YELLOW}警告：系统似乎没有安装 SELinux 工具（如 getenforce, semanage）。跳过配置。${NC}"
        return
    fi
    
    CURRENT_STATUS=$(getenforce)
    echo "当前 SELinux 状态: ${YELLOW}${CURRENT_STATUS}${NC}"

    echo -e "\n请选择 SELinux 应对策略："
    echo "1. 永久禁用 SELinux (最彻底，但需要重启才能生效)"
    echo "2. 仅放宽 Nginx 策略 (推荐，更安全)"
    echo "3. 退出菜单，不修改"
    
    read -r -p "请选择操作 [1-3]: " SELINUX_CHOICE

    case "$SELINUX_CHOICE" in
        1) 
            echo -e "${RED}警告：选择禁用 SELinux！此操作需要重启服务器才能完全生效。${NC}"
            sudo sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config
            echo -e "${GREEN}配置已修改为 'SELINUX=disabled'。请在方便时重启系统。${NC}"
            ;;
        2) 
            if ! command -v setsebool &> /dev/null || ! command -v semanage &> /dev/null; then
                echo -e "${RED}错误：缺少 'setsebool' 或 'semanage' 工具。请安装相关包。${NC}"
                return
            fi
            
            echo "1. 允许 Nginx 发起网络连接 (setsebool -P httpd_can_network_connect on)"
            sudo setsebool -P httpd_can_network_connect on
            
            echo -e "${YELLOW}注意：端口策略可能需要手动添加，例如: sudo semanage port -a -t http_port_t -p tcp <端口号>${NC}"
            echo -e "${GREEN}Nginx 的网络代理权限已放宽。${NC}"
            
            if [ "$CURRENT_STATUS" != "enforcing" ]; then
                read -r -p "是否需要将 SELinux 状态临时设置为 Enforcing 来测试策略? (y/n): " TEMP_ENFORCE
                if [[ "$TEMP_ENFORCE" =~ ^[Yy]$ ]]; then
                    sudo setenforce 1
                    echo -e "${GREEN}SELinux 临时设置为 Enforcing。${NC}"
                fi
            fi
            ;;
        3) 
            echo "未进行 SELinux 配置修改。"
            ;;
        *) 
            echo -e "${RED}无效输入，请选择 1 到 3 之间的数字。${NC}"
            ;;
    esac
}


# --- 功能 2: 添加规则 ---
add_rule() {
    echo -e "\n${GREEN}--- 添加新的转发规则 ---${NC}"
    read -r -p "请输入监听端口 (例如: 55203): " LISTEN_PORT
    
    if [ -z "$LISTEN_PORT" ]; then echo -e "${RED}错误：监听端口不能为空。${NC}"; return; fi
    
    # 查找 listen 行并排除注释行
    if grep -q "^\s*listen ${LISTEN_PORT};" "$CONFIG_FILE"; then
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
            echo -e "${YELLOW}使用默认 proxy_ssl_name: ${SSL_NAME}${NC}" >&2 # 将此警告输出到 stderr
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

# --- 功能 3: 查看规则 ---
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

# --- 功能 4: 删除规则 ---
delete_rule() {
    view_rules
    
    if [ "$(grep -c "server {" "$CONFIG_FILE")" -eq 0 ]; then
        echo -e "${RED}没有可供删除的转发规则。${NC}"
        return
    fi
    
    read -r -p "请输入要删除规则的监听端口: " PORT_TO_DELETE
    
    if [ -z "$PORT_TO_DELETE" ]; then echo -e "${RED}错误：端口号不能为空。${NC}"; return; fi

    LISTEN_LINE=$(grep -n "listen ${PORT_TO_DELETE};"