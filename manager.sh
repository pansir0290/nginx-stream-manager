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
        # 考虑到用户的配置，我们更精确地检查 stream_proxy.conf 是否被 include
        if ! grep -q "include /etc/nginx/conf.d/stream_proxy.conf;" "$MAIN_CONF"; then
            echo -e "${YELLOW}警告：Nginx 主配置 ($MAIN_CONF) 可能缺少 'include /etc/nginx/conf.d/stream_proxy.conf;'${NC}"
        fi
    fi
}

# --- 核心函数：生成配置块 (回退到直接代理 IP:Port) ---
generate_config_block() {
    local LISTEN_PORT=$1
    local TARGET_ADDR=$2
    local USE_SSL=$3
    local SSL_NAME=$4
    local CONFIG_BLOCK=""
    
    echo -e "${YELLOW}警告: 规则将仅监听 TCP 端口（UDP已注释）。${NC}" >&2
    
    local UDP_LINE="# Nginx不支持UDP: listen ${LISTEN_PORT} udp;"
    
    # 使用 here-doc (<<-) 来构建配置块，仅生成 server 块
    CONFIG_BLOCK=$(cat <<- EOM
    
    server {
        listen ${LISTEN_PORT};
${UDP_LINE}
        # 规则标识符: ${LISTEN_PORT} -> ${TARGET_ADDR}
EOM
)

    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        CONFIG_BLOCK+="\n        ssl_preread on;"
        CONFIG_BLOCK+="\n        proxy_ssl_name ${SSL_NAME};"
    fi

    CONFIG_BLOCK+="\n        proxy_connect_timeout 20s;"
    CONFIG_BLOCK+="\n        proxy_timeout 5m;"
    # 核心修改：proxy_pass 直接指向 IP:Port
    CONFIG_BLOCK+="\n        proxy_pass ${TARGET_ADDR};\n    }"
    
    # 返回生成的配置块
    echo -e "$CONFIG_BLOCK"
}

# --- 功能 1: 安装依赖 (未更改，用于 SELinux) ---
install_dependencies() {
    echo -e "\n${GREEN}--- 安装 SELinux/系统依赖 ---${NC}"
    
    if command -v apt &> /dev/null; then
        echo -e "${YELLOW}检测到 Debian/Ubuntu 系统。${NC}"
        # 针对 Debian/Ubuntu 系统，安装 policycoreutils 和 selinux-utils，确保 setsebool/semanage 存在。
        read -r -p "是否运行 'sudo apt update' 并安装完整的 SELinux 管理工具 (policycoreutils selinux-utils)? (y/n): " INSTALL_CONFIRM
        if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
            sudo apt update
            # 同时安装这两个包，以确保获得 setsebool 和 semanage
            sudo apt install -y policycoreutils selinux-utils
            echo -e "${GREEN}SELinux 管理工具 (policycoreutils, selinux-utils) 安装尝试完成。${NC}"
            
            # 额外检查是否成功安装（使用绝对路径）
            if [ -x "/usr/sbin/setsebool" ] && [ -x "/usr/sbin/semanage" ]; then
                echo -e "${GREEN}✅ setsebool 和 semanage 现已可用。${NC}"
            else
                echo -e "${YELLOW}⚠️ 某些 SELinux 工具可能仍然缺失或不在 PATH 中。${NC}"
            fi
        fi
    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        echo -e "${YELLOW}检测到 RHEL/CentOS/Fedora 系统。${NC}"
        read -r -p "是否安装 SELinux 管理工具 (policycoreutils-python-utils)? (y/n): " INSTALL_CONFIRM
        if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
            sudo $(command -v dnf || echo "yum") install -y policycoreutils-python-utils
            echo -e "${GREEN}SELinux 管理工具安装完成。${NC}"
        fi
    else
        echo -e "${RED}错误：无法识别您的包管理器。请手动安装 SELinux 管理工具包。${NC}"
    fi
}


# --- 功能 2: 配置 SELinux (未更改，用于 SELinux) ---
configure_selinux() {
    echo -e "\n${GREEN}--- 配置 SELinux 策略 ---${NC}"
    
    # 检查 SELinux 核心工具是否存在
    if ! command -v getenforce &> /dev/null; then
        echo -e "${YELLOW}警告：系统似乎没有安装 SELinux 工具。请先运行选项 1 安装依赖。${NC}"
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
            # --- 修复后的检查和命令：使用绝对路径 /usr/sbin/ ---
            if [ ! -x "/usr/sbin/setsebool" ] || [ ! -x "/usr/sbin/semanage" ]; then
                echo -e "${RED}错误：缺少 '/usr/sbin/setsebool' 或 '/usr/sbin/semanage' 工具。${NC}"
                echo -e "${YELLOW}请确保您已运行选项 1。如果问题仍然存在，请手动检查 /usr/sbin 目录。${NC}"
                return
            fi
            
            echo "1. 允许 Nginx 发起网络连接 (/usr/sbin/setsebool -P httpd_can_network_connect on)"
            sudo /usr/sbin/setsebool -P httpd_can_network_connect on
            
            echo -e "${YELLOW}注意：端口策略可能需要手动添加，例如: sudo /usr/sbin/semanage port -a -t http_port_t -p tcp <端口号>${NC}"
            
            # 使用绝对路径执行 semanage
            if ! sudo /usr/sbin/semanage port -l &> /dev/null; then
                 echo -e "${YELLOW}警告：semanage 运行时可能需要额外配置或权限。${NC}"
            fi

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


# --- 功能 3: 添加规则 ---
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
            SSL_NAME="www.yahoo.com" 
            echo -e "${YELLOW}使用默认 proxy_ssl_name: ${SSL_NAME}${NC}" >&2 
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

# --- 功能 4: 查看规则 (简化，不再区分 Upstream) ---
view_rules() {
    echo -e "\n${GREEN}--- 当前 Stream 转发配置 (${CONFIG_FILE}) ---${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        if [ "$(grep -c "server {" "$CONFIG_FILE")" -eq 0 ]; then
             echo "当前未配置任何转发规则。"
             return
        fi

        # 仅显示 server 块内容
        awk '
        /server \{/ {
            print "\n--- SERVER 块 ---"
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

# --- 功能 5: 删除规则 (简化删除逻辑，仅删除 server 块) ---
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
    
    # 1. 查找 Server 块的起始和结束行
    SERVER_START=$(sed -n "1,${LISTEN_LINE}p" "$CONFIG_FILE" | grep -n "server {" | tail -n 1 | cut -d: -f1)
    SERVER_END_OFFSET=$(sed -n "${SERVER_START},\$p" "$CONFIG_FILE" | grep -n "}" | head -n 1 | cut -d: -f1)
    SERVER_END=$((SERVER_START + SERVER_END_OFFSET - 1))
    
    if [ -n "$SERVER_START" ] && [ "$SERVER_END" ] && [ "$SERVER_START" -lt "$SERVER_END" ]; then
        echo -e "${GREEN}正在删除端口 ${PORT_TO_DELETE} 的 SERVER 规则块 (行 $SERVER_START 到 $SERVER_END)...${NC}"
        
        # 删除 Server 块
        sudo sed -i "${SERVER_START},${SERVER_END}d" "$CONFIG_FILE"
        
        sudo sed -i '/^$/d' "$CONFIG_FILE" # 清理多余空行

        echo -e "${GREEN}规则已删除。${NC}"
        read -r -p "是否立即应用配置并重载 Nginx? (y/n): " APPLY_NOW
        if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
            apply_config
        fi
    else
        echo -e "${RED}错误：无法定位完整的 server 块。请手动检查文件。${NC}"
    fi
}


# --- 功能 6: 应用配置并重载 Nginx (未更改) ---
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
        echo "1. 安装 SELinux/系统依赖"
        echo "2. 配置 SELinux (解决连接被拒问题)"
        echo "3. 添加新的转发规则"
        echo "4. 查看当前转发规则"
        echo "5. 删除转发规则 (按监听端口)"
        echo "6. 应用配置并重载 Nginx (使更改生效)"
        echo "7. 退出"
        echo -e "${GREEN}=============================================${NC}"
        
        read -r -p "请选择操作 [1-7]: " CHOICE

        case "$CHOICE" in
            1) install_dependencies ;; 
            2) configure_selinux ;; 
            3) add_rule ;;
            4) view_rules ;;
            5) delete_rule ;;
            6) apply_config ;;
            7) echo "感谢使用管理器。再见！"; exit 0 ;;
            *) echo -e "${RED}无效输入，请选择 1 到 7 之间的数字。${NC}" ;;
        esac
    done
}

# --- 脚本开始 ---
main_menu