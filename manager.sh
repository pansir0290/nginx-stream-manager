#!/bin/bash
# ... (配置、颜色定义、setup_environment, generate_config_block 函数不变) ...

# --- 新增功能 1: 安装依赖 ---
install_dependencies() {
    echo -e "\n${GREEN}--- 安装 SELinux/系统依赖 ---${NC}"
    
    if command -v apt &> /dev/null; then
        echo -e "${YELLOW}检测到 Debian/Ubuntu 系统。${NC}"
        read -r -p "是否运行 'sudo apt update' 并安装 SELinux 管理工具? (y/n): " INSTALL_CONFIRM
        if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
            sudo apt update
            sudo apt install -y policycoreutils
            echo -e "${GREEN}SELinux 管理工具安装完成。${NC}"
        fi
    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        echo -e "${YELLOW}检测到 RHEL/CentOS/Fedora 系统。${NC}"
        read -r -p "是否安装 SELinux 管理工具 (policycoreutils-python-utils)? (y/n): " INSTALL_CONFIRM
        if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
            sudo $(command -v dnf || echo "yum") install -y policycoreutils-python-utils
            echo -e "${GREEN}SELinux 管理工具安装完成。${NC}"
        fi
    else
        echo -e "${RED}错误：无法识别您的包管理器。请手动安装 policycoreutils 包。${NC}"
    fi
}


# --- 功能 2: 配置 SELinux --- (原功能 1，函数名称和逻辑不变，但编号变动)
configure_selinux() {
    echo -e "\n${GREEN}--- 配置 SELinux 策略 ---${NC}"
    
    if ! command -v getenforce &> /dev/null; then
        echo -e "${YELLOW}警告：系统似乎没有安装 SELinux 工具。请先运行选项 1 安装依赖。${NC}"
        return
    fi
    # ... (函数其余部分不变) ...
    
    # 策略放宽部分，现在假设依赖已安装
    # ... (策略放宽代码不变) ...
}

# --- 功能 3: 添加规则 --- (原功能 2)
add_rule() {
    # ... (不变) ...
}

# --- 功能 4: 查看规则 --- (原功能 3)
view_rules() {
    # ... (不变) ...
}

# --- 功能 5: 删除规则 --- (原功能 4)
delete_rule() {
    # ... (不变) ...
}

# --- 功能 6: 应用配置并重载 Nginx --- (原功能 5)
apply_config() {
    # ... (不变) ...
}


# --- 主菜单 (Main Menu) ---
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
        echo "1. 安装 SELinux/系统依赖"               # <--- 新增
        echo "2. 配置 SELinux (解决连接被拒问题)"     # <--- 编号变动
        echo "3. 添加新的转发规则"
        echo "4. 查看当前转发规则"
        echo "5. 删除转发规则 (按监听端口)"
        echo "6. 应用配置并重载 Nginx (使更改生效)"
        echo "7. 退出"                                # <--- 编号变动
        echo -e "${GREEN}=============================================${NC}"
        
        read -r -p "请选择操作 [1-7]: " CHOICE

        case "$CHOICE" in
            1) install_dependencies ;; # <--- 新增调用
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