#!/bin/bash
# Nginx Stream Manager v4.0 - 优化UI版
# 作者：您的名字
# 更新日期：$(date +%Y-%m-%d)

# ANSI颜色代码
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # 重置颜色
BOLD='\033[1m'

# 配置路径
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
NGINX_CONF="/etc/nginx/nginx.conf"
BACKUP_DIR="/etc/nginx/conf.d/backups"
LOG_FILE="/var/log/nsm.log"

# 安装模式处理
if [ "$1" == "--install" ]; then
    echo -e "${GREEN}▶ 安装Nginx Stream Manager...${NC}"
    echo -e "${CYAN}1. 下载主脚本${NC}"
    curl -fsSL -o /usr/local/bin/nsm-manager \
        https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/manager.sh
    chmod +x /usr/local/bin/nsm-manager
    
    echo -e "${CYAN}2. 创建命令行别名${NC}"
    if ! grep -q "alias nsm=" ~/.bashrc; then
        echo "alias nsm='sudo nsm-manager'" >> ~/.bashrc
    fi
    source ~/.bashrc
    
    echo -e "${CYAN}3. 初始化配置${NC}"
    mkdir -p "$(dirname "$CONFIG_FILE")" &>/dev/null
    mkdir -p "$BACKUP_DIR" &>/dev/null
    
    echo -e "${GREEN}✅ 安装完成！${NC}"
    echo -e "使用 ${YELLOW}nsm menu${NC} 启动管理界面"
    sleep 2
    nsm-manager menu
    exit 0
fi

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须使用sudo或root运行${NC}"
        exit 1
    fi
}

# 获取Nginx状态
nginx_status() {
    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}已停止${NC}"
    fi
}

# 显示标题
show_header() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║   ${BOLD}Nginx Stream Manager ${MAGENTA}v4.0${NC}${CYAN}   ║"
    echo "╟───────────────────────────────────────────╢"
    echo "║  状态: $(nginx_status)  | 规则: $(grep -c "server {" $CONFIG_FILE 2>/dev/null)   ║"
    echo "╚═══════════════════════════════════════════╝${NC}"
}

# 主菜单
main_menu() {
    while true; do
        show_header
        echo -e "${CYAN}1. 端口转发规则管理${NC}"
        echo -e "${CYAN}2. 查看当前所有规则${NC}"
        echo -e "${CYAN}3. 服务控制${NC}"
        echo -e "${CYAN}4. 系统管理${NC}"
        echo -e "${RED}0. 退出${NC}"
        echo -e "${YELLOW}────────────────────────────${NC}"
        echo -ne "${BOLD}请选择操作 [0-4]: ${NC}"
        read choice
        
        case $choice in
            1) rules_menu ;;
            2) list_rules ;;
            3) service_menu ;;
            4) system_menu ;;
            0) echo -e "${GREEN}感谢使用！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项，请重新选择${NC}"; sleep 1 ;;
        esac
    done
}

# 规则管理菜单
rules_menu() {
    while true; do
        show_header
        echo -e "${CYAN}════════ 端口转发管理 ════════${NC}"
        echo -e "${GREEN}1. 添加新转发规则${NC}"
        echo -e "${YELLOW}2. 删除已有规则${NC}"
        echo -e "${CYAN}3. 批量导入规则${NC}"
        echo -e "${MAGENTA}0. 返回主菜单${NC}"
        echo -e "${YELLOW}────────────────────────────${NC}"
        echo -ne "${BOLD}请选择操作 [0-3]: ${NC}"
        read choice
        
        case $choice in
            1) add_rule_menu ;;
            2) delete_rule_menu ;;
            3) batch_import_menu ;;
            0) return ;;
            *) echo -e "${RED}无效选项，请重新选择${NC}"; sleep 1 ;;
        esac
    done
}

# 服务控制菜单
service_menu() {
    while true; do
        show_header
        echo -e "${CYAN}════════ 服务控制 ════════${NC}"
        echo -e "${GREEN}1. 启动Nginx服务${NC}"
        echo -e "${RED}2. 停止Nginx服务${NC}"
        echo -e "${YELLOW}3. 重启Nginx服务${NC}"
        echo -e "${CYAN}4. 检查配置状态${NC}"
        echo -e "${MAGENTA}0. 返回主菜单${NC}"
        echo -e "${YELLOW}────────────────────────────${NC}"
        echo -ne "${BOLD}请选择操作 [0-4]: ${NC}"
        read choice
        
        case $choice in
            1) start_nginx ;;
            2) stop_nginx ;;
            3) restart_nginx ;;
            4) check_nginx_config ;;
            0) return ;;
            *) echo -e "${RED}无效选项，请重新选择${NC}"; sleep 1 ;;
        esac
    done
}

# 系统管理菜单
system_menu() {
    while true; do
        show_header
        echo -e "${CYAN}════════ 系统管理 ════════${NC}"
        echo -e "${GREEN}1. 备份当前配置${NC}"
        echo -e "${YELLOW}2. 恢复配置${NC}"
        echo -e "${CYAN}3. 更新管理器${NC}"
        echo -e "${RED}4. 卸载管理器${NC}"
        echo -e "${MAGENTA}0. 返回主菜单${NC}"
        echo -e "${YELLOW}────────────────────────────${NC}"
        echo -ne "${BOLD}请选择操作 [0-4]: ${NC}"
        read choice
        
        case $choice in
            1) backup_config ;;
            2) restore_config_menu ;;
            3) update_manager ;;
            4) uninstall_menu ;;
            0) return ;;
            *) echo -e "${RED}无效选项，请重新选择${NC}"; sleep 1 ;;
        esac
    done
}

# 添加规则菜单
add_rule_menu() {
    show_header
    echo -e "${CYAN}════════ 添加转发规则 ════════${NC}"
    
    # 协议选择
    while true; do
        echo -e "选择协议:"
        echo -e "${GREEN}1. TCP${NC} (网页/远程桌面)"
        echo -e "${GREEN}2. UDP${NC} (视频流/游戏)"
        echo -e "${GREEN}3. TCP+UDP${NC} (双协议)"
        echo -ne "${BOLD}请选择 [1-3]: ${NC}"
        read protocol_choice
        
        case $protocol_choice in
            1) protocol="tcp"; break ;;
            2) protocol="udp"; break ;;
            3) protocol="tcpudp"; break ;;
            *) echo -e "${RED}无效选项，请重新选择${NC}" ;;
        esac
    done
    
    # 端口输入
    while true; do
        echo -ne "${BOLD}输入监听端口 (1-65535): ${NC}"
        read port
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            break
        else
            echo -e "${RED}端口无效，请输入1-65535之间的数字${NC}"
        fi
    done
    
    # 目标地址
    while true; do
        echo -ne "${BOLD}输入目标地址 (格式: 服务器IP或域名:端口): ${NC}"
        read target
        if [[ "$target" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
            break
        else
            echo -e "${RED}格式无效，请使用 服务器:端口 格式${NC}"
        fi
    done
    
    # 描述信息
    echo -ne "${BOLD}规则描述 (可选): ${NC}"
    read description
    
    # 确认信息
    show_header
    echo -e "${CYAN}═════ 规则确认 ═════${NC}"
    echo -e "协议:     ${GREEN}$protocol${NC}"
    echo -e "监听端口: ${GREEN}$port${NC}"
    echo -e "目标地址: ${GREEN}$target${NC}"
    echo -e "描述:     ${GREEN}${description:-"未提供描述"}${NC}"
    echo -e "${YELLOW}────────────────────────────${NC}"
    
    echo -ne "${BOLD}是否添加此规则? [y/N]: ${NC}"
    read confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        add_rule "$protocol" "$port" "$target" "${description:-"未提供描述"}"
        echo -ne "${BOLD}按回车键返回...${NC}"; read
    fi
}

# 删除规则菜单
delete_rule_menu() {
    list_rules
    if [ $? -ne 0 ]; then  # 如果没有规则
        sleep 2
        return
    fi
    
    echo -ne "${BOLD}输入要删除的规则ID: ${NC}"
    read rule_id
    
    # 确认删除
    if grep -q "# 规则ID: $rule_id" "$CONFIG_FILE"; then
        echo -e "${RED}警告：此操作不可恢复！${NC}"
        echo -ne "${BOLD}确认删除规则 $rule_id? [y/N]: ${NC}"
        read confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            delete_rule "$rule_id"
        fi
    else
        echo -e "${RED}错误：找不到规则 $rule_id${NC}"
        sleep 1
    fi
}

# 列出规则
list_rules() {
    show_header
    echo -e "${CYAN}══════ 当前端口转发规则 ══════${NC}"
    
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}暂无配置规则${NC}"
        return 1
    fi
    
    # 显示规则表格
    echo -e "${BOLD}ID       端口      协议      目标地址           描述${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────${NC}"
    
    grep -A5 "# 规则ID:" "$CONFIG_FILE" | awk -v green="$GREEN" -v yellow="$YELLOW" -v nc="$NC" '
        /^# 规则ID: / {
            id = $3
            $1=$2=$3=""
            desc = substr($0, index($0, $4))
            next
        }
        /listen [0-9]+/ {
            port = $2
            proto = ""
            if ($3 == "tcp;") proto = "TCP"
            if ($3 == "udp;") proto = "UDP"
            if (proto != "") {
                getline
                if ($1 == "proxy_pass") {
                    target = $2
                    sub(";", "", target)
                    printf "%-9s %-9s %-9s %-19s %s\n", yellow id nc, green port nc, green proto nc, green target nc, yellow desc nc
                }
            }
        }
    '
    
    echo -e "${YELLOW}────────────────────────────────────────────────────────${NC}"
    return 0
}

# 添加规则函数
add_rule() {
    local protocol=$1
    local listen_port=$2
    local target=$3
    local description=$4
    local rule_id=$(date +%s)
    
    # 创建规则
    backup_config
    
    echo -e "\n# 规则ID: $rule_id - $description" >> "$CONFIG_FILE"
    echo "server {" >> "$CONFIG_FILE"
    
    if [[ "$protocol" == "tcpudp" ]]; then
        echo "    listen $listen_port tcp;" >> "$CONFIG_FILE"
        echo "    proxy_pass $target;" >> "$CONFIG_FILE"
        echo "}" >> "$CONFIG_FILE"
        
        echo -e "\n# 规则ID: $rule_id - $description" >> "$CONFIG_FILE"
        echo "server {" >> "$CONFIG_FILE"
        echo "    listen $listen_port udp;" >> "$CONFIG_FILE"
        echo "    proxy_pass $target;" >> "$CONFIG_FILE"
    else
        echo "    listen $listen_port $protocol;" >> "$CONFIG_FILE"
        echo "    proxy_pass $target;" >> "$CONFIG_FILE"
    fi
    
    echo "}" >> "$CONFIG_FILE"
    
    echo -e "${GREEN}✅ 规则已成功添加！${NC}"
    reload_nginx
}

# 删除规则
delete_rule() {
    local rule_id=$1
    
    if grep -q "# 规则ID: $rule_id" "$CONFIG_FILE"; then
        # 创建备份
        backup_config
        
        # 删除规则
        local temp_file=$(mktemp)
        sed -e "/# 规则ID: $rule_id/,/^}/d" "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
        
        echo -e "${GREEN}✅ 规则 $rule_id 已删除${NC}"
        reload_nginx
    else
        echo -e "${RED}错误: 找不到规则 $rule_id${NC}"
        return 1
    fi
}

# 备份配置
backup_config() {
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    cp "$CONFIG_FILE" "$BACKUP_DIR/stream_proxy_$timestamp.conf"
    echo -e "${CYAN}📦 已创建配置备份: $BACKUP_DIR/stream_proxy_$timestamp.conf${NC}"
}

# 启动Nginx
start_nginx() {
    if systemctl start nginx; then
        echo -e "${GREEN}✅ Nginx已成功启动${NC}"
    else
        echo -e "${RED}❌ 无法启动Nginx${NC}"
    fi
    sleep 1
}

# 停止Nginx
stop_nginx() {
    if systemctl stop nginx; then
        echo -e "${GREEN}✅ Nginx已停止${NC}"
    else
        echo -e "${RED}❌ 无法停止Nginx${NC}"
    fi
    sleep 1
}

# 重启Nginx
restart_nginx() {
    if systemctl restart nginx; then
        echo -e "${GREEN}✅ Nginx已重启${NC}"
    else
        echo -e "${RED}❌ 无法重启Nginx${NC}"
    fi
    sleep 1
}

# 重载Nginx配置
reload_nginx() {
    echo -e "${CYAN}🔄 重新加载Nginx配置...${NC}"
    
    if nginx -t &> /dev/null; then
        if systemctl reload nginx &> /dev/null; then
            echo -e "${GREEN}✅ 配置已重新加载${NC}"
        else
            echo -e "${RED}❌ 无法重新加载Nginx - 请手动重启${NC}"
        fi
    else
        echo -e "${RED}❌ Nginx配置测试失败！${NC}"
        echo -e "${YELLOW}使用 'nginx -t' 查看详细信息${NC}"
        return 1
    fi
    return 0
}

# 检查配置
check_nginx_config() {
    echo -e "${CYAN}🔍 检查Nginx配置...${NC}"
    nginx -t
    echo -ne "${BOLD}按回车键返回...${NC}"; read
}

# 更新管理器
update_manager() {
    echo -e "${CYAN}🔄 检查更新...${NC}"
    curl -fsSL -o /tmp/nsm-update \
        https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/manager.sh
        
    if diff /usr/local/bin/nsm-manager /tmp/nsm-update &> /dev/null; then
        echo -e "${GREEN}✅ 已是最新版本${NC}"
        rm /tmp/nsm-update
    else
        echo -e "${CYAN}发现新版本，正在更新...${NC}"
        mv /tmp/nsm-update /usr/local/bin/nsm-manager
        chmod +x /usr/local/bin/nsm-manager
        echo -e "${GREEN}✅ 更新成功！${NC}"
    fi
    sleep 1
}

# 卸载确认
uninstall_menu() {
    show_header
    echo -e "${RED}═════ 卸载确认 ═════${NC}"
    echo -e "此操作将："
    echo -e "1. 移除所有转发规则"
    echo -
