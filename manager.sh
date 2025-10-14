#!/bin/bash

# --- Script Configuration ---
CONFIG_FILE="/etc/nginx/conf.d/stream_proxy.conf"
MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_SERVICE="nginx"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- Helper Functions ---

setup_environment() {
    echo -e "${GREEN}--- Checking Environment and Nginx Configuration ---${NC}"

    if ! command -v nginx &> /dev/null; then
        echo -e "${RED}ERROR: Nginx is not installed. Exiting.${NC}"
        exit 1
    fi

    # Ensure this block runs with root privileges (nsm is called with sudo)
    if [ ! -d "/etc/nginx/conf.d" ]; then
        echo "Creating config directory /etc/nginx/conf.d"
        mkdir -p /etc/nginx/conf.d
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Creating Stream configuration file: $CONFIG_FILE"
        {
            echo "stream {"
            echo "}"
        } | tee "$CONFIG_FILE" > /dev/null
    fi

    if ! grep -q "include /etc/nginx/conf.d/\*.conf;" "$MAIN_CONF"; then
        echo -e "${RED}WARNING: Nginx main config ($MAIN_CONF) may be missing 'include /etc/nginx/conf.d/*.conf;'$NC"
        echo "Ensure this line is outside the 'http {}' block, or rules added here will not work."
    fi
}

generate_config_block() {
    local LISTEN_PORT=$1
    local TARGET_ADDR=$2
    local USE_SSL=$3
    local SSL_NAME=$4

    cat << EOF
    server {
        listen ${LISTEN_PORT};
        listen ${LISTEN_PORT} udp;
        proxy_connect_timeout 20s;
        proxy_timeout 5m;
        
        # Rule Identifier: ${LISTEN_PORT} -> ${TARGET_ADDR}
EOF

    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        cat << EOF
        ssl_preread on;
        proxy_ssl_name ${SSL_NAME};
EOF
    fi

    cat << EOF
        proxy_pass ${TARGET_ADDR};
    }
EOF
}

# --- Feature 1: Add Rule ---
add_rule() {
    echo -e "\n${GREEN}--- Add New Forwarding Rule ---${NC}"
    read -r -p "Enter Listen Port (e.g., 55203): " LISTEN_PORT
    read -r -p "Enter Target Address (IP:Port, e.g., 31.56.123.199:55203): " TARGET_ADDR
    read -r -p "Enable SSL Preread? (y/n): " USE_SSL

    local SSL_NAME=""
    if [[ "$USE_SSL" =~ ^[Yy]$ ]]; then
        read -r -p "Enter proxy_ssl_name (e.g., yahoo.com): " SSL_NAME
        if [ -z "$SSL_NAME" ]; then
            SSL_NAME="default_sni"
        fi
    fi

    CONFIG_BLOCK=$(generate_config_block "$LISTEN_PORT" "$TARGET_ADDR" "$USE_SSL" "$SSL_NAME")

    # Find the end line of the stream block '}'
    local END_LINE=$(grep -n "^}" "$CONFIG_FILE" | tail -n 1 | cut -d: -f1)
    
    if [ -n "$END_LINE" ] && [ "$END_LINE" -gt 1 ]; then
        # Insert block before the last '}'
        echo "$CONFIG_BLOCK" | sed -i "$((END_LINE - 1))r /dev/stdin" "$CONFIG_FILE"
        echo -e "${GREEN}Rule added to $CONFIG_FILE.${NC}"
        read -r -p "Apply config and reload Nginx now? (y/n): " APPLY_NOW
        if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
            apply_config
        fi
    else
        echo -e "${RED}ERROR: Could not find '}' to insert config. Check $CONFIG_FILE manually.${NC}"
    fi
}

# --- Feature 2: View Rules ---
view_rules() {
    echo -e "\n${GREEN}--- Current Stream Forwarding Configuration (${CONFIG_FILE}) ---${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        # Exclude the stream {} wrapper lines
        cat "$CONFIG_FILE" | grep -v "^stream" | grep -v "^}" | nl -ba -s ". "
    else
        echo -e "${RED}Configuration file not found.${NC}"
    fi
    echo ""
}

# --- Feature 3: Delete Rule ---
delete_rule() {
    view_rules
    if [ -s "$CONFIG_FILE" ] && [ "$(grep -c "server {" "$CONFIG_FILE")" -eq 0 ]; then
        echo -e "${RED}No forwarding rules to delete.${NC}"
        return
    fi
    read -r -p "Enter Listen Port of the rule to delete: " PORT_TO_DELETE
    
    if [ -z "$PORT_TO_DELETE" ]; then

    # Find the start line of the server block using the listen port
    SERVER_END_OFFSET=$(sed -n "${START_LINE},\$p" "$CONFIG_FILE" | grep -n "}" | head -n 1 | cut -d: -f1)
    SERVER_END=$((SERVER_START + SERVER_END_OFFSET - 1))
    
        sed -i "$SERVER_START,${SERVER_END}d" "$CONFIG_FILE"
        echo -e "${GREEN}Rule deleted.${NC}"
        read -r -p "Apply config and reload Nginx now? (y/n): " APPLY_NOW
        if [[ "$APPLY_NOW" =~ ^[Yy]$ ]]; then
            apply_config
        fi
    else
        echo -e "${RED}Deletion failed: Could not locate complete server block. Check file manually.${NC}"
    fi
}

# --- Feature 4: Apply Config and Reload Nginx ---
apply_config() {
    echo -e "\n${GREEN}--- Testing Nginx Configuration ---${NC}"
    nginx -t

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Config test successful! Reloading Nginx...${NC}"
        if systemctl reload "$NGINX_SERVICE"; then
            echo -e "${GREEN}Nginx reloaded, new rules are active.${NC}"
        else
            echo -e "${RED}ERROR: Nginx reload failed. Check system logs.${NC}"
        fi
    else
        echo -e "${RED}Config test failed. New config NOT applied.${NC}"
    fi
}

# --- Main Menu ---
main_menu() {
    # Check if run as root (nsm is called with sudo, so we are root here)
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}ERROR: This script must be run with root privileges (sudo).${NC}"
        exit 1
    fi
    
    # Setup environment (creates files if needed)
    setup_environment

    while true; do
        echo -e "\n${GREEN}=============================================${NC}"
        echo -e "${GREEN} Nginx Stream Manager (v1.0) ${NC}"
        echo -e "${GREEN}=============================================${NC}"
        echo "1. Add New Forwarding Rule"
        echo "2. View Current Forwarding Rules"
        echo "3. Delete Forwarding Rule (by Listen Port)"
        echo "4. Apply Config and Reload Nginx (Make changes live)"
        echo "5. Exit"
        echo -e "${GREEN}=============================================${NC}"
        
        read -r -p "Select an operation [1-5]: " CHOICE

        case "$CHOICE" in
            1) add_rule ;;
            2) view_rules ;;
            3) delete_rule ;;
            4) apply_config ;;
            5) echo "Thank you for using the manager. Goodbye!"; exit 0 ;;
            *) echo -e "${RED}Invalid input, please select a number between 1 and 5.${NC}" ;;
        esac
    done
}

# --- Script Start ---
main_menu    if [ -n "$SERVER_START" ] && [ -n "$SERVER_END" ]; then
        echo -e "${GREEN}Deleting rule block from line $SERVER_START to $SERVER_END...${NC}"
        # Delete the line range
    START_LINE=$(grep -n "listen ${PORT_TO_DELETE};" "$CONFIG_FILE" | cut -d: -f1 | head -n 1)

    SERVER_START=$(sed -n "1,${START_LINE}p" "$CONFIG_FILE" | grep -n "server {" | tail -n 1 | cut -d: -f1)
    if [ -z "$START_LINE" ]; then
        echo -e "${RED}Rule listening on port ${PORT_TO_DELETE} not found.${NC}"
    # Locate the start and end of the server {} block
        return
    fi
    
        echo -e "${RED}Port number cannot be empty.${NC}"
        return
    fi

