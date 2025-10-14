#!/bin/bash

# --- 脚本配置 ---
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_SERVICE="nginx"
MANAGER_URL="https://raw.githubusercontent.com/pansir0290/nginx-stream-manager/main/manager.sh"
MANAGER_PATH="/usr/local/bin/nsm"
BACKUP_DIR="/etc/nginx/conf-backup"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 用于存储时间戳的全局变量
CURRENT_TIMESTAMP=""

# --- 核心函数 ---

# 查找SSL模块路径
find_ssl_module() {
    local paths=(
        "/usr/lib/nginx/modules"
        "/usr/lib64/nginx/modules"
        "/usr/lib/x86_64-linux-gnu/nginx/modules"
        "/usr/share/nginx/modules"
    )
    
    for path in "${paths[@]}"; do
        if [ -f "$path/ngx_stream_ssl_module.so" ]; then
            echo "$path/ngx_stream_ssl_module.so"
            return 0
        fi
    done
    
    echo ""
    return 1
}

# 创建配置备份
create_backup() {
    echo -e "${YELLOW}创建配置备份...${NC}"
    sudo mkdir -p "$BACKUP_DIR"
    
    # 获取当前时间戳（如果尚未设置）
    [ -z "$CURRENT_TIMESTAMP" ] && CURRENT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    
    sudo cp -f "$MAIN_CONF" "$BACKUP_DIR/nginx.conf.bak-$CURRENT_TIMESTAMP"
    [ -f "$CONFIG_FILE" ] && sudo cp -f "$CONFIG_FILE" "$BACKUP_DIR/stream_proxy.conf.bak-$CURRENT_TIMESTAMP"
    
    echo -e "${GREEN}配置已备份到: ${YELLOW}$BACKUP_DIR${NC}"
    echo -e "备份文件: ${GREEN}nginx.conf.bak-$CURRENT_TIMESTAMP${NC}"
    [ -f "$CONFIG_FILE" ] && echo -e "备份文件: ${GREEN}stream_proxy.conf.bak-$CURRENT_TIMESTAMP${NC}"
}

# 验证Nginx配置
validate_nginx_config() {
    echo -e "${YELLOW}验证Nginx配置...${NC}"
    
    # 确保有当前时间戳
    [ -z "$CURRENT_TIMESTAMP" ] && CURRENT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    
    if ! sudo nginx -t > /dev/null 2>&1; then
        echo -e "${RED}错误: Nginx配置验证失败${NC}"
        
        # 恢复备份
        echo -e "${YELLOW}尝试恢复原始配置...${NC}"
        sudo cp -f "$BACKUP_DIR/nginx.conf.bak-$CURRENT_TIMESTAMP" "$MAIN_CONF"
        [ -f "$BACKUP_DIR/stream_proxy.conf.bak-$CURRENT_TIMESTAMP" ] && \
            sudo cp -f "$BACKUP_DIR/stream_proxy.conf.bak-$CURRENT_TIMESTAMP" "$CONFIG_FILE"
        
        # 重新验证
        if sudo nginx -t > /dev/null 2>&1; then
            echo -e "${GREEN}配置已成功恢复${NC}"
        else
            echo -e "${RED}严重错误: 无法恢复有效配置，请手动修复${NC}"
            echo -e "错误详情:"
            sudo nginx -t
            exit 1
        fi
        return 1
    fi
    return 0
}

# 重启Nginx服务
restart_nginx_service() {
    echo -e "${YELLOW}尝试重启Nginx...${NC}"
    
    if systemctl list-unit-files | grep -q "^${NGINX_SERVICE}.service"; then
        sudo systemctl restart "$NGINX_SERVICE" && return 0
    fi
    
    if command -v service > /dev/null; then
        sudo service "$NGINX_SERVICE" restart && return 0
    fi
    
    if [ -f "/etc/init.d/$NGINX_SERVICE" ]; then
        sudo "/etc/init.d/$NGINX_SERVICE" restart && return 0
    fi
    
    echo -e "${YELLOW}警告: 无法自动重启服务，请手动执行: ${RED}nginx -s reload${NC}"
    return 1
}

# 检查依赖项
check_dependencies() {
    local missing=()
    
    for cmd in curl nginx sed grep; do
        if ! command -v $cmd > /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}错误: 缺少依赖项: ${missing[*]}${NC}"
        echo "请安装后再运行此脚本"
        exit 1
    fi
}

# 配置Nginx主文件
configure_nginx_main_conf() {
    echo -e "\n--- 配置Nginx主文件 ---"
    local needs_restart=0
    local ssl_module=$(find_ssl_module)
    
    # 1. 添加Stream SSL模块
    if [ -n "$ssl_module" ]; then
        if ! grep -q "load_module .*ngx_stream_ssl_module\.so" "$MAIN_CONF"; then
            echo -e "${YELLOW}添加Stream SSL模块: $ssl_module${NC}"
            sudo sed -i "1i load_module ${ssl_module};" "$MAIN_CONF"
            needs_restart=1
        else
            echo -e "${GREEN}Stream SSL模块已加载${NC}"
        fi
    else
        echo -e "${YELLOW}警告: 未找到Stream SSL模块，SSL相关功能可能受限${NC}"
    fi
    
    # 2. 添加Stream块
    if ! grep -q "stream\s*{" "$MAIN_CONF"; then
        echo -e "${YELLOW}添加Stream配置块${NC}"
        # 修复这里的引号问题
        sudo tee -a "$MAIN_CONF" > /dev/null <&lt;EOF

# Nginx Stream Manager 配置
stream {
    include $CONFIG_FILE;
}
EOF
        needs_restart=1
    else
        echo -e "${GREEN}Stream配置块已存在${NC}"
        
        # 检查include指令
        if ! grep -q "include\s*$CONFIG_FILE" "$MAIN_CONF"; then
            echo -e "${YELLOW}添加include指令${NC}"
            sudo sed -i "/stream\s*{/a \\    include $CONFIG_FILE;" "$MAIN_CONF"
            needs_restart=1
        fi
    fi
    
    # 3. 添加全局超时设置
    if ! grep -q "proxy_connect_timeout" "$MAIN_CONF"; then
        echo -e "${YELLOW}添加默认超时设置${NC}"
        sudo sed -i "/stream\s*{/a \\    proxy_connect_timeout 20s;\n    proxy_timeout 5m;" "$MAIN_CONF"
        needs_restart=1
    fi
    
    return $needs_restart
}

# 安装管理脚本
install_manager() {
    echo -e "\n--- 安装管理工具 ---"
    echo "下载管理脚本: $MANAGER_URL"
    
    if ! sudo curl -fSL "$MANAGER_URL" -o "$MANAGER_PATH"; then
        echo -e "${RED}错误: 下载管理脚本失败${NC}"
        return 1
    fi
    
    sudo chmod +x "$MANAGER_PATH"
    echo -e "${GREEN}管理工具已安装到: $MANAGER_PATH${NC}"
    
    # 添加bash别名
    if ! grep -q "alias nsm=" ~/.bashrc; then
        echo "alias nsm='sudo $MANAGER_PATH'" &gt;> ~/.bashrc
        echo -e "${GREEN}已添加 'nsm' 别名到 ~/.bashrc${NC}"
    fi
    
    return 0
}

# --- 主部署函数 ---
deploy() {
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：此脚本必须使用root权限运行 (sudo)${NC}"
        exit 1
    fi
    
    # 生成全局时间戳
    CURRENT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    
    # 创建备份目录
    sudo mkdir -p "$BACKUP_DIR"
    
    check_dependencies
    create_backup
    local needs_restart=0
    
    # 创建配置目录
    sudo mkdir -p "$(dirname "$CONFIG_FILE")"
    sudo touch "$CONFIG_FILE"
    
    # 初始化配置文件内容 (仅包含注释，避免无效指令)
    sudo tee "$CONFIG_FILE" > /dev/null <&lt;EOF
# Nginx Stream Manager 配置文件
# 由 nsm 工具自动管理，请勿手动编辑

EOF
    
    # 配置主文件
    if configure_nginx_main_conf; then
        needs_restart=1
    fi
    
    # 安装管理工具
    install_manager
    
    # 需要重启Nginx
    if [ $needs_restart -eq 1 ]; then
        if validate_nginx_config; then
            restart_nginx_service && echo -e "${GREEN}Nginx已成功重启${NC}"
        else
            echo -e "${RED}配置验证失败，Nginx未重启${NC}"
        fi
    fi
    
    echo -e "\n${GREEN}✓ 部署成功!${NC}"
    echo -e "使用命令: ${YELLOW}nsm${NC} 进入交互式管理界面"
    echo -e "或直接使用命令行: ${YELLOW}nsm add tcp 8080 example.com:80${NC}"
    echo -e "请执行: ${YELLOW}source ~/.bashrc${NC} 以使 nsm 命令生效"
    echo -e "当前配置备份: ${GREEN}$BACKUP_DIR/${NC}"
}

# --- 执行主函数 ---
case "$1" in
    uninstall|remove|--uninstall)
        uninstall
        ;;
    *)
        deploy
        ;;
esac

# 卸载函数 (如果部署成功不需要使用)
uninstall() {
    echo -e "\n${YELLOW}--- 卸载Nginx Stream Manager ---${NC}"
    
    # 移除管理脚本
    if [ -f "$MANAGER_PATH" ]; then
        sudo rm -f "$MANAGER_PATH"
        echo -e "${GREEN}已移除管理脚本${NC}"
    fi
    
    # 清理bash别名
    sed -i '/alias nsm=/d' ~/.bashrc
    
    # 恢复原始配置
    if [ -d "$BACKUP_DIR" ]; then
        local latest_backup=$(ls -t "$BACKUP_DIR" | grep 'nginx.conf.bak' | head -1)
        
        if [ -n "$latest_backup" ]; then
            echo -e "${YELLOW}恢复Nginx主配置${NC}"
            sudo cp -f "$BACKUP_DIR/$latest_backup" "$MAIN_CONF"
        fi
    else
        # 尝试自动清理
        sudo sed -i '/# Nginx Stream Manager/,/}/d' "$MAIN_CONF"
        sudo sed -i '/load_module .*ngx_stream_ssl_module\.so;/d' "$MAIN_CONF"
    fi
    
    # 移除配置文件
    if [ -f "$CONFIG_FILE" ]; then
        sudo rm -f "$CONFIG_FILE"
    fi
    
    restart_nginx_service
    echo -e "${GREEN}卸载完成!${NC}"
}
