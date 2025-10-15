#!/bin/bash
# Nginx Stream Manager v2.0 - 完整管理套件
# 功能：端口转发规则管理 + Nginx配置
# 作者：您的名字
# 更新：$(date +%Y-%m-%d)

# ANSI颜色代码
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # 重置颜色

# 配置文件
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
NGINX_CONF="/etc/nginx/nginx.conf"
BACKUP_DIR="/etc/nginx/conf.d/backups"

# 确保脚本以root权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须使用sudo或root运行${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}安装curl...${NC}"
        apt-get update > /dev/null
        apt-get install -y curl
    fi
}

# 初始化配置
init_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    mkdir -p "$BACKUP_DIR"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "# 由Nginx Stream Manager自动生成" > "$CONFIG_FILE"
        echo -e "${GREEN}创建初始配置文件: $CONFIG_FILE${NC}"
    fi
    
    # 添加stream模块到nginx.conf
    if ! grep -q "stream\s*{" "$NGINX_CONF"; then
        echo -e "\n# Nginx Stream Manager 配置" >> "$NGINX_CONF"
        echo "stream {" >> "$NGINX_CONF"
        echo "    include $CONFIG_FILE;" >> "$NGINX_CONF"
        echo "    proxy_connect_timeout 20s;" >> "$NGINX_CONF"
        echo "    proxy_timeout 5m;" >> "$NGINX_CONF"
        echo "}" >> "$NGINX_CONF"
        echo -e "${GREEN}已添加stream模块到nginx配置${NC}"
    fi
}

# 备份配置
backup_config() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    cp "$CONFIG_FILE" "$BACKUP_DIR/stream_proxy_$timestamp.conf"
    echo -e "${YELLOW}已创建备份: $BACKUP_DIR/stream_proxy_$timestamp.conf${NC}"
}

# 添加转发规则
add_rule() {
    local protocol=$1
    local listen_port=$2
    local target=$3
    local description=$4
    
    # 验证协议
    if [[ ! "$protocol" =~ ^(tcp|udp|tcpudp)$ ]]; then
        echo -e "${RED}错误协议: 必须是 tcp, udp 或 tcpudp${NC}"
        return 1
    fi
    
    # 验证端口
    if ! [[ "$listen_port" =~ ^[0-9]+$ ]] || [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
        echo -e "${RED}错误端口号: 必须是1-65535${NC}"
        return 1
    fi
    
    # 验证目标
    if ! [[ "$target" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        echo -e "${RED}错误目标格式: 必须是 host:port${NC}"
        return 1
    fi
    
    # 创建规则
    backup_config
    local rule_id=$(date +%s)
    
    if [[ "$protocol" == "tcpudp" ]]; then
        echo -e "\n# 规则ID: $rule_id - $description" >> "$CONFIG_FILE"
        echo "server {" >> "$CONFIG_FILE"
        echo "    listen $listen_port tcp;" >> "$CONFIG_FILE"
        echo "    proxy_pass $target;" >> "$CONFIG_FILE"
        echo "}" >> "$CONFIG_FILE"
        
        echo -e "\n# 规则ID: $rule_id - $description" >> "$CONFIG_FILE"
        echo "server {" >> "$CONFIG_FILE"
        echo "    listen $listen_port udp;" >> "$CONFIG_FILE"
        echo "    proxy_pass $target;" >> "$CONFIG_FILE"
        echo "}" >> "$CONFIG_FILE"
    else
        echo -e "\n# 规则ID: $rule_id - $description" >> "$CONFIG_FILE"
        echo "server {" >> "$CONFIG_FILE"
        echo "    listen $listen_port $protocol;" >> "$CONFIG_FILE"
        echo "    proxy_pass $target;" >> "$CONFIG_FILE"
        echo "}" >> "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}规则已添加!${NC}"
    
    # 重启Nginx
    reload_nginx
    
    return 0
}

# 删除规则
delete_rule() {
    local rule_id=$1
    
    if [ -z "$rule_id" ]; then
        echo -e "${RED}错误: 缺少规则ID${NC}"
        return 1
    fi
    
    if ! grep -q "# 规则ID: $rule_id" "$CONFIG_FILE"; then
        echo -e "${RED}错误: 规则 $rule_id 不存在${NC}"
        return 1
    fi
    
    # 创建备份
    backup_config
    
    # 删除规则
    local temp_file=$(mktemp)
    sed -e "/# 规则ID: $rule_id/,/^}/d" "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"
    
    echo -e "${GREEN}规则 $rule_id 已删除${NC}"
    
    # 重启Nginx
    reload_nginx
    
    return 0
}

# 列出规则
list_rules() {
    echo -e "\n${CYAN}===== 当前端口转发规则 =====${NC}"
    
    if [ ! -s "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}暂无配置规则${NC}"
        return
    fi
    
    # 解析规则
    awk -v green="$GREEN" -v cyan="$CYAN" -v yellow="$YELLOW" -v nc="$NC" '
        /^# 规则ID: / {
            gsub(/\r/, "") # 移除Windows换行符
            rule_id = $3
            $1=$2=""
            desc = substr($0, index($0, $3))
            next
        }
        /listen [0-9]+/ {
            if ($2 ~ /[0-9]+/) {
                port = $2
                protocol = ""
                if ($3 == "tcp;") protocol = "TCP"
                if ($3 == "udp;") protocol = "UDP"
                if (protocol != "") {
                    print cyan "ID: " yellow rule_id nc " | " cyan "端口: " green port nc " | " cyan "协议: " green protocol nc " | " cyan "描述: " yellow desc nc
                }
            }
        }
    ' "$CONFIG_FILE"
}

# 重载Nginx服务
reload_nginx() {
    echo -e "${YELLOW}重新加载Nginx配置...${NC}"
    
    # 测试配置
    if ! nginx -t &> /dev/null; then
        echo -e "${RED}❌ Nginx配置测试失败！${NC}"
        echo -e "${YELLOW}使用 'nginx -t' 查看详细信息${NC}"
        return 1
    fi
    
    # 重载或重启服务
    if systemctl reload nginx &> /dev/null; then
        echo -e "${GREEN}✅ Nginx配置已重新加载${NC}"
    elif systemctl restart nginx &> /dev/null; then
        echo -e "${GREEN}✅ Nginx已重启${NC}"
    else
        # 最后尝试使用nginx命令重载
        if nginx -s reload &> /dev/null; then
            echo -e "${GREEN}✅ Nginx配置已重新加载${NC}"
        else
            echo -e "${RED}❌ 无法重新加载Nginx - 请手动重启${NC}"
            return 1
        fi
    fi
    
    return 0
}

# 完整安装
full_install() {
    check_root
    echo -e "\n${CYAN}===== 开始Nginx Stream Manager安装 =====${NC}"
    
    install_dependencies
    init_config
    
    # 设置别名
    if ! grep -q "alias nsm=" ~/.bashrc; then
        echo "alias nsm='sudo $0'" >> ~/.bashrc
        echo -e "${GREEN}已设置命令行别名: nsm${NC}"
    fi
    
    echo -e "\n${GREEN}✅ 安装完成！${NC}"
    echo -e "请运行 ${YELLOW}nsm menu${NC} 启动管理界面"
}

# 卸载
uninstall() {
    check_root
    echo -e "\n${RED}===== 卸载Nginx Stream Manager =====${NC}"
    
    read -p "确定要卸载吗？这将移除所有配置 (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}卸载已取消${NC}"
        return
    fi
    
    # 删除配置文件
    if [ -f "$CONFIG_FILE" ]; then
        backup_config
        rm -f "$CONFIG_FILE"
        echo -e "${GREEN}已移除配置文件${NC}"
    fi
    
    # 从nginx.conf中移除stream模块
    if grep -q "Nginx Stream Manager" "$NGINX_CONF"; then
        cp "$NGINX_CONF" "$NGINX_CONF.bak"
        sed -i '/# Nginx Stream Manager/,/}/d' "$NGINX_CONF"
        echo -e "${GREEN}已从nginx.conf中移除配置${NC}"
    fi
    
    # 删除别名
    sed -i '/alias nsm=/d' ~/.bashrc
    
    echo -e "\n${GREEN}✅ 卸载完成！${NC}"
    echo -e "配置文件备份在 ${YELLOW}$BACKUP_DIR${NC}"
}

# 显示帮助
show_help() {
    echo -e "${CYAN}Nginx Stream Manager 使用帮助${NC}"
    echo "命令:"
    echo "  menu         - 启动交互式菜单"
    echo "  install      - 完成安装"
    echo "  add          - 添加转发规则"
    echo "   用法: add [协议] [监听端口] [目标地址] [描述]"
    echo "   示例: add tcp 8080 web-server:80 'Web服务'"
    echo "  delete       - 删除规则"
    echo "   用法: delete [规则ID]"
    echo "  list         - 列出所有规则"
    echo "  reload       - 重载Nginx配置"
    echo "  uninstall    - 卸载管理器"
    echo "  help         - 显示本帮助"
    echo "  version      - 显示版本信息"
    echo ""
    echo "直接运行'nsm'将启动交互菜单"
}

# 显示版本
show_version() {
    echo -e "${GREEN}Nginx Stream Manager v2.0${NC}"
    echo "最后更新: 2024-06-15"
}

# 交互式菜单
interactive_menu() {
    check_root
    
    while true; do
        clear
        echo -e "${CYAN}"
        echo "┌───────────────────────────────────────────────┐"
        echo "│   ${NC}${GREEN}Nginx Stream Manager ${CYAN}- ${NC}交互菜单${CYAN}   │"
        echo "├───────────────────────────────────────────────┤"
        echo "│ ${GREEN}1${NC}${CYAN}. 添加端口转发规则 ${NC}                         ${CYAN}│"
        echo "│ ${GREEN}2${NC}${CYAN}. 查看当前规则 ${NC}                             ${CYAN}│"
        echo "│ ${GREEN}3${NC}${CYAN}. 删除规则 ${NC}                                 ${CYAN}│"
        echo "│ ${GREEN}4${NC}${CYAN}. 重载Nginx服务 ${NC}                           ${CYAN}│"
        echo "│ ${GREEN}5${NC}${CYAN}. 测试Nginx配置 ${NC}                           ${CYAN}│"
        echo "│ ${GREEN}6${NC}${CYAN}. 完成安装 ${NC}                                ${CYAN}│"
        echo "│ ${GREEN}7${NC}${CYAN}. 卸载管理器 ${NC}                              ${CYAN}│"
        echo "│ ${RED}0${NC}${CYAN}. 退出 ${NC}                                     ${CYAN}│"
        echo "└───────────────────────────────────────────────┘${NC}"
        echo -ne "${YELLOW}请选择操作 [0-7]: ${NC}"
        read choice
        
        case $choice in
            1)
                echo -ne "协议 (tcp/udp/tcpudp): "
                read protocol
                echo -ne "监听端口: "
                read port
                echo -ne "目标地址 (host:port): "
                read target
                echo -ne "描述: "
                read desc
                
                add_rule "$protocol" "$port" "$target" "$desc"
                ;;
            2)
                list_rules
                ;;
            3)
                echo -ne "输入要删除的规则ID: "
                read rule_id
                delete_rule "$rule_id"
                ;;
            4)
                reload_nginx
                ;;
            5)
                echo -e "${YELLOW}测试Nginx配置...${NC}"
                nginx -t
                ;;
            6)
                full_install
                ;;
            7)
                uninstall
                exit 0
                ;;
            0)
                echo -e "${GREEN}已退出${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项!${NC}"
                ;;
        esac
        
        echo -e "\n${CYAN}按回车键继续...${NC}"
        read
    done
}

# 主入口
case "$1" in
    "menu")
        interactive_menu
        ;;
    "install")
        full_install
        ;;
    "add")
        if [ $# -lt 4 ]; then
            echo -e "${RED}错误: 参数不足${NC}"
            echo "用法: add [协议] [监听端口] [目标地址] [描述]"
            exit 1
        fi
        add_rule "$2" "$3" "$4" "${5:-自动添加}"
        ;;
    "delete")
        if [ -z "$2" ]; then
            echo -e "${RED}错误: 缺少规则ID${NC}"
            exit 1
        fi
        delete_rule "$2"
        ;;
    "list")
        list_rules
        ;;
    "reload")
        reload_nginx
        ;;
    "uninstall")
        uninstall
        ;;
    "help")
        show_help
        ;;
    "version")
        show_version
        ;;
    "")
        interactive_menu
        ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        show_help
        exit 1
        ;;
esac

exit 0
