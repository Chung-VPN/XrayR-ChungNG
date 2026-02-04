#!/bin/bash
#============================================================
#   XrayR Auto-Install — V2Board (1-2 Nodes)
#   Usage: bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install.sh)
#============================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[0;36m'
blue='\033[0;34m'
bold='\033[1m'
plain='\033[0m'

XRAYR_DIR="/usr/local/XrayR"
XRAYR_BIN="$XRAYR_DIR/XrayR"
XRAYR_CFG="/etc/XrayR/config.yml"
XRAYR_SVC="/etc/systemd/system/XrayR.service"

CONFIG_URL="https://cdn.jsdelivr.net/gh/Chung-VPN/XrayR-ChungNG@main/config.yml"

#============================================================
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${red}Cần chạy bằng root!${plain}" && exit 1
}

detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi "debian|ubuntu" /etc/issue 2>/dev/null; then
        release="debian"
    elif grep -Eqi "debian|ubuntu" /proc/version 2>/dev/null; then
        release="debian"
    else
        echo -e "${red}Không nhận diện được OS!${plain}"
        exit 1
    fi
}

detect_arch() {
    local raw_arch=$(uname -m)
    case "$raw_arch" in
        x86_64|amd64)   arch="64" ;;
        aarch64|arm64)  arch="arm64-v8a" ;;
        armv7|armv7l)   arch="arm32-v7a" ;;
        armv6l)         arch="arm32-v6" ;;
        *)
            echo -e "${red}Kiến trúc không hỗ trợ: $raw_arch${plain}"
            exit 1
            ;;
    esac
}

is_installed() { [[ -f "$XRAYR_BIN" ]]; }

header() {
    clear
    echo -e "${cyan}============================================================${plain}"
    echo -e "${bold}${green}   XrayR Multi-Node Installer — V2Board${plain}"
    echo -e "${cyan}============================================================${plain}"
    if ! is_installed; then
        echo -e "  Trạng thái: ${red}● Chưa cài${plain}"
    elif systemctl is-active --quiet XrayR 2>/dev/null; then
        echo -e "  Trạng thái: ${green}● Đang chạy${plain}"
    else
        echo -e "  Trạng thái: ${yellow}● Đã cài${plain}"
    fi
    echo ""
}

wait_key() {
    read -rp "$(echo -e "${cyan}Ấn Enter...${plain}")" _
}

#============================================================
install_deps() {
    echo -e "${blue}[*] Cài dependencies...${plain}"
    if [[ "$release" == "centos" ]]; then
        yum install -y -q curl wget unzip 2>/dev/null
    else
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq curl wget unzip 2>/dev/null
    fi
    echo -e "${green}[✓] Xong${plain}"
}

disable_fw() {
    echo -e "${blue}[*] Tắt firewall...${plain}"
    if command -v ufw &>/dev/null; then
        ufw disable &>/dev/null
    elif command -v firewall-cmd &>/dev/null; then
        systemctl stop firewalld &>/dev/null
        systemctl disable firewalld &>/dev/null
    fi
    echo -e "${green}[✓] OK${plain}"
}

#============================================================
install_binary() {
    echo -e "${blue}[*] Tải XrayR...${plain}"
    mkdir -p "$XRAYR_DIR"
    
    local url="https://github.com/XrayR-project/XrayR/releases/latest/download/XrayR-linux-${arch}.zip"
    local zip_path="$XRAYR_DIR/XrayR.zip"
    
    # Thử tải 3 lần
    local success=false
    for i in 1 2 3; do
        echo -e "${blue}    Lần thử $i/3...${plain}"
        if wget -q --show-progress --timeout=30 -O "$zip_path" "$url" 2>&1; then
            if [[ -s "$zip_path" ]] && file "$zip_path" 2>/dev/null | grep -qi "zip"; then
                success=true
                break
            fi
        fi
        rm -f "$zip_path"
        sleep 2
    done
    
    if [[ "$success" != true ]]; then
        echo -e "${red}[✗] Tải thất bại sau 3 lần thử${plain}"
        return 1
    fi
    
    echo -e "${blue}[*] Giải nén...${plain}"
    cd "$XRAYR_DIR" || return 1
    unzip -oq "$zip_path" 2>/dev/null || {
        echo -e "${red}[✗] Giải nén thất bại${plain}"
        return 1
    }
    
    rm -f "$zip_path"
    chmod +x "$XRAYR_BIN"
    echo -e "${green}[✓] Cài binary thành công${plain}"
}

download_config() {
    echo -e "${blue}[*] Tải config...${plain}"
    mkdir -p /etc/XrayR
    
    if ! curl -fsSL -o "$XRAYR_CFG" "$CONFIG_URL" 2>/dev/null; then
        echo -e "${red}[✗] Tải config thất bại${plain}"
        return 1
    fi
    echo -e "${green}[✓] Config đã tải${plain}"
}

#============================================================
# HÀM NHẬP THÔNG TIN - ĐƠN GIẢN HÓA
#============================================================
input_all_info() {
    # Hỏi số node
    echo -e "${cyan}╔════════════════════════════════╗${plain}"
    echo -e "${cyan}║  Cài bao nhiêu node?           ║${plain}"
    echo -e "${cyan}╚════════════════════════════════╝${plain}"
    echo ""
    while true; do
        echo -ne "${green}Nhập 1 hoặc 2: ${plain}"
        read -r num_nodes
        [[ "$num_nodes" == "1" ]] || [[ "$num_nodes" == "2" ]] && break
        echo -e "${red}Chỉ nhập 1 hoặc 2!${plain}"
    done
    
    # Panel URL (chung cho tất cả node)
    echo ""
    echo -e "${cyan}╔════════════════════════════════╗${plain}"
    echo -e "${cyan}║  Địa chỉ V2Board Panel         ║${plain}"
    echo -e "${cyan}╚════════════════════════════════╝${plain}"
    while true; do
        echo -ne "${green}VD https://panel.com: ${plain}"
        read -r panel_url
        panel_url="${panel_url%/}"
        [[ "$panel_url" =~ ^https?:// ]] && break
        echo -e "${red}Phải có http:// hoặc https://${plain}"
    done
    
    # API Key (chung)
    echo ""
    echo -e "${cyan}╔════════════════════════════════╗${plain}"
    echo -e "${cyan}║  API Key (V2Board Settings)    ║${plain}"
    echo -e "${cyan}╚════════════════════════════════╝${plain}"
    while true; do
        echo -ne "${green}API Key: ${plain}"
        read -r api_key
        [[ -n "$api_key" ]] && break
        echo -e "${red}Không được rỗng!${plain}"
    done
    
    # Node 1 ID
    echo ""
    echo -e "${cyan}╔════════════════════════════════╗${plain}"
    echo -e "${cyan}║  NODE 1 - Node ID              ║${plain}"
    echo -e "${cyan}╚════════════════════════════════╝${plain}"
    while true; do
        echo -ne "${green}Node 1 ID: ${plain}"
        read -r node1_id
        [[ "$node1_id" =~ ^[0-9]+$ ]] && break
        echo -e "${red}Chỉ nhập số!${plain}"
    done
    
    # Node 1 Type
    echo -e "${cyan}Loại node: 1) V2ray  2) Trojan  3) Shadowsocks${plain}"
    while true; do
        echo -ne "${green}Chọn [1-3]: ${plain}"
        read -r n1_type
        case "$n1_type" in
            1) node1_type="V2ray" ; break ;;
            2) node1_type="Trojan" ; break ;;
            3) node1_type="Shadowsocks" ; break ;;
            *) echo -e "${red}Chỉ nhập 1-3!${plain}" ;;
        esac
    done
    
    # Nếu 2 node
    if [[ "$num_nodes" == "2" ]]; then
        echo ""
        echo -e "${cyan}╔════════════════════════════════╗${plain}"
        echo -e "${cyan}║  NODE 2 - Node ID              ║${plain}"
        echo -e "${cyan}╚════════════════════════════════╝${plain}"
        while true; do
            echo -ne "${green}Node 2 ID: ${plain}"
            read -r node2_id
            [[ "$node2_id" =~ ^[0-9]+$ ]] && break
            echo -e "${red}Chỉ nhập số!${plain}"
        done
        
        echo -e "${cyan}Loại node: 1) V2ray  2) Trojan  3) Shadowsocks${plain}"
        while true; do
            echo -ne "${green}Chọn [1-3]: ${plain}"
            read -r n2_type
            case "$n2_type" in
                1) node2_type="V2ray" ; break ;;
                2) node2_type="Trojan" ; break ;;
                3) node2_type="Shadowsocks" ; break ;;
                *) echo -e "${red}Chỉ nhập 1-3!${plain}" ;;
            esac
        done
    fi
    
    # Redis
    echo ""
    echo -e "${cyan}╔════════════════════════════════╗${plain}"
    echo -e "${cyan}║  Bật Redis? (y/N)              ║${plain}"
    echo -e "${cyan}╚════════════════════════════════╝${plain}"
    echo -ne "${green}[y/N]: ${plain}"
    read -r redis_choice
    
    if [[ "$redis_choice" =~ ^[Yy] ]]; then
        redis_enabled="true"
        echo -ne "${green}Redis Addr (127.0.0.1:6379): ${plain}"
        read -r redis_addr
        [[ -z "$redis_addr" ]] && redis_addr="127.0.0.1:6379"
        
        echo -ne "${green}Redis Pass (Enter = rỗng): ${plain}"
        read -r redis_pass
    else
        redis_enabled="false"
    fi
}

#============================================================
review() {
    echo ""
    echo -e "${cyan}╔════════════════════════════════╗${plain}"
    echo -e "${cyan}║  XEM LẠI CẤU HÌNH              ║${plain}"
    echo -e "${cyan}╚════════════════════════════════╝${plain}"
    echo ""
    echo -e "${green}Panel:${plain} $panel_url"
    echo -e "${green}API Key:${plain} ${api_key:0:15}..."
    echo -e "${green}Node 1:${plain} ID=$node1_id, Type=$node1_type"
    
    if [[ "$num_nodes" == "2" ]]; then
        echo -e "${green}Node 2:${plain} ID=$node2_id, Type=$node2_type"
    fi
    
    echo -e "${green}Redis:${plain} $redis_enabled"
    
    echo ""
    echo -ne "${green}Xác nhận? [y/N]: ${plain}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy] ]]
}

#============================================================
write_config() {
    echo -e "${blue}[*] Ghi config...${plain}"
    
    # Backup
    cp "$XRAYR_CFG" "${XRAYR_CFG}.bak"
    
    # Thay thế Node 1
    sed -i "s|PANEL_URL_1|$panel_url|g" "$XRAYR_CFG"
    sed -i "s|API_KEY_1|$api_key|g" "$XRAYR_CFG"
    sed -i "s|NodeID: 1|NodeID: $node1_id|" "$XRAYR_CFG"
    sed -i "s|NodeType: V2ray|NodeType: $node1_type|" "$XRAYR_CFG"
    
    # Nếu 2 node - thêm node 2 vào cuối file
    if [[ "$num_nodes" == "2" ]]; then
        cat >> "$XRAYR_CFG" <<EOF

  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "$panel_url"
      ApiKey: "$api_key"
      NodeID: $node2_id
      NodeType: $node2_type
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
        Enable: false
        RedisNetwork: tcp
        RedisAddr: 127.0.0.1:6379
        RedisUsername:
        RedisPassword:
        RedisDB: 1
        Timeout: 5
        Expiry: 60
      EnableFallback: false
      FallBackConfigs:
        - SNI:
          Alpn:
          Path:
          Dest: 80
          ProxyProtocolVer: 0
      DisableLocalREALITYConfig: false
      EnableREALITY: false
      REALITYConfigs:
        Show: true
        Dest: www.amazon.com:443
        ProxyProtocolVer: 0
        ServerNames:
          - www.amazon.com
        PrivateKey: YOUR_PRIVATE_KEY
        MinClientVer:
        MaxClientVer:
        MaxTimeDiff: 0
        ShortIds:
          - ""
          - 0123456789abcdef
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
    fi
    
    # Redis
    if [[ "$redis_enabled" == "true" ]]; then
        sed -i "s|Enable: false|Enable: true|g" "$XRAYR_CFG"
        sed -i "s|RedisAddr: 127.0.0.1:6379|RedisAddr: $redis_addr|g" "$XRAYR_CFG"
        if [[ -n "$redis_pass" ]]; then
            sed -i "s|RedisPassword:|RedisPassword: $redis_pass|g" "$XRAYR_CFG"
        fi
    fi
    
    echo -e "${green}[✓] Config đã ghi${plain}"
}

create_service() {
    echo -e "${blue}[*] Tạo service...${plain}"
    cat > "$XRAYR_SVC" <<EOF
[Unit]
Description=XrayR Multi-Node
After=network.target

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
    echo -e "${green}[✓] Service OK${plain}"
}

#============================================================
do_install() {
    header
    echo -e "${bold}${cyan}── CÀI ĐẶT ──${plain}"
    echo ""
    
    if is_installed; then
        echo -e "${yellow}Đã cài rồi. Cài lại?${plain}"
        echo -ne "${green}[y/N]: ${plain}"
        read -r ov
        [[ ! "$ov" =~ ^[Yy] ]] && return
    fi
    
    detect_os
    detect_arch
    install_deps
    disable_fw
    install_binary || { wait_key ; return ; }
    download_config || { wait_key ; return ; }
    
    input_all_info
    review || { echo -e "${yellow}Hủy${plain}" ; wait_key ; return ; }
    
    write_config
    create_service
    
    echo ""
    echo -e "${blue}[*] Khởi động...${plain}"
    systemctl enable XrayR &>/dev/null
    systemctl start XrayR
    sleep 2
    
    if systemctl is-active --quiet XrayR; then
        echo -e "${green}${bold}[✓] Chạy thành công!${plain}"
    else
        echo -e "${red}[✗] Lỗi. Xem log: journalctl -u XrayR -n 50${plain}"
    fi
    
    wait_key
}

do_uninstall() {
    header
    echo -e "${bold}${red}── GỠ CÀI ĐẶT ──${plain}"
    echo ""
    
    if ! is_installed; then
        echo -e "${yellow}Chưa cài đặt${plain}"
        wait_key
        return
    fi
    
    echo -ne "${green}Xác nhận? [y/N]: ${plain}"
    read -r yn
    [[ ! "$yn" =~ ^[Yy] ]] && return
    
    systemctl stop XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -rf "$XRAYR_DIR" /etc/XrayR "$XRAYR_SVC"
    systemctl daemon-reload
    
    echo -e "${green}[✓] Đã gỡ${plain}"
    wait_key
}

do_manage() {
    while true; do
        header
        echo -e "${bold}${cyan}── QUẢN LÝ ──${plain}"
        echo ""
        echo -e "  ${cyan}1${plain}  Start      ${cyan}4${plain}  Status"
        echo -e "  ${cyan}2${plain}  Stop       ${cyan}5${plain}  Logs"
        echo -e "  ${cyan}3${plain}  Restart    ${cyan}6${plain}  Edit config"
        echo -e "  ${cyan}0${plain}  Quay về"
        echo ""
        echo -ne "${green}Chọn: ${plain}"
        read -r m
        
        case "$m" in
            1) systemctl start XrayR && echo -e "${green}OK${plain}" || echo -e "${red}Lỗi${plain}" ; wait_key ;;
            2) systemctl stop XrayR && echo -e "${green}OK${plain}" ; wait_key ;;
            3) systemctl restart XrayR && echo -e "${green}OK${plain}" || echo -e "${red}Lỗi${plain}" ; wait_key ;;
            4) systemctl status XrayR --no-pager ; wait_key ;;
            5) journalctl -u XrayR -n 100 --no-pager ; wait_key ;;
            6)
                nano "$XRAYR_CFG" || vi "$XRAYR_CFG"
                echo -ne "${green}Restart? [y/N]: ${plain}"
                read -r rr
                [[ "$rr" =~ ^[Yy] ]] && systemctl restart XrayR
                wait_key
                ;;
            0) return ;;
            *) echo -e "${red}0-6 thôi!${plain}" ; wait_key ;;
        esac
    done
}

main() {
    check_root
    while true; do
        header
        echo -e "${cyan}  ┌─────────────────────────┐${plain}"
        echo -e "${cyan}  │  1  Cài đặt             │${plain}"
        echo -e "${cyan}  │  2  Quản lý             │${plain}"
        echo -e "${cyan}  │  3  Gỡ cài đặt          │${plain}"
        echo -e "${cyan}  │  0  Thoát               │${plain}"
        echo -e "${cyan}  └─────────────────────────┘${plain}"
        echo ""
        echo -ne "${green}Chọn: ${plain}"
        read -r opt
        
        case "$opt" in
            1) do_install ;;
            2) do_manage ;;
            3) do_uninstall ;;
            0) echo -e "${green}Bye!${plain}" ; exit 0 ;;
            *) ;;
        esac
    done
}

main
