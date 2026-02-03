#!/bin/bash
#============================================================
#   XrayR Auto Install — V2Board (Fixed Version)

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[0;36m'
blue='\033[0;34m'
bold='\033[1m'
plain='\033[0m'

# ── PATHS ───────────────────────────────────────────────
XRAYR_DIR="/usr/local/XrayR"
XRAYR_BIN="$XRAYR_DIR/XrayR"
XRAYR_CFG="/etc/XrayR/config.yml"
XRAYR_SVC="/etc/systemd/system/XrayR.service"
XRAYR_RELEASE_SH="https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/XrayR.sh"

# Config download URL - sử dụng raw.githubusercontent.com thay vì jsDelivr
CONFIG_DOWNLOAD_URL="https://raw.githubusercontent.com/Chung-VPN/XrayR-ChungNG/main/config.yml"

# Alternative mirrors for GitHub (used if main download fails)
GITHUB_MIRRORS=(
    "https://github.com"
    "https://ghproxy.com/https://github.com"
    "https://mirror.ghproxy.com/https://github.com"
)

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${red}Cần chạy bằng root!  →  sudo bash install.sh${plain}" && exit 1
}

detect_os() {
    if [[ -f /etc/redhat-release ]]; then          release="centos"
    elif grep -Eqi "debian" /etc/issue 2>/dev/null; then  release="debian"
    elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then  release="ubuntu"
    elif grep -Eqi "centos|red hat" /proc/version 2>/dev/null; then release="centos"
    elif grep -Eqi "debian" /proc/version 2>/dev/null; then  release="debian"
    elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then  release="ubuntu"
    else echo -e "${red}Không phát hiện được OS!${plain}" ; exit 1 ; fi
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  arch="amd64"  ;;
        aarch64|arm64) arch="arm64"  ;;
        armv7l)        arch="armv7"  ;;
        *)  echo -e "${red}Arch không hỗ trợ: $(uname -m)${plain}" ; exit 1 ;;
    esac
}

is_installed() { [[ -f "$XRAYR_BIN" ]]; }

svc_badge() {
    if ! is_installed; then
        echo -e "  Trạng thái: ${red}● Chưa cài đặt${plain}"
    elif systemctl is-active --quiet XrayR 2>/dev/null; then
        echo -e "  Trạng thái: ${green}● Đang chạy${plain}"
    else
        echo -e "  Trạng thái: ${yellow}● Cài rồi, chưa chạy${plain}"
    fi
}

header() {
    clear
    echo -e "${cyan}============================================================${plain}"
    echo -e "${bold}${green}       XrayR Tự-Cài — V2Board${plain}"
    echo -e "${cyan}============================================================${plain}"
    svc_badge
    echo ""
}

install_deps() {
    echo -e "${blue}[*] Cài dependencies...${plain}"
    case "$release" in
        debian|ubuntu)
            apt-get update  -qq            > /dev/null 2>&1
            apt-get install -y -qq curl wget unzip tar > /dev/null 2>&1 ;;
        centos)
            yum install -y -q curl wget unzip tar > /dev/null 2>&1 ;;
    esac
    echo -e "${green}[✓] OK${plain}"
}

# Hàm mới: lấy version với fallback
get_latest_version() {
    echo -e "${blue}[*] Lấy phiên bản mới nhất...${plain}"
    
    # Thử API chính
    last_version=$(curl -sSL --connect-timeout 10 --max-time 20 \
        "https://api.github.com/repos/XrayR-project/XrayR/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null)
    
    # Nếu fail, thử từ releases page
    if [[ -z "$last_version" ]]; then
        echo -e "${yellow}[!] API GitHub chậm, thử cách khác...${plain}"
        last_version=$(curl -sSL --connect-timeout 10 --max-time 20 \
            "https://github.com/XrayR-project/XrayR/releases/latest" \
            | grep -oP 'XrayR-project/XrayR/releases/tag/\K[^"]+' | head -1 2>/dev/null)
    fi
    
    # Nếu vẫn fail, dùng version cố định
    if [[ -z "$last_version" ]]; then
        echo -e "${yellow}[!] Không lấy được version mới, dùng v0.9.4${plain}"
        last_version="v0.9.4"
    fi
    
    echo -e "${green}[✓] Version: $last_version  |  Arch: $arch${plain}"
}

# Hàm mới: download với retry và mirrors
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retry=3
    local retry=0
    
    while [ $retry -lt $max_retry ]; do
        echo -e "${blue}[*] Download (thử $((retry+1))/$max_retry)...${plain}"
        
        if wget -q --show-progress --timeout=30 --tries=2 --no-check-certificate -O "$output" "$url"; then
            if [[ -s "$output" ]]; then
                echo -e "${green}[✓] Download thành công${plain}"
                return 0
            fi
        fi
        
        retry=$((retry+1))
        [[ $retry -lt $max_retry ]] && echo -e "${yellow}[!] Thử lại sau 2s...${plain}" && sleep 2
    done
    
    echo -e "${red}[✗] Download thất bại sau $max_retry lần thử${plain}"
    return 1
}

install_binary() {
    get_latest_version
    
    mkdir -p "$XRAYR_DIR"
    local filename="XrayR-linux-${arch}.zip"
    local download_success=false
    
    # Thử download từ các mirrors
    for mirror in "${GITHUB_MIRRORS[@]}"; do
        local url="${mirror}/XrayR-project/XrayR/releases/download/${last_version}/${filename}"
        echo -e "${cyan}[*] Mirror: ${mirror}${plain}"
        
        if download_with_retry "$url" "$XRAYR_DIR/XrayR-linux.zip"; then
            download_success=true
            break
        fi
        
        echo -e "${yellow}[!] Mirror này fail, thử mirror khác...${plain}"
    done
    
    if ! $download_success; then
        echo -e "${red}╔════════════════════════════════════════════════════════╗${plain}"
        echo -e "${red}║  [✗] TẤT CẢ MIRRORS ĐỀU FAIL                          ║${plain}"
        echo -e "${red}╠════════════════════════════════════════════════════════╣${plain}"
        echo -e "${red}║  Nguyên nhân có thể:                                   ║${plain}"
        echo -e "${red}║  • GitHub bị chặn từ VPS                               ║${plain}"
        echo -e "${red}║  • Firewall/security group chặn outbound               ║${plain}"
        echo -e "${red}║  • DNS resolution bị lỗi                               ║${plain}"
        echo -e "${red}║                                                        ║${plain}"
        echo -e "${red}║  Giải pháp:                                            ║${plain}"
        echo -e "${red}║  1. Kiểm tra: ping github.com                          ║${plain}"
        echo -e "${red}║  2. Kiểm tra firewall VPS                              ║${plain}"
        echo -e "${red}║  3. Download thủ công:                                 ║${plain}"
        echo -e "${yellow}║     wget https://github.com/XrayR-project/XrayR/\\     ║${plain}"
        echo -e "${yellow}║     releases/download/${last_version}/${filename}     ║${plain}"
        echo -e "${red}╚════════════════════════════════════════════════════════╝${plain}"
        return 1
    fi
    
    cd "$XRAYR_DIR"
    echo -e "${blue}[*] Giải nén...${plain}"
    if ! unzip -o XrayR-linux.zip > /dev/null 2>&1; then
        echo -e "${red}[✗] Giải nén thất bại! File có thể bị corrupt.${plain}"
        return 1
    fi
    
    rm -f XrayR-linux.zip
    chmod +x "$XRAYR_BIN"
    
    # Verify binary
    if [[ ! -x "$XRAYR_BIN" ]]; then
        echo -e "${red}[✗] Binary không thể chạy được!${plain}"
        return 1
    fi
    
    echo -e "${green}[✓] Binary: $XRAYR_BIN${plain}"
}

install_mgmt_cmd() {
    echo -e "${blue}[*] Cài lệnh quản lý (XrayR start/stop/restart/log)...${plain}"
    
    if ! curl -o /usr/bin/XrayR -Ls "$XRAYR_RELEASE_SH"; then
        echo -e "${yellow}[!] Không tải được script quản lý, bỏ qua...${plain}"
        return 0
    fi
    
    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
    echo -e "${green}[✓] Xong${plain}"
}

download_config() {
    echo -e "${blue}[*] Download config.yml...${plain}"
    mkdir -p /etc/XrayR
    
    # Thử download config
    if ! wget -q --timeout=15 --tries=3 --no-check-certificate -O "$XRAYR_CFG" "$CONFIG_DOWNLOAD_URL"; then
        echo -e "${yellow}[!] Download config.yml thất bại, tạo từ template...${plain}"
        
        # Tạo config mặc định từ template trong script
        cat > "$XRAYR_CFG" << 'EOF'
Log:
  Level: warning
  AccessPath:
  ErrorPath:

DnsConfigPath:
RouteConfigPath:
InboundConfigPath:
OutboundConfigPath:

ConnectionConfig:
  Handshake: 4
  ConnIdle: 30
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 64

Nodes:
  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "YOUR_PANEL_URL"
      ApiKey: "YOUR_API_KEY"
      NodeID: 1
      NodeType: V2ray
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
        RedisDB: 0
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
    
    if [[ ! -s "$XRAYR_CFG" ]]; then
        echo -e "${red}[✗] Tạo config.yml thất bại!${plain}"
        return 1
    fi
    echo -e "${green}[✓] config.yml OK${plain}"
}

input_api_host() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập API URL của V2Board panel${plain}"
    echo -e "${cyan}   VD: https://panel.example.com${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   API URL: ${plain}"
        read -r api_host

        api_host="${api_host%/}"
        [[ -z "$api_host" ]]              && { echo -e "${red}    [!] Không được rỗng.${plain}" ; continue ; }
        [[ "$api_host" =~ ^https?:// ]]   && { echo -e "${green}    [✓] $api_host${plain}" ; break ; }
        echo -e "${red}    [!] Phải bắt đầu bằng http:// hoặc https://${plain}"
    done
}

input_api_key() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập API Key${plain}"
    echo -e "${cyan}   (V2Board Admin → Settings → API)${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   API Key: ${plain}"
        read -r api_key
        [[ -z "$api_key" ]] && { echo -e "${red}    [!] Không được rỗng.${plain}" ; continue ; }
        echo -e "${green}    [✓] OK${plain}"
        break
    done
}

input_node_id() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập Node ID${plain}"
    echo -e "${cyan}   (V2Board Admin → Nodes → chọn node → ID)${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   Node ID: ${plain}"
        read -r node_id
        [[ -z "$node_id" ]]          && { echo -e "${red}    [!] Không được rỗng.${plain}" ; continue ; }
        [[ "$node_id" =~ ^[0-9]+$ ]] && { echo -e "${green}    [✓] Node ID = $node_id${plain}" ; break ; }
        echo -e "${red}    [!] Phải là số.${plain}"
    done
}

input_node_type() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Chọn giao thức (NodeType)${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "    ${cyan}1${plain}  V2ray       ← chọn này nếu node là VMESS hoặc VLESS"
    echo -e "    ${cyan}2${plain}  Trojan"
    echo -e "    ${cyan}3${plain}  Shadowsocks"
    echo ""
    echo -e "  ${blue}💡 VMESS / VLESS đều chọn \"V2ray\".${plain}"
    echo -e "  ${blue}   Nếu node là VLESS → sau cài đổi EnableVless thành true trong config.yml.${plain}"
    echo ""
    while true; do
        echo -ne "${green}   Chọn [1/2/3]: ${plain}"
        read -r ch
        case "$ch" in
            1) node_type="V2ray"       ; echo -e "${green}    [✓] V2ray${plain}"       ; break ;;
            2) node_type="Trojan"      ; echo -e "${green}    [✓] Trojan${plain}"      ; break ;;
            3) node_type="Shadowsocks" ; echo -e "${green}    [✓] Shadowsocks${plain}" ; break ;;
            *) echo -e "${red}    [!] Nhập 1, 2 hoặc 3.${plain}" ;;
        esac
    done
}

input_redis() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   GlobalDeviceLimitConfig (Redis)${plain}"
    echo -e "${cyan}   Giới hạn số thiết bị đăng nhập cùng lúc${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -ne "${green}   Enable? [y/N]: ${plain}"
    read -r re

    if [[ "$re" =~ ^[Yy] ]]; then
        redis_on="true"
        echo ""

        # Address
        while true; do
            echo -ne "${green}   Redis Address [127.0.0.1:6379]: ${plain}"
            read -r redis_addr
            [[ -z "$redis_addr" ]] && redis_addr="127.0.0.1:6379"
            [[ "$redis_addr" =~ : ]] && { echo -e "${green}    [✓] $redis_addr${plain}" ; break ; }
            echo -e "${red}    [!] Format: IP:PORT${plain}"
        done

        # Password
        echo -ne "${green}   Redis Password (để trống nếu không có): ${plain}"
        read -r redis_pass

        # DB
        while true; do
            echo -ne "${green}   Redis DB [0]: ${plain}"
            read -r redis_db
            [[ -z "$redis_db" ]] && redis_db="0"
            [[ "$redis_db" =~ ^[0-9]+$ ]] && { echo -e "${green}    [✓] DB $redis_db${plain}" ; break ; }
            echo -e "${red}    [!] Phải là số.${plain}"
        done

        # Timeout
        echo -ne "${green}   Redis Timeout (giây) [5]: ${plain}"
        read -r redis_timeout
        [[ -z "$redis_timeout" ]] && redis_timeout="5"

        # Expiry
        echo -ne "${green}   Redis Expiry (giây) [60]: ${plain}"
        read -r redis_expiry
        [[ -z "$redis_expiry" ]] && redis_expiry="60"
    else
        redis_on="false"
    fi
}

review() {
    echo ""
    echo -e "${cyan}============================================================${plain}"
    echo -e "${bold}${yellow}   KIỂM TRA LẠI CẤU HÌNH${plain}"
    echo -e "${cyan}============================================================${plain}"
    echo -e "   ${yellow}API URL    :${plain} $api_host"
    echo -e "   ${yellow}API Key    :${plain} $(echo "$api_key" | sed 's/.\{4\}/****/')"
    echo -e "   ${yellow}Node ID    :${plain} $node_id"
    echo -e "   ${yellow}NodeType   :${plain} $node_type"
    [[ "$node_type" == "V2ray" ]] && echo -e "   ${blue}→ Nếu VLESS nhớ đổi EnableVless: true sau cài${plain}"
    echo -e "   ${yellow}Redis      :${plain} $redis_on"
    if [[ "$redis_on" == "true" ]]; then
        echo -e "     ${yellow}Addr     :${plain} $redis_addr"
        echo -e "     ${yellow}DB       :${plain} $redis_db"
        echo -e "     ${yellow}Timeout  :${plain} ${redis_timeout}s"
        echo -e "     ${yellow}Expiry   :${plain} ${redis_expiry}s"
    fi
    echo -e "${cyan}============================================================${plain}"
    echo ""
    echo -ne "${green}   Tiếp tục? [y/N]: ${plain}"
    read -r c
    [[ "$c" =~ ^[Yy] ]]
}

patch_config() {
    echo ""
    echo -e "${blue}[*] Patch config.yml...${plain}"

    sed -i -E 's|^( +)ApiHost:.*$|      ApiHost: "'"$api_host"'"|' "$XRAYR_CFG"
    sed -i -E 's|^( +)ApiKey:.*$|      ApiKey: "'"$api_key"'"|'   "$XRAYR_CFG"

    sed -i -E 's/^( +)NodeID:.*$/      NodeID: '"$node_id"'/'       "$XRAYR_CFG"
    sed -i -E 's/^( +)NodeType:.*$/      NodeType: '"$node_type"'/' "$XRAYR_CFG"

    if [[ "$redis_on" == "true" ]]; then
     
        sed -i -E '/GlobalDeviceLimitConfig/{n; s/^( +)Enable:.*$/        Enable: true/}' "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisAddr:.*$/        RedisAddr: '"$redis_addr"'/'         "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisPassword:.*$/        RedisPassword: '"$redis_pass"'/' "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisDB:.*$/        RedisDB: '"$redis_db"'/'             "$XRAYR_CFG"
      
        sed -i -E '/GlobalDeviceLimitConfig/,/^[^ ]/{
            s/^( +)Timeout:.*$/        Timeout: '"$redis_timeout"'/
            s/^( +)Expiry:.*$/        Expiry: '"$redis_expiry"'/
        }' "$XRAYR_CFG"
    fi

    echo -e "${green}[✓] Patch xong${plain}"
}

create_service() {
    echo -e "${blue}[*] Tạo systemd service...${plain}"
    cat > "$XRAYR_SVC" <<EOF
[Unit]
Description=XrayR V2Board Node
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
    echo -e "${green}[✓] Service OK${plain}"
}

disable_fw() {
    echo -e "${blue}[*] Tắt firewall...${plain}"
    if command -v ufw &>/dev/null; then
        ufw disable > /dev/null 2>&1 ; echo -e "${green}[✓] UFW off${plain}"
    elif command -v firewall-cmd &>/dev/null; then
        systemctl stop firewalld > /dev/null 2>&1
        systemctl disable firewalld > /dev/null 2>&1
        echo -e "${green}[✓] firewalld off${plain}"
    else
        echo -e "${yellow}[—] Không có UFW / firewalld${plain}"
    fi
}

do_install() {
    header
    echo -e "${bold}${cyan}── CÀI ĐẶT ──${plain}"
    echo ""

    if is_installed; then
        echo -e "${yellow}[!] Đã cài rồi. Cài lại sẽ overwrite.${plain}"
        echo -ne "${green} Tiếp tục? [y/N]: ${plain}"
        read -r ov ; [[ "$ov" =~ ^[Yy] ]] || return
        echo ""
    fi

    detect_os
    detect_arch
    install_deps
    install_binary       || { read -rp "$(echo -e "${cyan}Enter để tiếp tục...${plain}")" _ ; return ; }
    install_mgmt_cmd
    download_config      || { read -rp "$(echo -e "${cyan}Enter để tiếp tục...${plain}")" _ ; return ; }

    input_api_host
    input_api_key
    input_node_id
    input_node_type
    input_redis

    review || { echo -e "${yellow}\n[—] Hủy.${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ; return ; }

    patch_config
    create_service
    disable_fw

    # START
    echo ""
    echo -e "${blue}[*] Start XrayR...${plain}"
    systemctl enable XrayR > /dev/null 2>&1
    systemctl start  XrayR
    sleep 2

    if systemctl is-active --quiet XrayR; then
        echo -e "${green}${bold}[✓✓] XrayR đang chạy!${plain}"
        echo -e "${green}     Node sẽ tự sync với V2Board panel trong vài giây.${plain}"
    else
        echo -e "${red}[✗] Chưa chạy. Kiểm tra:${plain}"
        echo -e "${yellow}    XrayR log   hoặc   systemctl status XrayR${plain}"
        systemctl status XrayR --no-pager 2>/dev/null || true
    fi

    read -rp "$(echo -e "${cyan}\nẤn Enter...${plain}")" _
}

do_uninstall() {
    header
    echo -e "${bold}${red}── GỠ CÀI ĐẶT ──${plain}"
    echo ""
    if ! is_installed; then
        echo -e "${yellow}[!] Chưa cài.${plain}"
        read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ; return
    fi

    echo -e "${red}  Sẽ xóa:  $XRAYR_DIR  │  /etc/XrayR  │  service  │  /usr/bin/XrayR${plain}"
    echo ""
    echo -ne "${green} Xác nhận [y/N]: ${plain}"
    read -r yn ; [[ "$yn" =~ ^[Yy] ]] || { echo -e "${yellow}[—] Hủy${plain}" ; return ; }

    systemctl stop    XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -rf  "$XRAYR_DIR"  /etc/XrayR  "$XRAYR_SVC"
    rm -f   /usr/bin/XrayR  /usr/bin/xrayr
    systemctl daemon-reload 2>/dev/null

    echo -e "${green}[✓] Gỡ hoàn toàn.${plain}"
    read -rp "$(echo -e "${cyan}Enter...${plain}")" _
}

do_manage() {
    while true; do
        header
        echo -e "${bold}${cyan}── QUẢN LÝ SERVICE ──${plain}"
        echo ""
        echo -e "  ${cyan}1${plain}  Start       ${cyan}4${plain}  Status"
        echo -e "  ${cyan}2${plain}  Stop        ${cyan}5${plain}  Xem Log"
        echo -e "  ${cyan}3${plain}  Restart     ${cyan}6${plain}  Sửa config.yml"
        echo -e "  ${cyan}0${plain}  Quay về"
        echo ""
        echo -ne "${green} Chọn: ${plain}"
        read -r m

        case "$m" in
            1) systemctl start   XrayR   && echo -e "${green}[✓] Started${plain}"   || echo -e "${red}[✗] Fail${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ;;
            2) systemctl stop    XrayR   && echo -e "${green}[✓] Stopped${plain}"   || echo -e "${red}[✗] Fail${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ;;
            3) systemctl restart XrayR   && echo -e "${green}[✓] Restarted${plain}" || echo -e "${red}[✗] Fail${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ;;
            4) echo "" ; systemctl status XrayR --no-pager || true                  ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ;;
            5)
                echo ""
                if [[ -f /var/log/XrayR/error.log ]]; then
                    tail -n 80 /var/log/XrayR/error.log
                else
                    journalctl -u XrayR --no-pager -n 80
                fi
                read -rp "$(echo -e "${cyan}Enter...${plain}")" _
                ;;
            6)
                command -v nano &>/dev/null && nano "$XRAYR_CFG" || vi "$XRAYR_CFG"
                echo ""
                echo -ne "${green} Restart để apply? [y/N]: ${plain}"
                read -r rr
                [[ "$rr" =~ ^[Yy] ]] && { systemctl restart XrayR && echo -e "${green}[✓] Restarted${plain}" || echo -e "${red}[✗] Fail${plain}" ; }
                read -rp "$(echo -e "${cyan}Enter...${plain}")" _
                ;;
            0) return ;;
            *) echo -e "${red}[!] Nhập 0–6${plain}" ;;
        esac
    done
}

main() {
    check_root
    while true; do
        header
        echo -e "${cyan}  ┌───────────────────────────────────┐${plain}"
        echo -e "${cyan}  │   1   Cài đặt XrayR               │${plain}"
        echo -e "${cyan}  │   2   Quản lý XrayR               │${plain}"
        echo -e "${cyan}  │   3   Gỡ cài đặt XrayR            │${plain}"
        echo -e "${cyan}  │   0   Thoát                       │${plain}"
        echo -e "${cyan}  └───────────────────────────────────┘${plain}"
        echo ""
        echo -ne "${green}  Chọn: ${plain}"
        read -r opt
        case "$opt" in
            1) do_install   ;;
            2) do_manage    ;;
            3) do_uninstall ;;
            0) echo -e "${green}\n  Tạm biệt!\n${plain}" ; exit 0 ;;
            *) echo -e "${red}  [!] Nhập 0–3${plain}" ;;
        esac
    done
}

main
