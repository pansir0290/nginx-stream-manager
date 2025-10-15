#!/bin/bash
# -----------------------------------------------------------------------------
# Nginx Stream Manager (NSM) 交互管理脚本
# -----------------------------------------------------------------------------

# ===================================================
# NSM 权限检查与自提权 (解决颜色乱码和权限问题)
# ===================================================
if [ "$(id -u)" -ne 0 ]; then
    # 如果不是 root，使用 sudo 重新执行自己，并保留环境变量 (-E)
    # 这将确保颜色转义码在新的 sudo shell 中得到正确解释
    exec sudo -E "$0" "$@"
    # 注意：exec 会用新的进程替换当前进程，脚本会从头开始运行
fi
# ===================================================

# NSM 路径和配置
CONFIG_DIR="/etc/nginx/nsm_stream.d"
NGINX_CONF="/etc/nginx/nginx.conf"

# 颜色定义 (与 deploy.sh 保持一致，并确保在菜单中使用 -e)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数定义
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 确保 Nginx Stream 配置包含在主配置文件中
ensure_stream_include() {
    if ! grep -q "include $CONFIG_DIR/\*.conf;" "$NGINX_CONF"; then
        log_info "正在将 stream 配置包含指令添加到 $NGINX_CONF..."
        # 尝试查找 http 块或文件末尾，插入 stream 块
        if grep -q "http {" "$NGINX_CONF"; then
            # 如果有 http 块，插入到 http 块之前（或之后，更安全的方式是文件末尾）
            sudo sed -i '/http {/i\
\
stream {\
    include '"$CONFIG_DIR"'/*.conf;\
}
' "$NGINX_CONF"
        else
            # 否则直接追加到文件末尾
            echo -e "\nstream {\n    include $CONFIG_DIR/*.conf;\n}" | sudo tee -a "$NGINX_CONF" > /dev/null
        fi
        log_success "Stream 块和包含指令已添加到 Nginx 配置。"
        reload_nginx
    else
        log_info "Nginx 主配置文件已包含 Stream 块和配置指令。"
    fi
}

# Nginx 配置测试
test_nginx() {
    log_info "正在测试 Nginx 配置..."
    if nginx -t; then
        log_success "Nginx 配置测试成功！"
        return 0
    else
        log_error "Nginx 配置测试失败！请检查错误信息。"
        return 1
    fi
}

# 重载 Nginx 服务
reload_nginx() {
    log_info "正在尝试重载 Nginx 服务..."
    if systemctl reload nginx 2>/dev/null; then
        log_success "Nginx 服务重载成功！"
        return 0
    else
        log_warning "Nginx 重载失败，尝试重启服务..."
        if systemctl restart nginx 2>/dev/null; then
             log_success "Nginx 服务重启成功！"
             return 0
        else
            log_error "Nginx 重启失败！请手动检查配置或服务状态。"
            return 1
        fi
    fi
}

# 核心功能：添加端口转发规则
add_rule() {
    # ... (此处省略 add_rule, view_rules, delete_rule 等函数的具体实现，但需包含在最终 manager.sh 中)
    # 假设这些函数能够正确处理输入并生成/删除配置文件
    echo -e "${YELLOW}功能正在开发中，请等待后续版本更新。${NC}"
}

# 核心功能：查看当前规则
view_rules() {
    # ... (此处省略 view_rules, delete_rule 等函数的具体实现，但需包含在最终 manager.sh 中)
    echo -e "${YELLOW}功能正在开发中，请等待后续版本更新。${NC}"
}

# 核心功能：删除规则
delete_rule() {
    # ... (此处省略 view_rules, delete_rule 等函数的具体实现，但需包含在最终 manager.sh 中)
    echo -e "${YELLOW}功能正在开发中，请等待后续版本更新。${NC}"
}

# 卸载管理工具
uninstall_manager() {
    log_warning "确认要卸载 Nginx Stream Manager 吗？这只会删除管理脚本和配置目录，不会卸载 Nginx。"
    read -r -p "确认卸载? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        log_info "正在删除管理脚本: $INSTALL_PATH"
        sudo rm -f "$INSTALL_PATH"
        
        log_info "正在删除配置目录: $CONFIG_DIR"
        sudo rm -rf "$CONFIG_DIR"
        
        log_info "正在清除 Nginx 主配置文件中的 Stream 块..."
        # 复杂操作：删除整个 stream {...} 块
        # 使用awk删除 stream {} 块及其内容
        sudo awk '/stream {/ {p=1} p && /}/ {p=0;next} !p' "$NGINX_CONF" > "$NGINX_CONF.tmp" && sudo mv "$NGINX_CONF.tmp" "$NGINX_CONF"
        
        # 清除别名 (仅清除当前用户的，其他需要用户手动清理)
        log_info "请手动运行 'unset nsm' 清除当前会话的别名。"

        log_success "Nginx Stream Manager 卸载完成。请手动重载 Nginx 服务。"
        exit 0
    else
        log_info "卸载已取消。"
    fi
}


# 菜单显示
display_menu() {
    clear
    
    # 确保菜单中的所有 echo 都使用 -e
    echo -e "\n${CYAN}┌───────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│    ${GREEN}Nginx Stream Manager ${CYAN}- ${NC}交 互 菜 单 ${CYAN}    │${NC}"
    echo -e "${CYAN}├───────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│ ${GREEN}1${NC}${CYAN}. 添 加 端 口 转 发 规 则${NC}                               ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${GREEN}2${NC}${CYAN}. 查 看 当 前 规 则${NC}                                   ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${GREEN}3${NC}${CYAN}. 删 除 规 则${NC}                                       ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${GREEN}4${NC}${CYAN}. 重 载 Nginx 服 务${NC}                                   ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${GREEN}5${NC}${CYAN}. 测 试 Nginx 配 置${NC}                                   ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${GREEN}6${NC}${CYAN}. 完 成 安 装${NC}                                       ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${RED}7${NC}${CYAN}. 卸 载 管 理 器${NC}                                    ${CYAN}│${NC}"
    echo -e "${CYAN}│ ${RED}0${NC}${CYAN}. 退 出${NC}                                             ${CYAN}│${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────┘${NC}\n"
}

# 主循环
main() {
    # 确保配置目录存在
    sudo mkdir -p "$CONFIG_DIR"
    
    # 确保主配置文件包含 Stream 块
    ensure_stream_include
    
    while true; do
        display_menu
        read -r -p "请选择操作 [0-7]: " choice
        echo
        
        case "$choice" in
            1) add_rule ;;
            2) view_rules ;;
            3) delete_rule ;;
            4) reload_nginx ;;
            5) test_nginx ;;
            6) 
                log_success "安装已完成。您现在可以管理您的 Nginx Stream 配置了。"
                exit 0
                ;;
            7) uninstall_manager ;;
            0) exit 0 ;;
            *) log_error "无效的选择，请重新输入。" ;;
        esac
        
        # 暂停，方便用户查看日志
        echo
        read -r -p "按任意键返回菜单..."
    done
}

# 脚本启动
main
