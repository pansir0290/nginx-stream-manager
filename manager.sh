#!/bin/bash

# --- 配置参数 (必须与 deploy.sh 一致) ---
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
BACKUP_DIR="/etc/nginx/conf-backup"
NGINX_SERVICE="nginx"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 恢复默认颜色

# --- 功能函数 ---

# 配置备份函数
backup_config() {
    sudo cp "$CONFIG_FILE" "$BACKUP_DIR/stream_proxy.conf.bak-$TIMESTAMP"
    echo -e "${YELLOW}配置文件已备份: ${BACKUP_DIR}/stream_proxy.conf.bak-$TIMESTAMP${NC}"
}

# Nginx 重启函数
restart_nginx() {
    echo -e "${YELLOW}重新加载Nginx配置...${NC}"
    
    # 验证配置语法
    if ! sudo nginx -t 2>/dev/null; then
        echo -e "${RED}错误: Nginx配置验证失败，正在恢复备份...${NC}"
        sudo cp -f "$BACKUP_DIR/stream_proxy.conf.bak-$TIMESTAMP" "$CONFIG_FILE"
        return 1
    fi
    
    # 尝试不同方式重启
    if systemctl list-unit-files | grep -q "^${NGINX_SERVICE}.service"; then
        sudo systemctl reload "$NGINX_SERVICE" && return 0
    fi
    
    if command -v service > /dev/null; then
        sudo service "$NGINX_SERVICE" reload && return 0
    fi
    
    echo -e "${RED}警告: 自动重载失败，请手动执行: ${YELLOW}nginx -s reload${NC}"
    return 1
}

# 规则格式验证
validate_rule() {
    local protocol=$1
    local listen_port=$2
    local target=$3
    
    # 验证端口格式
    if ! [[ $listen_port =~ ^[0-9]+$ ]] || [ $listen_port -lt 1 ] || [ $listen_port -gt 65535 ]; then
        echo -e "${RED}错误: 监听端口必须是1-65535的整数${NC}"
        return 1
    fi
    
    # 验证目标格式
    if ! [[ $target =~ ^([a-zA-Z0-9.-]+|$$[a-fA-F0-9:]+$$):[0-9]+$ ]]; then
        echo -e "${RED}错误: 目标格式无效，请使用<地址/域名>:<端口>${NC}"
        return 1
    fi
    
    # 验证协议
    case $protocol in
        tcp|udp|tcpudp) ;;
        *) 
            echo -e "${RED}错误: 协议必须为 tcp, udp 或 tcpudp${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# 端口占用检查
check_port_availability() {
    local port=$1
    
    # 检查Nginx是否已监听该端口
    if sudo ss -tuln | grep -q ":$port\b"; then
        echo -e "${YELLOW}警告: 端口 $port 已被其他服务使用${NC}"
        read -p "是否继续添加规则? (y/N): " choice
        [[ $choice =~ ^[Yy]$ ]] || return 1
    fi
    
    # 检查规则是否已存在
    if grep -q "server .*:$port;" "$CONFIG_FILE"; then
        echo -e "${RED}错误: 端口 $port 已有转发规则${NC}"
        return 1
    fi
    
    return 0
}

# 添加转发规则
add_rule() {
    local protocol=$1
    local listen_port=$2
    local target=$3
    local rule_template=""
    
    # 创建备份
    backup_config
    
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
    echo -e "# 规则ID: ${TIMESTAMP}-${listen_port}\n${rule_template}" | sudo tee -a "$CONFIG_FILE" >/dev/null
    
    # 重启Nginx
    if restart_nginx; then
        echo -e "${GREEN}✓ 规则添加成功${NC}"
        return 0
    else
        return 1
    fi
}

# 删除转发规则
delete_rule() {
    local port=$1
    
    # 检查规则是否存在
    if ! grep -q "listen $port;" "$CONFIG_FILE"; then
        echo -e "${RED}错误: 未找到端口 $port 的规则${NC}"
        return 1
    fi
    
    # 创建备份
    backup_config
    
    # 查找规则ID
    local rule_id=$(grep -B1 "listen $port;" "$CONFIG_FILE" | grep "# 规则ID:" | awk '{print $3}')
    
    if [ -z "$rule_id" ]; then
        echo -e "${YELLOW}警告: 未找到规则ID，执行全端口匹配删除${NC}"
        rule_id=$port
    fi
    
    # 删除规则
    echo -e "${BLUE}删除规则: $port${NC}"
    sudo sed -i "/# 规则ID: ${rule_id}/,/^}/d" "$CONFIG_FILE"
    
    # 重启Nginx
    if restart_nginx; then
        echo -e "${GREEN}✓ 规则删除成功${NC}"
        return 0
    else
        return 1
    fi
}

# 显示规则列表
list_rules() {
    echo -e "${GREEN}当前转发规则列表:${NC}"
    
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
            printf "%-8s %-6s %-12s %s\n", id, port, protocol, target
            in_block=0
        }
    ' "$CONFIG_FILE" | column -t
    
    # 空规则提示
    if ! grep -q "server { listen" "$CONFIG_FILE"; then
        echo -e "${YELLOW}暂无转发规则${NC}"
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${GREEN}Nginx Stream Manager (nsm) 使用帮助${NC}"
    echo -e "${BLUE}用法:${NC}"
    echo -e "  add [协议] [监听端口] [目标地址]  添加转发规则"
    echo -e "  del [端口]                       删除转发规则"
    echo -e "  list                             显示所有规则"
    echo -e "  help                             显示本帮助信息"
    echo -e "\n${BLUE}示例:${NC}"
    echo -e "  ${YELLOW}添加规则:${NC} nsm add tcp 8080 example.com:80"
    echo -e "  ${YELLOW}添加UDP规则:${NC} nsm add udp 10000 voip-server:5060"
    echo -e "  ${YELLOW}添加双向规则:${NC} nsm add tcpudp 53 dns-server:53"
    echo -e "  ${YELLOW}删除规则:${NC} nsm del 8080"
    echo -e "  ${YELLOW}查看规则:${NC} nsm list"
}

# --- 主程序逻辑 ---

# 确保以root运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 此命令需要root权限 (请使用 sudo nsm)${NC}"
    exit 1
fi

# 确保配置文件存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}错误: 配置文件不存在 - $CONFIG_FILE${NC}"
    echo -e "请先运行 ${YELLOW}sudo ./deploy.sh${NC} 安装程序"
    exit 1
fi

# 解析命令
case $1 in
    add)
        if [ $# -ne 4 ]; then
            echo -e "${RED}错误: 参数不足，格式为 nsm add [协议] [监听端口] [目标地址]${NC}"
            exit 1
        fi
        
        if validate_rule "$2" "$3" "$4" && check_port_availability "$3"; then
            add_rule "$2" "$3" "$4"
        else
            exit 1
        fi
        ;;
    
    del|delete|remove)
        if [ $# -ne 2 ]; then
            echo -e "${RED}错误: 请指定要删除的端口号${NC}"
            exit 1
        fi
        
        if ! [[ $2 =~ ^[0-9]+$ ]]; then
            echo -e "${RED}错误: 端口号必须是数字${NC}"
            exit 1
        fi
        
        delete_rule "$2"
        ;;
    
    list|show|ls)
        list_rules
        ;;
    
    help|--help|-h)
        show_help
        ;;
    
    *)
        if [ $# -eq 0 ]; then
            echo -e "${YELLOW}提示: 使用 nsm help 查看可用命令${NC}"
        else
            echo -e "${RED}错误: 未知命令 '$1'${NC}"
            echo -e "使用 ${YELLOW}nsm help${NC} 查看可用命令"
        fi
        exit 1
        ;;
esac
