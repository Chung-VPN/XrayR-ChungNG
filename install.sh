#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[0;36m'
blue='\033[0;34m'
bold='\033[1m'
plain='\033[0m'


GITHUB_USER="Chung-VPN"                    
GITHUB_REPO="XrayR-ChungNG"                

BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"
CONFIG_URL="${BASE_URL}/config.yml"
BINARY_AMD64_URL="${BASE_URL}/bin/XrayR-linux-amd64"
BINARY_ARM64_URL="${BASE_URL}/bin/XrayR-linux-arm64"

XRAYR_DIR="/usr/local/XrayR"
XRAYR_BIN="$XRAYR_DIR/XrayR"
XRAYR_CFG="/etc/XrayR/config.yml"
XRAYR_SVC="/etc/systemd/system/XrayR.service"



declare -a NODE_IDS
declare -a NODE_TYPES
declare -a NODE_NAMES

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${red}Cần chạy bằng root!${plain}\n${yellow}Chạy: sudo bash install.sh${plain}" && exit 1
}

detect_os() {
    if [[ -f /etc/redhat-release ]]; then          
        release="centos"
    elif grep -Eqi "debian|ubuntu" /etc/issue 2>/dev/null; then  
        release="debian"
    elif grep -Eqi "debian|ubuntu" /proc/version 2>/dev/null; then  
        release="debian"
    else 
        echo -e "${red}OS không được hỗ trợ!${plain}"
        exit 1
    fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  
            arch="amd64"
            BINARY_URL="$BINARY_AMD64_URL"
            ;;
        aarch64|arm64) 
            arch="arm64"
            BINARY_URL="$BINARY_ARM64_URL"
            ;;
        *)  
            echo -e "${red}Kiến trúc không hỗ trợ: $(uname -m)${plain}"
            exit 1
            ;;
    esac
}

is_installed() { 
    [[ -f "$XRAYR_BIN" ]]
}

svc_badge() {
    if ! is_installed; then
        echo -e "  Trạng thái: ${red}● Chưa cài${plain}"
    elif systemctl is-active --quiet XrayR 2>/dev/null; then
        echo -e "  Trạng thái: ${green}● Đang chạy${plain}"
    else
        echo -e "  Trạng thái: ${yellow}● Đã cài, chưa chạy${plain}"
    fi
}

header() {
    clear
    echo -e "${cyan}════════════════════════════════════════════════${plain}"
    echo -e "${bold}${green}    XrayR Multi-Node Installer — V2Board${plain}"
    echo -e "${cyan}════════════════════════════════════════════════${plain}"
    svc_badge
    echo ""
}

install_deps() {
    echo -e "${blue}[*] Cài dependencies...${plain}"
    case "$release" in
        debian|ubuntu)
            apt-get update -qq > /dev/null 2>&1
            apt-get install -y -qq curl wget > /dev/null 2>&1
            ;;
        centos)
            yum install -y -q curl wget > /dev/null 2>&1
            ;;
    esac
    echo -e "${green}[✓] OK${plain}"
}

download_binary() {
    echo -e "${blue}[*] Tải XrayR binary (${arch})...${plain}"
    mkdir -p "$XRAYR_DIR"
    
    if wget -q --show-progress --timeout=60 --tries=3 --no-check-certificate \
        -O "$XRAYR_BIN" "$BINARY_URL" 2>&1; then
        
        if [[ ! -s "$XRAYR_BIN" ]]; then
            echo -e "${red}[✗] File rỗng!${plain}"
            return 1
        fi
        
        local size=$(stat -c%s "$XRAYR_BIN" 2>/dev/null || stat -f%z "$XRAYR_BIN" 2>/dev/null)
        if [[ "$size" -lt 5000000 ]]; then
            echo -e "${red}[✗] File quá nhỏ!${plain}"
            return 1
        fi
        
        chmod +x "$XRAYR_BIN"
        
        if "$XRAYR_BIN" version >/dev/null 2>&1; then
            local ver=$("$XRAYR_BIN" version 2>/dev/null | head -1)
            echo -e "${green}[✓] Tải OK: $ver${plain}"
        else
            echo -e "${green}[✓] Binary: $XRAYR_BIN${plain}"
        fi
        return 0
    else
        echo -e "${red}[✗] Tải thất bại!${plain}"
        return 1
    fi
}

download_config() {
    echo -e "${blue}[*] Tải config.yml...${plain}"
    mkdir -p /etc/XrayR

    if wget -q --timeout=30 --tries=3 --no-check-certificate \
        -O "$XRAYR_CFG" "$CONFIG_URL" 2>&1; then
        
        if [[ ! -s "$XRAYR_CFG" ]]; then
            echo -e "${red}[✗] File rỗng!${plain}"
            return 1
        fi
        
        echo -e "${green}[✓] OK${plain}"
        return 0
    else
        echo -e "${red}[✗] Thất bại!${plain}"
        return 1
    fi
}


input_num_nodes() {
    echo ""
    echo -e "${cyan}┌──────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${yellow}  Bạn muốn cài bao nhiêu node?          ${cyan}│${plain}"
    echo -e "${cyan}│${plain}  (Tối đa 5 node trên 1 VPS)            ${cyan}│${plain}"
    echo -e "${cyan}└──────────────────────────────────────────┘${plain}"
    
    while true; do
        echo -ne "${green}Số lượng node [1-5]: ${plain}"
        read -r num_nodes
        
        if [[ "$num_nodes" =~ ^[1-5]$ ]]; then
            echo -e "${green}✓ Sẽ cài $num_nodes node${plain}"
            break
        fi
        echo -e "${red}→ Nhập số từ 1 đến 5!${plain}"
    done
}

input_api_host() {
    echo ""
    echo -e "${cyan}┌──────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${yellow}  API URL của V2Board panel             ${cyan}│${plain}"
    echo -e "${cyan}│${plain}  VD: https://panel.example.com         ${cyan}│${plain}"
    echo -e "${cyan}└──────────────────────────────────────────┘${plain}"
    
    while true; do
        echo -ne "${green}API URL: ${plain}"
        read -r api_host
        api_host="${api_host%/}"
        
        [[ -z "$api_host" ]] && { echo -e "${red}→ Không rỗng!${plain}" ; continue ; }
        [[ "$api_host" =~ ^https?:// ]] && { echo -e "${green}✓ $api_host${plain}" ; break ; }
        echo -e "${red}→ Phải có http:// hoặc https://${plain}"
    done
}

input_api_key() {
    echo ""
    echo -e "${cyan}┌──────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${yellow}  API Key                               ${cyan}│${plain}"
    echo -e "${cyan}│${plain}  V2Board → Settings → API              ${cyan}│${plain}"
    echo -e "${cyan}└──────────────────────────────────────────┘${plain}"
    
    while true; do
        echo -ne "${green}API Key: ${plain}"
        read -r api_key
        [[ -z "$api_key" ]] && { echo -e "${red}→ Không rỗng!${plain}" ; continue ; }
        echo -e "${green}✓ OK${plain}"
        break
    done
}

input_node_info() {
    local idx=$1
    
    echo ""
    echo -e "${cyan}════════════════════════════════════════════════${plain}"
    echo -e "${bold}${yellow}  CẤU HÌNH NODE #$idx${plain}"
    echo -e "${cyan}════════════════════════════════════════════════${plain}"
    
    echo -ne "${green}Tên node (VD: SG-VMESS) [tùy chọn]: ${plain}"
    read -r node_name
    [[ -z "$node_name" ]] && node_name="Node-$idx"
    NODE_NAMES[$idx]="$node_name"
    
    # Node ID
    while true; do
        echo -ne "${green}Node ID (từ V2Board): ${plain}"
        read -r node_id
        [[ -z "$node_id" ]] && { echo -e "${red}→ Không rỗng!${plain}" ; continue ; }
        [[ "$node_id" =~ ^[0-9]+$ ]] && { echo -e "${green}✓ ID = $node_id${plain}" ; break ; }
        echo -e "${red}→ Phải là số!${plain}"
    done
    NODE_IDS[$idx]=$node_id
    
    echo ""
    echo -e "${cyan}Loại node:${plain}"
    echo -e "  ${cyan}1${plain} → V2ray (VMESS/VLESS)"
    echo -e "  ${cyan}2${plain} → Trojan"
    echo -e "  ${cyan}3${plain} → Shadowsocks"
    
    while true; do
        echo -ne "${green}Chọn [1/2/3]: ${plain}"
        read -r choice
        case "$choice" in
            1) NODE_TYPES[$idx]="V2ray" ; echo -e "${green}✓ V2ray${plain}" ; break ;;
            2) NODE_TYPES[$idx]="Trojan" ; echo -e "${green}✓ Trojan${plain}" ; break ;;
            3) NODE_TYPES[$idx]="Shadowsocks" ; echo -e "${green}✓ SS${plain}" ; break ;;
            *) echo -e "${red}→ Nhập 1/2/3!${plain}" ;;
        esac
    done
}

input_redis() {
    echo ""
    echo -e "${cyan}┌──────────────────────────────────────────┐${plain}"
    echo -e "${cyan}│${yellow}  Redis Device Limit (Global)           ${cyan}│${plain}"
    echo -e "${cyan}│${plain}  Áp dụng cho tất cả các node           ${cyan}│${plain}"
    echo -e "${cyan}└──────────────────────────────────────────┘${plain}"
    echo -ne "${green}Bật Redis? [y/N]: ${plain}"
    read -r enable_redis

    if [[ "$enable_redis" =~ ^[Yy]$ ]]; then
        redis_on="true"
        
        echo -ne "${green}Redis Addr [127.0.0.1:6379]: ${plain}"
        read -r redis_addr
        [[ -z "$redis_addr" ]] && redis_addr="127.0.0.1:6379"
        
        echo -ne "${green}Redis Pass: ${plain}"
        read -r redis_pass
        
        echo -ne "${green}Redis DB [0]: ${plain}"
        read -r redis_db
        [[ -z "$redis_db" ]] && redis_db="0"
        
        redis_timeout="5"
        redis_expiry="60"
        
        echo -e "${green}✓ Redis enabled${plain}"
    else
        redis_on="false"
    fi
}

review_config() {
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║${bold}${yellow}       KIỂM TRA LẠI CẤU HÌNH                 ${plain}${cyan}║${plain}"
    echo -e "${cyan}╠════════════════════════════════════════════════╣${plain}"
    echo -e "${cyan}║${plain} ${yellow}API URL :${plain} %-37s ${cyan}║${plain}" "$(echo "$api_host" | cut -c1-37)"
    echo -e "${cyan}║${plain} ${yellow}API Key :${plain} %-37s ${cyan}║${plain}" "****"
    echo -e "${cyan}║${plain} ${yellow}Số node :${plain} %-37s ${cyan}║${plain}" "$num_nodes"
    echo -e "${cyan}║${plain} ${yellow}Redis   :${plain} %-37s ${cyan}║${plain}" "$redis_on"
    echo -e "${cyan}╠════════════════════════════════════════════════╣${plain}"
    
    for ((i=1; i<=num_nodes; i++)); do
        echo -e "${cyan}║${plain} ${bold}Node #$i:${plain} %-39s ${cyan}║${plain}" "${NODE_NAMES[$i]}"
        echo -e "${cyan}║${plain}   ID: %-6s  Type: %-26s ${cyan}║${plain}" "${NODE_IDS[$i]}" "${NODE_TYPES[$i]}"
    done
    
    echo -e "${cyan}╚════════════════════════════════════════════════╝${plain}"
    echo ""
    echo -ne "${green}Xác nhận cài đặt? [y/N]: ${plain}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]]
}


patch_config_multinode() {
    echo ""
    echo -e "${blue}[*] Cấu hình multi-node...${plain}"
    
    cp "$XRAYR_CFG" "${XRAYR_CFG}.bak"
    
    sed -i '/^Nodes:/,$d' "$XRAYR_CFG"
    
    echo "Nodes:" >> "$XRAYR_CFG"
    
    for ((i=1; i<=num_nodes; i++)); do
        cat >> "$XRAYR_CFG" <<EOF
  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "$api_host"
      ApiKey: "$api_key"
      NodeID: ${NODE_IDS[$i]}
      NodeType: ${NODE_TYPES[$i]}
      Timeout: 30
      EnableVless: false
      VlessFlow: "xtls-rprx-vision"
      SpeedLimit: 0
      DeviceLimit: 0
      RuleListPath:
      DisableCustomConfig: false

    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false

      AutoSpeedLimitConfig:
        Limit: 0
        WarnTimes: 0
        LimitSpeed: 0
        LimitDuration: 0

      GlobalDeviceLimitConfig:
        Enable: $([[ "$redis_on" == "true" ]] && echo "true" || echo "false")
        RedisNetwork: tcp
        RedisAddr: $redis_addr
        RedisUsername:
        RedisPassword: $redis_pass
        RedisDB: $redis_db
        Timeout: $redis_timeout
        Expiry: $redis_expiry

      EnableFallback: false
      FallBackConfigs:
        - SNI:
          Alpn:
          Path:
          Dest: 80
          ProxyProtocolVer: 0

      CertConfig:
        CertMode: none
        CertDomain: ""
        CertFile:
        KeyFile:
        Provider: alidns
        Email:
        DNSEnv:
          ALICLOUD_ACCESS_KEY:
          ALICLOUD_SECRET_KEY:

EOF
    done
    
    echo -e "${green}[✓] Đã cấu hình $num_nodes node${plain}"
}

create_service() {
    echo -e "${blue}[*] Tạo systemd service...${plain}"
    
    cat > "$XRAYR_SVC" <<EOF
[Unit]
Description=XrayR Multi-Node Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$XRAYR_BIN --config $XRAYR_CFG
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    echo -e "${green}[✓] OK${plain}"
}

start_service() {
    echo ""
    echo -e "${blue}[*] Khởi động XrayR...${plain}"
    
    systemctl enable XrayR >/dev/null 2>&1
    systemctl start XrayR
    sleep 3

    if systemctl is-active --quiet XrayR; then
        echo -e "${green}${bold}"
        echo -e "╔════════════════════════════════════════════════╗"
        echo -e "║     ✓✓ XrayR ĐANG CHẠY ($num_nodes NODES)              ║"
        echo -e "╚════════════════════════════════════════════════╝"
        echo -e "${plain}"
        echo -e "${green}Các node sẽ tự đồng bộ với panel.${plain}"
        echo -e "${cyan}Check log: ${yellow}journalctl -u XrayR -f${plain}"
    else
        echo -e "${red}╔════════════════════════════════════════════════╗${plain}"
        echo -e "${red}║     ✗ KHỞI ĐỘNG THẤT BẠI!                     ║${plain}"
        echo -e "${red}╚════════════════════════════════════════════════╝${plain}"
        echo ""
        systemctl status XrayR --no-pager
    fi
}


do_install() {
    header
    echo -e "${bold}${cyan}══════════════ CÀI ĐẶT XrayR ══════════════${plain}"
    echo ""

    if is_installed; then
        echo -e "${yellow}⚠ XrayR đã cài. Cài lại sẽ ghi đè config.${plain}"
        echo -ne "${green}Tiếp tục? [y/N]: ${plain}"
        read -r ov
        [[ ! "$ov" =~ ^[Yy]$ ]] && return
    fi

    detect_os
    detect_arch
    echo -e "${cyan}→ OS: ${release} | Arch: ${arch}${plain}\n"

    install_deps
    download_binary || { read -p "Enter..." ; return ; }
    download_config || { read -p "Enter..." ; return ; }

    input_num_nodes
    input_api_host
    input_api_key
    
    for ((i=1; i<=num_nodes; i++)); do
        input_node_info $i
    done
    
    input_redis

    # Review và confirm
    if ! review_config; then
        echo -e "${yellow}\n→ Đã hủy${plain}"
        read -p "Enter..."
        return
    fi

    # Thực hiện cài đặt
    patch_config_multinode
    create_service
    start_service

    echo ""
    read -p "Ấn Enter..."
}

do_uninstall() {
    header
    echo -e "${bold}${red}══════════════ GỠ CÀI ĐẶT ══════════════${plain}"
    echo ""
    
    if ! is_installed; then
        echo -e "${yellow}⚠ Chưa cài.${plain}"
        read -p "Enter..."
        return
    fi

    echo -ne "${green}Xác nhận gỡ? [y/N]: ${plain}"
    read -r yn
    [[ ! "$yn" =~ ^[Yy]$ ]] && return

    systemctl stop XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -rf "$XRAYR_DIR" /etc/XrayR "$XRAYR_SVC"
    systemctl daemon-reload

    echo -e "${green}[✓] Đã gỡ${plain}"
    read -p "Enter..."
}

do_manage() {
    while true; do
        header
        echo -e "${bold}${cyan}══════════════ QUẢN LÝ ══════════════${plain}"
        echo ""
        echo -e "  ${cyan}1${plain} → Start"
        echo -e "  ${cyan}2${plain} → Stop"
        echo -e "  ${cyan}3${plain} → Restart"
        echo -e "  ${cyan}4${plain} → Status"
        echo -e "  ${cyan}5${plain} → Log (real-time)"
        echo -e "  ${cyan}6${plain} → Sửa config"
        echo -e "  ${cyan}7${plain} → Xem config hiện tại"
        echo -e "  ${cyan}0${plain} → Quay lại"
        echo ""
        echo -ne "${green}Chọn: ${plain}"
        read -r m

        case "$m" in
            1) systemctl start XrayR ; sleep 1 ;;
            2) systemctl stop XrayR ; sleep 1 ;;
            3) systemctl restart XrayR ; sleep 1 ;;
            4) systemctl status XrayR --no-pager ; read -p "Enter..." ;;
            5) echo -e "${cyan}Ctrl+C để thoát${plain}" ; journalctl -u XrayR -f ;;
            6) 
                nano "$XRAYR_CFG" 2>/dev/null || vi "$XRAYR_CFG"
                echo -ne "${green}Restart? [y/N]: ${plain}"
                read -r r
                [[ "$r" =~ ^[Yy]$ ]] && systemctl restart XrayR
                ;;
            7)
                echo ""
                echo -e "${cyan}════ Config hiện tại ════${plain}"
                grep -A 5 "NodeID:" "$XRAYR_CFG" | grep -E "NodeID:|NodeType:"
                echo ""
                read -p "Enter..."
                ;;
            0) return ;;
        esac
    done
}

main_menu() {
    while true; do
        header
        echo -e "${cyan}┌─────────────────────────────────────┐${plain}"
        echo -e "${cyan}│${bold}${green}        MENU CHÍNH                   ${plain}${cyan}│${plain}"
        echo -e "${cyan}├─────────────────────────────────────┤${plain}"
        echo -e "${cyan}│${plain}  ${cyan}1${plain} → Cài đặt (Multi-Node)       ${cyan}│${plain}"
        echo -e "${cyan}│${plain}  ${cyan}2${plain} → Quản lý                    ${cyan}│${plain}"
        echo -e "${cyan}│${plain}  ${cyan}3${plain} → Gỡ cài đặt                 ${cyan}│${plain}"
        echo -e "${cyan}│${plain}  ${cyan}0${plain} → Thoát                      ${cyan}│${plain}"
        echo -e "${cyan}└─────────────────────────────────────┘${plain}"
        echo ""
        echo -ne "${green}Chọn: ${plain}"
        read -r opt

        case "$opt" in
            1) do_install ;;
            2) 
                if ! is_installed; then
                    header
                    echo -e "${yellow}⚠ Chưa cài!${plain}"
                    read -p "Enter..."
                else
                    do_manage
                fi
                ;;
            3) do_uninstall ;;
            0) echo -e "\n${green}Tạm biệt!${plain}\n" ; exit 0 ;;
        esac
    done
}

check_root
main_menu
