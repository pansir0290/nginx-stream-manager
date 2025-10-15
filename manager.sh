#!/bin/bash
# -----------------------------------------------------------------------------
# Nginx Stream Manager (NSM) - 修复与优化版
# 版本：1.0.1
# 修复：配置冲突、SSL选项控制、删除功能
# -----------------------------------------------------------------------------

# 配置参数
CONFIG_DIR="/etc/nginx/conf.d/nsm"
CONFIG_FILE="$CONFIG_DIR/nsm-stream.conf" # 此文件将只包含 server {} 块
BACKUP_DIR="$CONFIG_DIR/backups"
LOG_FILE="/var/log/nsm-manager.log"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_SERVICE="nginx"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 初始化日志
init_log() {
    [ ! -d "$(dirname "$LOG_FILE")" ] && mkdir -p "$(dirname "$LOG_FILE")"
    echo -e "$(date +'%Y-%m-%d %H:%M:%S') NSM 初始化开始" >> "$LOG_FILE"
}

# 记录日志
log() {
    local level=$1
    local message=$2
    local color
    
    case $level in
        "SUCCESS") color=$GREEN ;;
        "ERROR") color=$RED ;;
        "WARNING") color=$YELLOW ;;
        "INFO") color=$CYAN ;;
        *) color=$NC ;;
    esac
    
    echo -e "$(date +'%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
    echo -e "${color}[${level}]${NC} $message"
}

# 检查是否以root运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "此脚本必须使用root权限运行！请使用sudo重新执行。"
        exit 1
    fi
}

# 检查并修复编码问题
check_encoding() {
    if grep -q $'\r' "$0"; then
        log "WARNING" "检测到Windows换行符，正在修复..."
        # 使用临时文件进行修复
        sed 's/\r$//' "$0" > "$0.tmp" && mv "$0.tmp" "$0"
        log "INFO" "编码修复完成，请重新运行脚本。"
        # 重新执行自身
        exec "$0" "$@"
    fi
}

# 系统检测 (简化，仅用于安装)
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/centos-release ]; then
        OS="centos"
    else
        OS="unknown"
    fi
    log "INFO" "操作系统: $OS"
}

# 安装必要组件 (简化，重点在于 Stream 模块)
install_components() {
    # 检查 netstat (用于端口占用检查)
    if ! command -v netstat &> /dev/null; then
        log "INFO" "安装 netstat/iproute2 (用于端口检查)..."
        case $OS in
            ubuntu|debian) sudo apt update && sudo apt install -y net-tools iproute2 ;;
            centos|rhel|fedora) sudo yum install -y net-tools iproute2 ;;
            *) log "WARNING" "无法自动安装 net-tools/iproute2，请手动安装。" ;;
        esac
    fi

    # 检查是否已安装nginx
    if ! command -v nginx &> /dev/null; then
        log "WARNING" "Nginx未安装。请先手动安装Nginx后再运行此选项。"
        return
    fi
    
    # 确保 stream 模块加载 (尝试自动修复 ssl_preread 问题)
    if ! grep -q "load_module .*ngx_stream_ssl_module\.so;" "$NGINX_CONF"; then
        log "INFO" "尝试自动加载 ngx_stream_ssl_module.so..."
        # 尝试在 worker_processes 后添加模块加载，使用通用和常见路径
        MODULE_LINE="load_module /usr/lib/nginx/modules/ngx_stream_ssl_module.so;"
        
        if grep -q "worker_processes" "$NGINX_CONF"; then
            sed -i "/worker_processes/a\ ${MODULE_LINE}" "$NGINX_CONF"
            log "SUCCESS" "Stream SSL 模块加载指令已添加到 $NGINX_CONF。"
            restart_nginx "y" # 尝试重启以加载模块
        else
            log "WARNING" "无法在 $NGINX_CONF 中定位 worker_processes，请手动添加 ${MODULE_LINE}。"
        fi
    fi
}

# 配置SELinux (保持原逻辑，但给出更安全警告)
configure_selinux() {
    # ... (保持原 configure_selinux 函数，但注意 SELinux 永久禁用需要重启)
    if command -v getenforce &> /dev/null; then
        if [ "$(getenforce)" != "Disabled" ]; then
            log "INFO" "配置SELinux..."
            
            # 临时禁用
            setenforce 0
            
            # 永久禁用
            if [ -f /etc/selinux/config ]; then
                sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
                sed -i 's/^SELINUX=permissive$/SELINUX=disabled/' /etc/selinux/config
            fi
            
            log "SUCCESS" "SELinux已禁用 (警告：完全禁用SELinux会降低系统安全性，并需要重启后永久生效)"
        else
            log "INFO" "SELinux已处于禁用状态"
        fi
    else
        log "INFO" "未检测到SELinux"
    fi
}

# 初始化配置目录 (核心修复点：确保 include 语句在 stream 块内)
init_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        log "INFO" "创建配置目录: $CONFIG_DIR"
        mkdir -p "$CONFIG_DIR"
    fi
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log "INFO" "创建备份目录: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
    fi
    
    # 创建主配置文件（如果不存在或为空）
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        log "INFO" "创建/清空规则文件: $CONFIG_FILE"
        echo "# Auto-generated Nginx Stream Proxy rules by NSM. Do not modify manually." > "$CONFIG_FILE"
    fi
    
    # 确保nginx主配置文件中存在 stream {} 块
    if ! grep -q "stream {" "$NGINX_CONF"; then
        log "WARNING" "Nginx主配置中缺少 stream {} 块，尝试添加..."
        # 在 http {} 之前插入 stream {} 块
        sed -i '/http {/i\
stream {\
    # Stream rules will be included here\
}\
' "$NGINX_CONF"
        log "SUCCESS" "stream {} 块已添加到 $NGINX_CONF。"
    fi

    # 确保 stream {} 块中包含我们的规则文件
    if ! grep -q "include $CONFIG_FILE;" "$NGINX_CONF"; then
        log "INFO" "添加规则文件 include 到 $NGINX_CONF 的 stream {} 块中。"
        
        # 插入配置到 stream { 的下一行
        sed -i "/stream {/a\    include $CONFIG_FILE;" "$NGINX_CONF"
        
        log "SUCCESS" "include $CONFIG_FILE; 已添加到 stream {} 块中。"
    fi
}

# 备份当前配置
backup_config() {
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local backup_name="$BACKUP_DIR/nsm-stream.conf.$timestamp"
    cp "$CONFIG_FILE" "$backup_name"
    log "INFO" "配置已备份到 $backup_name"
}

# 重启 Nginx
restart_nginx() {
    local silent=$1
    if [ "$silent" != "y" ]; then
        show_banner
        echo -e "${BLUE}» Nginx 服务管理${NC}\n"
    fi

    log "INFO" "正在测试 Nginx 配置..."
    if ! nginx -t 2>/dev/null; then
        log "ERROR" "Nginx 配置测试失败。请查看上面的错误信息或日志。"
        [ "$silent" != "y" ] && read -n 1 -s -r -p "按任意键返回主菜单..."
        [ "$silent" != "y" ] && main_menu
        return 1
    fi
    
    log "INFO" "配置测试成功，正在重载/重启 Nginx..."
    if command -v systemctl &> /dev/null; then
        sudo systemctl reload "$NGINX_SERVICE" || sudo systemctl restart "$NGINX_SERVICE"
    else
        sudo service "$NGINX_SERVICE" reload || sudo service "$NGINX_SERVICE" restart
    fi

    if [ $? -eq 0 ]; then
        log "SUCCESS" "Nginx 重载/重启成功，规则已生效。"
    else
        log "ERROR" "Nginx 服务启动/重载失败。请手动检查日志。"
    fi

    [ "$silent" != "y" ] && read -n 1 -s -r -p "按任意键返回主菜单..."
    [ "$silent" != "y" ] && main_menu
    return 0
}

# 添加端口转发规则 (核心修复点：SSL选项和正确的规则结构)
add_rule() {
    show_banner
    echo -e "${BLUE}» 添加端口转发规则${NC}\n"
    
    # ... (端口/IP/协议选择逻辑保持不变，确保 netstat/iproute2 已安装)
    
    # 检查 netstat/ss (用于端口占用检查)
    if ! command -v netstat &> /dev/null && ! command -v ss &> /dev/null; then
        log "WARNING" "未检测到 netstat 或 ss 命令。端口占用检查将跳过。"
    fi

    # 获取本地端口
    while true; do
        read -p "输入本地监听端口: " local_port
        
        # 验证端口是否数字
        if ! [[ "$local_port" =~ ^[0-9]+$ ]] || [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ]; then
            log "ERROR" "无效端口号：端口必须是1-65535之间的整数"
            continue
        fi
        
        # 检查端口是否已被使用
        if (command -v netstat &> /dev/null && netstat -tuln | grep -q ":$local_port ") || \
           (command -v ss &> /dev/null && ss -tuln | grep -q ":$local_port "); then
            log "ERROR" "端口 $local_port 已被系统占用，请选择其他端口"
            continue
        fi
        
        # 检查端口是否已在nginx配置中使用
        if grep -q "listen $local_port;" "$CONFIG_FILE"; then
            log "ERROR" "端口 $local_port 已在Nginx配置中使用"
            continue
        fi
        
        break
    done
    
    # 获取目标服务器
    while true; do
        read -p "输入目标服务器IP: " remote_ip
        if [[ ! "$remote_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log "ERROR" "无效IP地址格式"
            continue
        fi
        IFS='.' read -ra ADDR <<< "$remote_ip"
        if [ "${ADDR[0]}" -gt 255 ] || [ "${ADDR[1]}" -gt 255 ] || [ "${ADDR[2]}" -gt 255 ] || [ "${ADDR[3]}" -gt 255 ]; then
            log "ERROR" "无效IP地址：每段不能大于255"
            continue
        fi
        break
    done
    
    # 获取目标端口
    while true; do
        read -p "输入目标服务器端口: " remote_port
        if ! [[ "$remote_port" =~ ^[0-9]+$ ]] || [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ]; then
            log "ERROR" "无效端口号：端口必须是1-65535之间的整数"
            continue
        fi
        break
    done
    
    # 协议选择
    while true; do
        echo -e "\n选择协议类型:"
        echo -e "  ${GREEN}1${NC}) TCP和UDP (需要Nginx支持UDP模块)"
        echo -e "  ${GREEN}2${NC}) 仅TCP"
        echo -e "  ${GREEN}3${NC}) 仅UDP (需要Nginx支持UDP模块)"
        read -p "请选择 [1-3]: " proto_choice
        
        case $proto_choice in
            1)
                protocols="tcp/udp"
                listen_line="listen $local_port; listen $local_port udp;"
                ;;
            2)
                protocols="tcp"
                listen_line="listen $local_port;"
                ;;
            3)
                protocols="udp"
                listen_line="listen $local_port udp;"
                ;;
            *)
                log "ERROR" "无效选项"
                continue
                ;;
        esac
        break
    done
    
    # SSL 预读选择 (新逻辑)
    ssl_preread_line=""
    proxy_ssl_name_line=""
    if [ "$protocols" != "udp" ]; then
        read -p "是否启用 SSL 预读 (ssl_preread on)? (y/n): " use_ssl
        if [[ "$use_ssl" =~ ^[Yy]$ ]]; then
            read -p "请输入 proxy_ssl_name (例如: yahoo.com): " ssl_name
            if [ -z "$ssl_name" ]; then ssl_name="yahoo.com"; log "WARNING" "proxy_ssl_name 默认设置为 yahoo.com"; fi
            ssl_preread_line="    ssl_preread on;"
            proxy_ssl_name_line="    proxy_ssl_name $ssl_name;"
        fi
    fi

    # 生成规则
    new_rule=$(cat <<-EOF
server {
    $listen_line
${ssl_preread_line}
${proxy_ssl_name_line}
    proxy_connect_timeout 20s;
    proxy_timeout 5m;
    proxy_pass $remote_ip:$remote_port;
}
EOF
)
    
    # 备份当前配置
    backup_config
    
    # 在配置文件末尾追加新规则
    echo -e "$new_rule" >> "$CONFIG_FILE"
    
    log "SUCCESS" "规则已添加：端口 $local_port ($protocols) -> $remote_ip:$remote_port"
    
    # 提示并重载 Nginx
    read -p "是否立即应用配置并重载 Nginx? (y/n): " apply_now
    if [[ "$apply_now" =~ ^[Yy]$ ]]; then
        restart_nginx
    else
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
    fi
}

# ... (view_rules 和 delete_rule 保持原逻辑，但 delete_rule 需补全)

# 查看当前规则
view_rules() {
    show_banner
    echo -e "${BLUE}» 当前 Stream 转发规则列表 (${CONFIG_FILE})${NC}\n"
    
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ] || ! grep -q "server {" "$CONFIG_FILE"; then
        log "INFO" "没有配置任何转发规则。"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
        return
    fi
    
    grep -A 5 "server {" "$CONFIG_FILE" | awk '
        /server {/ {print "\n• 规则 " NR ":"}
        /listen/ {
            if ($3 == "udp;") {
                printf "  监听协议/端口: %s/%s\n", "UDP", substr($2, 1, length($2)-1)
            } else {
                printf "  监听协议/端口: %s/%s\n", "TCP", substr($2, 1, length($2)-1)
            }
        }
        /proxy_pass/ {print "  目标服务器:", substr($2, 1, length($2)-1)}
        /ssl_preread/ {print "  SSL 预读: 启用"}
    '
    echo -e ""
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
    main_menu
}


# 删除端口转发规则 (修复：补全删除操作)
delete_rule() {
    show_banner
    echo -e "${BLUE}» 删除端口转发规则${NC}\n"
    
    # ... (原有的查看规则和获取序号的逻辑)
    if ! grep -q "server {" "$CONFIG_FILE"; then
        log "INFO" "没有配置任何转发规则"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
        return
    fi
    
    echo -e "${YELLOW}当前转发规则列表:${NC}"
    server_lines=($(grep -n "server {" "$CONFIG_FILE" | cut -d: -f1))
    
    # 重新生成列表以显示序号和内容
    count=0
    for start_line in "${server_lines[@]}"; do
        count=$((count + 1))
        
        # 查找结束行
        end_line=$(sed -n "$start_line,\$p" "$CONFIG_FILE" | grep -m 1 -n "}" | head -1 | cut -d: -f1)
        end_line=$((start_line + end_line - 1))
        
        # 提取端口信息用于显示
        listen_info=$(sed -n "${start_line},${end_line}p" "$CONFIG_FILE" | grep 'listen' | head -1 | awk '{print $2}' | tr -d ';')
        target_info=$(sed -n "${start_line},${end_line}p" "$CONFIG_FILE" | grep 'proxy_pass' | head -1 | awk '{print $2}' | tr -d ';')
        
        echo -e "• 规则 ${GREEN}$count${NC}：监听端口 $listen_info -> 目标 $target_info"
    done
    echo -e ""
    
    # 获取要删除的规则
    while true; do
        read -p "输入要删除的规则序号 (输入c取消): " rule_num
        
        if [ "$rule_num" = "c" ]; then main_menu; return; fi
        if ! [[ "$rule_num" =~ ^[0-9]+$ ]] || [ "$rule_num" -lt 1 ] || [ "$rule_num" -gt "$count" ]; then
            log "ERROR" "请输入有效的规则序号 [1-$count]"
            continue
        fi
        
        start_line=${server_lines[$((rule_num-1))]}
        
        # 查找结束行
        end_line=$(sed -n "$start_line,\$p" "$CONFIG_FILE" | grep -m 1 -n "}" | head -1 | cut -d: -f1)
        end_line=$((start_line + end_line - 1))
        
        break
    done
    
    # 备份当前配置
    backup_config
    
    # 【修复：执行删除操作】
    sed -i "${start_line},${end_line}d" "$CONFIG_FILE"
    
    log "SUCCESS" "规则 $rule_num 已删除 (行 $start_line - $end_line)"
    
    # 提示并重载 Nginx
    read -p "是否立即应用配置并重载 Nginx? (y/n): " apply_now
    if [[ "$apply_now" =~ ^[Yy]$ ]]; then
        restart_nginx
    else
        read -n 1 -s -r -p "按任意键返回主菜单..."
        main_menu
    fi
}

# 系统检查 (保持原逻辑，但进行优化)
system_check() {
    show_banner
    echo -e "${BLUE}» 系统环境检查${NC}\n"
    detect_os # 显示操作系统信息
    
    echo -e "${YELLOW}--- Nginx 状态 ---${NC}"
    if command -v nginx &> /dev/null; then
        echo -e "Nginx 命令: ${GREEN}存在${NC} ($(command -v nginx))"
    else
        echo -e "Nginx 命令: ${RED}缺失${NC}"
    fi

    echo -e "Nginx 服务: $(systemctl is-active nginx 2>/dev/null)"
    
    echo -e "\n${YELLOW}--- 配置文件状态 ---${NC}"
    echo -e "规则文件 ($CONFIG_FILE): $([ -f "$CONFIG_FILE" ] && echo "${GREEN}存在${NC}" || echo "${RED}缺失${NC}")"
    
    # 检查主配置 include 状态
    if grep -q "include $CONFIG_FILE;" "$NGINX_CONF"; then
        include_status="${GREEN}已包含${NC}"
    else
        include_status="${RED}未包含${NC}"
    fi
    echo -e "主配置 Include 状态: $include_status"
    
    # 检查 Stream SSL 模块加载状态
    if grep -q "load_module .*ngx_stream_ssl_module\.so;" "$NGINX_CONF"; then
        ssl_module_status="${GREEN}已加载${NC}"
    else
        ssl_module_status="${RED}未加载 (可能导致 ssl_preread 失败)${NC}"
    fi
    echo -e "Stream SSL 模块: $ssl_module_status"
    
    echo -e "\n${YELLOW}--- SELinux 状态 ---${NC}"
    if command -v getenforce &> /dev/null; then
        echo "当前状态: $(getenforce)"
    else
        echo "未检测到 SELinux"
    fi
    
    read -n 1 -s -r -p "\n按任意键返回主菜单..."
    main_menu
}

# 显示横幅
show_banner() {
    # ... (保持原 show_banner 函数)
    clear
    echo -e "${MAGENTA}"
    echo -e "==============================================================================="
    echo -e "                                                                               "
    echo -e " ███╗  ██╗███████╗███╗  ███╗      ███████╗████████╗██████╗ ███████╗ █████╗ "
    echo -e " ████╗ ██║██╔════╝████╗ ████║      ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔══██╗"
    echo -e " ██╔██╗██║███████╗██╔████╔██║      ███████╗  ██║  ██████╔╝█████╗  ███████║"
    echo -e " ██║╚██╗██║╚════██║██║╚██╔╝██║      ╚════██║  ██║  ██╔══██╗██╔══╝  ██╔══██║"
    echo -e " ██║ ╚████║███████║██║ ╚═╝ ██║███████╗ ███████║  ██║  ██║  ██║███████╗██║  ██║"
    echo -e " ╚═╝  ╚═══╝╚══════╝╚═╝    ╚═╝╚══════╝ ╚══════╝  ╚═╝  ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
    echo -e "                                                                               "
    echo -e "              Nginx Stream 端口转发管理工具 v1.0.1 (修复版)                "
    echo -e "                                                                               "
    echo -e "===============================================================================${NC}"
    echo -e ""
}

# 主菜单 (调用入口)
main_menu_entry() {
    check_root
    check_encoding # 检查和修复编码问题 (如果检测到，会重新执行)
    init_log
    detect_os
    init_config_dir # 修复了 stream 块冲突和 include 路径
    
    # 循环主菜单
    while true; do
        main_menu
    done
}

# 脚本启动 (修复后的逻辑)
if [ "$1" = "init_config_dir" ]; then
    check_root
    init_config_dir
    exit 0 # 成功执行后退出
elif [ "$1" = "install_components" ]; then
    check_root
    detect_os
    install_components
    exit 0 # 成功执行后退出
else
    # 正常启动菜单入口
    main_menu_entry
fi
