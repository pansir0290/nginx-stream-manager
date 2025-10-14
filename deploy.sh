#!/bin/bash

# --- 配置参数 ---
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
BACKUP_DIR="/etc/nginx/conf-backup"
NGINX_SERVICE="nginx"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 恢复默认颜色

# --- 交互式函数 ---

# 主菜单
show_menu() {
    clear
    echo -e "${GREEN}▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁"
    echo -e "  Nginx Stream Manager (交互向导模式)  "
    echo -e "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔${NC}"
    echo -e "1. 📌 添加转发规则"
    echo -e "2. 🗑️  删除转发规则"
    echo -e "3. 📋 查看所有规则"
    echo -e "4. ❓ 帮助信息"
    echo -e "5. 🚪 退出"
    echo -e "${YELLOW}------------------------------------${NC}"
    read -p "请选择操作 [1-5]: " choice
    echo -e ""
    
    case $choice in
        1) add_rule_menu ;;
        2) delete_rule_menu ;;
        3) list_rules ;;
        4) show_help ;;
        5) exit 0 ;;
        *) 
            echo -e "${RED}错误: 无效选择，请重试${NC}"
            sleep 1
            show_menu
            ;;
    esac
}

# 添加规则向导
add_rule_menu() {
    echo -e "${BLUE}=== 添加转发规则向导 ===${NC}"
    
    # 选择协议类型
    echo -e "请选择协议类型:"
    echo -e "1. TCP (适用于Web服务)"
    echo -e "2. UDP (适用于DNS/VoIP)"
    echo -e "3. TCP+UDP (双向支持)"
    read -p "选择协议 [1-3]: " protocol_choice
    
    case $protocol_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="tcpudp" ;;
        *)
            echo -e "${RED}错误: 无效选择${NC}"
            sleep 1
            add_rule_menu
            return
            ;;
    esac
    
    # 输入监听端口
    while true; do
        read -p "请输入监听端口 (1-65535): " listen_port
        
        # 验证端口格式
        if ! [[ $listen_port =~ ^[0-9]+$ ]] || [ $listen_port -lt 1 ] || [ $listen_port -gt 65535 ]; then
            echo -e "${RED}错误: 端口必须是1-65535的整数${NC}"
            continue
        fi
        
        # 检查端口是否被占用
        if sudo ss -tuln | grep -q ":$listen_port\b"; then
            echo -e "${YELLOW}警告: 端口 $listen_port 已被其他服务使用${NC}"
            read -p "确定要使用此端口吗? [y/N]: " confirm
            [[ $confirm =~ ^[Yy]$ ]] || continue
        fi
        
        # 检查规则是否已存在
        if grep -q "server .*:$listen_port;" "$CONFIG_FILE"; then
            echo -e "${RED}错误: 端口 $listen_port 已有转发规则${NC}"
        else
            break
        fi
    done
    
    # 输入目标地址
    while true; do
        read -p "请输入目标地址 (格式: ip/域名:端口): " target
        
        # 验证目标格式
        if ! [[ $target =~ ^([a-zA-Z0-9.-]+|$$[a-fA-F0-9:]+$$):[0-9]+$ ]]; then
            echo -e "${RED}错误: 目标格式无效，请使用<地址/域名>:<端口>${NC}"
            continue
        fi
        
        # 拆分验证端口
        target_port=$(echo "$target" | cut -d: -f2)
        if ! [[ $target_port =~ ^[0-9]+$ ]] || [ $target_port -lt 1 ] || [ $target_port -gt 65535 ]; then
            echo -e "${RED}错误: 目标端口$target_port无效，必须是1-65535的整数${NC}"
            continue
        fi
        
        break
    done
    
    # 显示配置摘要
    echo -e "\n${YELLOW}=== 规则摘要 ==="
    echo -e "协议: $protocol"
    echo -e "监听端口: $listen_port"
    echo -e "目标地址: $target"
    echo -e "=================${NC}"
    
    # 确认添加
    read -p "确认添加此规则吗? [Y/n]: " confirm
    if [[ $confirm =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        sleep 1
        show_menu
        return
    fi
    
    # 执行添加
    add_rule "$protocol" "$listen_port" "$target"
    
    # 返回主菜单
    read -p "按回车键返回主菜单..."
    show_menu
}

# 删除规则向导
delete_rule_menu() {
    echo -e "${BLUE}=== 删除转发规则向导 ===${NC}"
    
    # 检查是否有规则
    if ! grep -q "server { listen" "$CONFIG_FILE"; then
        echo -e "${YELLOW}当前没有配置转发规则${NC}"
        sleep 1
        show_menu
        return
    fi
    
    # 显示规则列表
    echo -e "${GREEN}当前转发规则:${NC}"
    list_rules
    
    # 获取所有监听端口
    ports=($(grep -A1 "server { listen" "$CONFIG_FILE" | grep "listen" | awk '{print $2}' | sort -u | sed 's/;//'))
    
    # 选择要删除的端口
    while true; do
        echo -e ""
        read -p "请输入要删除的规则端口: " port
        
        # 验证输入
        if ! [[ $port =~ ^[0-9]+$ ]]; then
            echo -e "${RED}错误: 端口必须是数字${NC}"
            continue
        fi
        
        # 检查端口是否存在
        if grep -q "server .*:$port;" "$CONFIG_FILE"; then
            break
        else
            echo -e "${RED}错误: 未找到端口 $port 的规则${NC}"
            continue
        fi
    done
    
    # 确认删除
    read -p "确定要删除端口 $port 的规则吗? [y/N]: " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        sleep 1
        show_menu
        return
    fi
    
    # 执行删除
    delete_rule "$port"
    
    # 返回主菜单
    read -p "按回车键返回主菜单..."
    show_menu
}

# --- 功能函数 ---

# 添加转发规则
add_rule() {
    local protocol=$1
    local listen_port=$2
    local target=$3
    local rule_template=""
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    # 创建备份
    echo -e "${YELLOW}创建配置备份...${NC}"
    sudo mkdir -p "$BACKUP_DIR"
    sudo cp -f "$CONFIG_FILE" "$BACKUP_DIR/stream_proxy.conf.bak-$timestamp"
    echo -e "${GREEN}配置已备份: ${BACKUP_DIR}/stream_proxy.conf.bak-$timestamp${NC}"
    
    # 生成规则
    case $protocol in
        tcp)
            rule_template="server { listen $listen_port; proxy_pass $target; }"
            ;;
        udp)
            rule_template="server { listen $listen_port udp; proxy_pass $target; }"
            ;;
        tcpudp)
            rule_template="server { listen $listen_port; listen $listen_port udp; proxy_pass $target; }"
            ;;
    esac
    
    # 添加到配置
    echo -e "${BLUE}添加规则: ${protocol} ${listen_port} → ${target}${NC}"
    echo -e "# 规则ID: ${timestamp}-${listen_port}\n${rule_template}" | sudo tee -a "$CONFIG_FILE" >/dev/null
    
    # 重启Nginx
    restart_nginx
}

# 删除转发规则
delete_rule() {
    local port=$1
    
    # 创建备份
    local timestamp=$(date +%Y%m%d-%H%M%S)
    echo -e "${YELLOW}创建配置备份...${NC}"
    sudo mkdir -p "$BACKUP_DIR"
    sudo cp -f "$CONFIG_FILE" "$BACKUP_DIR/stream_proxy.conf.bak-$timestamp"
    echo -e "${GREEN}配置已备份: ${BACKUP_DIR}/stream_proxy.conf.bak-$timestamp${NC}"
    
    # 查找规则ID
    local rule_id=$(grep -B1 "listen $port;" "$CONFIG_FILE" | grep "# 规则ID:" | awk '{print $3}')
    
    if [ -z "$rule_id" ]; then
        echo -e "${YELLOW}警告: 未找到规则ID，执行端口匹配删除${NC}"
        rule_id=$port
    fi
    
    # 删除规则
    echo -e "${BLUE}删除规则: $port${NC}"
    sudo sed -i "/# 规则ID: ${rule_id}/,/^}/d" "$CONFIG_FILE"
    
    # 重启Nginx
    restart_nginx
}

# 重启Nginx
restart_nginx() {
    # 验证配置语法
    if ! sudo nginx -t 2>/dev/null; then
        echo -e "${RED}错误: Nginx配置验证失败${NC}"
        echo -e "正在恢复备份..."
        sudo cp -f "$BACKUP_DIR/stream_proxy.conf.bak-$timestamp" "$CONFIG_FILE"
        return 1
    fi
    
    echo -e "${YELLOW}重新加载Nginx配置...${NC}"
    
    # 尝试不同方式重启
    local reloaded=0
    
    if systemctl list-unit-files | grep -q "^${NGINX_SERVICE}.service"; then
        if sudo systemctl reload "$NGINX_SERVICE"; then
            reloaded=1
        fi
    fi
    
    if [ $reloaded -eq 0 ] && command -v service > /dev/null; then
        if sudo service "$NGINX_SERVICE" reload; then
            reloaded=1
        fi
    fi
    
    if [ $reloaded -eq 1 ]; then
        echo -e "${GREEN}✓ Nginx已成功重新加载${NC}"
        return 0
    else
        echo -e "${RED}警告: 自动重载失败，请手动执行: ${YELLOW}nginx -s reload${NC}"
        return 1
    fi
}

# 显示规则列表
list_rules() {
    local count=$(grep -c "server { listen" "$CONFIG_FILE" 2>/dev/null)
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}暂无转发规则${NC}"
        return
    fi
    
    echo -e "${GREEN}▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
    echo -e " ID         协议   端口      目标地址"
    echo -e "▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${NC}"
    
    # 提取并格式化规则
    awk '
        /# 规则ID:/ {
            gsub(/# 规则ID: /, "")
            id=$0
            next
        }
        /server {/ {
            in_block=1
            next
        }
        in_block && /listen [0-9]+/ {
            port=$2
            protocol="tcp"
            if ($0 ~ /udp/) protocol="udp"
            if (match($0, /listen [0-9]+ udp; listen [0-9]+;/)) protocol="tcpudp"
            next
        }
        in_block && /proxy_pass/ {
            target=$2
            sub(/;$/, "", target)
            next
        }
        in_block && /}/ {
            printf "%-12s %-6s %-8s %s\n", id, protocol, port, target
            in_block=0
        }
    ' "$CONFIG_FILE"
    
    echo -e "${GREEN}▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
    echo -e " 共找到 $count 条规则"
    echo -e "▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${NC}"
}

# 显示帮助信息
show_help() {
    echo -e "${GREEN}▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁"
    echo -e "  Nginx Stream Manager 使用帮助"
    echo -e "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔${NC}"
    echo -e "这是一个交互式工具，用于管理Nginx流转发规则。"
    echo -e "您可以通过菜单选择操作："
    echo -e ""
    echo -e "${BLUE}添加规则:${NC}"
    echo -e "  1. 选择协议类型 (TCP/UDP/TCP+UDP)"
    echo -e "  2. 输入本地监听端口 (1-65535)"
    echo -e "  3. 输入目标服务器地址 (IP/域名:端口)"
    echo -e ""
    echo -e "${BLUE}删除规则:${NC}"
    echo -e "  1. 从列表中选择要删除的规则"
    echo -e "  2. 输入监听端口号"
    echo -e ""
    echo -e "${BLUE}命令行模式:${NC}"
    echo -e "  nsm add [tcp|udp|tcpudp] [端口] [目标]"
    echo -e "  nsm del [端口]"
    echo -e "  nsm list"
    echo -e ""
    echo -e "${YELLOW}示例:${NC}"
    echo -e "  添加: nsm add tcp 8080 example.com:80"
    echo -e "  删除: nsm del 8080"
    echo -e ""
    echo -e "${GREEN}配置文件位置: $CONFIG_FILE${NC}"
    echo -e "${GREEN}备份目录: $BACKUP_DIR${NC}"
    
    read -p "按回车键返回主菜单..."
    show_menu
}

# --- 主程序 ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 此命令需要root权限 (请使用 sudo nsm)${NC}"
        exit 1
    fi
}

check_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: 配置文件不存在 - $CONFIG_FILE${NC}"
        echo -e "请先运行 ${YELLOW}sudo ./deploy.sh${NC} 安装程序"
        exit 1
    fi
}

# --- 命令行模式处理 ---
if [ $# -gt 0 ]; then
    case $1 in
        add)
            if [ $# -ne 4 ]; then
                echo -e "${RED}错误: 参数不足，格式为 nsm add [协议] [监听端口] [目标地址]${NC}"
                exit 1
            fi
            add_rule "$2" "$3" "$4"
            ;;
        del|delete|remove)
            if [ $# -ne 2 ]; then
                echo -e "${RED}错误: 请指定要删除的端口号${NC}"
                exit 1
            fi
            if ! [[ $2 =~ ^[0-9]+$ ]]; then
                echo -e "${RED}错误:
