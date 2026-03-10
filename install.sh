#!/bin/bash

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
CUSTOM_INBOUND_DIR="/etc/XrayR/custom_inbound"

#============================================================
#  TIỆN ÍCH
#============================================================
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${red}❌ Cần chạy bằng root!  →  sudo bash install.sh${plain}" && exit 1
}

detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi "debian|ubuntu" /etc/issue 2>/dev/null; then
        release="debian"
    elif grep -Eqi "debian|ubuntu" /proc/version 2>/dev/null; then
        release="debian"
    else
        echo -e "${red}❌ Không nhận diện được hệ điều hành!${plain}"
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
            echo -e "${red}❌ Kiến trúc không hỗ trợ: $raw_arch${plain}"
            exit 1
            ;;
    esac
}

is_installed() { [[ -f "$XRAYR_BIN" ]]; }

header() {
    clear
    echo -e "${cyan}╔══════════════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║                                                      ║${plain}"
    echo -e "${cyan}║${plain}    ${bold}${green}XrayR - ChungVPN — V2Board${plain}       ${cyan}║${plain}"
    echo -e "${cyan}║                                                      ║${plain}"
    echo -e "${cyan}╚══════════════════════════════════════════════════════╝${plain}"

    if ! is_installed; then
        echo -e "  Trạng thái: ${red}● Chưa cài đặt${plain}"
    elif systemctl is-active --quiet XrayR 2>/dev/null; then
        echo -e "  Trạng thái: ${green}● Đang chạy${plain}"
    else
        echo -e "  Trạng thái: ${yellow}● Đã cài, chưa chạy${plain}"
    fi
    echo ""
}

wait_key() {
    read -rp "$(echo -e "${cyan}▶ Ấn Enter để tiếp tục...${plain}")" _
}

#============================================================
#  CÀI DEPENDENCIES
#============================================================
install_deps() {
    echo -e "${blue}[●] Kiểm tra các gói cần thiết...${plain}"

    local missing_pkgs=()
    command -v curl  &>/dev/null || missing_pkgs+=("curl")
    command -v wget  &>/dev/null || missing_pkgs+=("wget")
    command -v unzip &>/dev/null || missing_pkgs+=("unzip")

    if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
        echo -e "${green}[✓] Tất cả đã có sẵn${plain}"
        return 0
    fi

    echo -e "${yellow}[!] Thiếu: ${missing_pkgs[*]}${plain}"
    echo -e "${blue}[●] Đang cài...${plain}"

    if [[ "$release" == "centos" ]]; then
        yum install -y -q "${missing_pkgs[@]}" 2>/dev/null
    else
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq "${missing_pkgs[@]}" 2>/dev/null
    fi

    echo -e "${green}[✓] Xong${plain}"
}

#============================================================
#  TẮT FIREWALL
#============================================================
disable_fw() {
    echo -e "${blue}[●] Tắt firewall...${plain}"
    if command -v ufw &>/dev/null; then
        ufw disable &>/dev/null
        echo -e "${green}[✓] UFW đã tắt${plain}"
    elif command -v firewall-cmd &>/dev/null; then
        systemctl stop firewalld &>/dev/null
        systemctl disable firewalld &>/dev/null
        echo -e "${green}[✓] Firewalld đã tắt${plain}"
    else
        echo -e "${yellow}[—] Không có firewall${plain}"
    fi
}

#============================================================
#  DỌN DẸP CÀI ĐẶT CŨ
#============================================================
cleanup_old() {
    echo -e "${blue}[●] Dọn dẹp cài đặt cũ...${plain}"

    local cleaned=false

    if systemctl is-active --quiet XrayR 2>/dev/null; then
        echo -e "${yellow}  → Dừng service cũ...${plain}"
        systemctl stop XrayR 2>/dev/null
        cleaned=true
    fi

    if [[ -f "$XRAYR_SVC" ]]; then
        systemctl disable XrayR 2>/dev/null
        rm -f "$XRAYR_SVC"
        cleaned=true
    fi

    if [[ -d "$XRAYR_DIR" ]]; then
        rm -rf "$XRAYR_DIR"
        cleaned=true
    fi

    if [[ -d "/etc/XrayR" ]]; then
        rm -rf /etc/XrayR
        cleaned=true
    fi

    if [[ "$cleaned" == true ]]; then
        systemctl daemon-reload 2>/dev/null
        echo -e "${green}[✓] Đã dọn sạch${plain}"
    else
        echo -e "${green}[✓] Không có cài đặt cũ${plain}"
    fi
}

#============================================================
#  TẢI XrayR
#============================================================
install_binary() {
    echo -e "${blue}[●] Tải XrayR (kiến trúc: ${arch})...${plain}"
    mkdir -p "$XRAYR_DIR"

    local url="https://github.com/XrayR-project/XrayR/releases/latest/download/XrayR-linux-${arch}.zip"
    local mirrors=(
        "$url"
        "https://ghproxy.com/$url"
    )

    local zip_path="$XRAYR_DIR/XrayR.zip"
    local downloaded=false

    for mirror in "${mirrors[@]}"; do
        echo -e "${blue}  → Đang tải từ: $mirror${plain}"

        for attempt in 1 2 3; do
            if curl -fSL --connect-timeout 15 --max-time 600 \
                    --progress-bar -o "$zip_path" "$mirror" 2>&1; then

                if [[ -s "$zip_path" ]] && file "$zip_path" 2>/dev/null | grep -qi "zip"; then
                    echo -e "${green}[✓] Tải thành công${plain}"
                    downloaded=true
                    break 2
                fi
            fi

            rm -f "$zip_path"
            [[ $attempt -lt 3 ]] && sleep 2
        done
    done

    if [[ "$downloaded" != true ]]; then
        echo -e "${red}[✗] Tải thất bại sau nhiều lần thử${plain}"
        return 1
    fi

    echo -e "${blue}[●] Giải nén...${plain}"
    cd "$XRAYR_DIR" || return 1

    if ! unzip -oq "$zip_path" 2>/dev/null; then
        echo -e "${red}[✗] Giải nén thất bại${plain}"
        return 1
    fi

    rm -f "$zip_path"
    chmod +x "$XRAYR_BIN"

    mkdir -p /etc/XrayR
    if [[ -f "$XRAYR_DIR/config.yml" ]]; then
        cp "$XRAYR_DIR/config.yml" "$XRAYR_CFG"
    fi

    echo -e "${green}[✓] Cài binary thành công${plain}"
}

#============================================================
#  FIX QUIC CRASH — Tạo custom inbound tắt QUIC sniffing
#  BUG: xray-core panic khi gói QUIC > 2048 bytes
#============================================================
create_quic_fix() {
    echo -e "${blue}[●] Áp dụng fix QUIC crash...${plain}"
    mkdir -p "$CUSTOM_INBOUND_DIR"

    cat > "$CUSTOM_INBOUND_DIR/sniff_fix.json" << 'EOF'
{
  "tag": "sniff-fix",
  "listen": "127.0.0.1",
  "port": 10900,
  "protocol": "dokodemo-door",
  "settings": {
    "address": "127.0.0.1"
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls"]
  }
}
EOF
    echo -e "${green}[✓] Đã tắt QUIC sniffing (fix crash panic)${plain}"
}

#============================================================
#  NHẬP THÔNG TIN - HỖ TRỢ 1-2 NODE
#============================================================
input_all_info() {
    # ── Số node ──
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║  BẠN MUỐN CÀI BAO NHIÊU NODE?              ║${plain}"
    echo -e "${cyan}║  (1 hoặc 2 node trên cùng 1 VPS)           ║${plain}"
    echo -e "${cyan}╚════════════════════════════════════════════╝${plain}"
    echo ""
    while true; do
        echo -ne "${green}▶ Nhập 1 hoặc 2: ${plain}"
        read -r num_nodes
        [[ "$num_nodes" == "1" ]] || [[ "$num_nodes" == "2" ]] && break
        echo -e "${red}  ⚠ Chỉ nhập 1 hoặc 2!${plain}"
    done

    # ── Panel URL ──
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║  ĐỊA CHỈ V2BOARD PANEL                     ║${plain}"
    echo -e "${cyan}╚════════════════════════════════════════════╝${plain}"
    while true; do
        echo -ne "${green}▶ VD https://panel.example.com: ${plain}"
        read -r panel_url
        panel_url="${panel_url%/}"
        [[ "$panel_url" =~ ^https?:// ]] && break
        echo -e "${red}  ⚠ Phải có http:// hoặc https://${plain}"
    done

    # ── API Key ──
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║  API KEY                                   ║${plain}"
    echo -e "${cyan}║  (V2Board → Cài đặt → API)                 ║${plain}"
    echo -e "${cyan}╚════════════════════════════════════════════╝${plain}"
    while true; do
        echo -ne "${green}▶ API Key: ${plain}"
        read -r api_key
        [[ -n "$api_key" ]] && break
        echo -e "${red}  ⚠ Không được rỗng!${plain}"
    done

    # ── Node 1 ──
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║  NODE 1 - THÔNG TIN                        ║${plain}"
    echo -e "${cyan}╚════════════════════════════════════════════╝${plain}"

    while true; do
        echo -ne "${green}▶ Node 1 ID: ${plain}"
        read -r node1_id
        [[ "$node1_id" =~ ^[0-9]+$ ]] && break
        echo -e "${red}  ⚠ Chỉ nhập số!${plain}"
    done

    echo ""
    echo -e "${yellow}Chọn loại giao thức cho Node 1:${plain}"
    echo -e "  ${cyan}1${plain} → VMESS"
    echo -e "  ${cyan}2${plain} → VLESS"
    echo -e "  ${cyan}3${plain} → Trojan"
    echo -e "  ${cyan}4${plain} → Shadowsocks"

    while true; do
        echo -ne "${green}▶ Chọn [1-4]: ${plain}"
        read -r n1_choice
        case "$n1_choice" in
            # FIX: VlessFlow chỉ dùng cho VLESS, VMess/Trojan/SS để trống
            1) node1_type="V2ray"       ; node1_vless="false" ; node1_flow="" ; break ;;
            2) node1_type="V2ray"       ; node1_vless="true"  ; node1_flow="xtls-rprx-vision" ; break ;;
            3) node1_type="Trojan"      ; node1_vless="false" ; node1_flow="" ; break ;;
            4) node1_type="Shadowsocks" ; node1_vless="false" ; node1_flow="" ; break ;;
            *) echo -e "${red}  ⚠ Chỉ nhập 1, 2, 3 hoặc 4!${plain}" ;;
        esac
    done

    # ── Node 2 (nếu có) ──
    if [[ "$num_nodes" == "2" ]]; then
        echo ""
        echo -e "${cyan}╔════════════════════════════════════════════╗${plain}"
        echo -e "${cyan}║  NODE 2 - THÔNG TIN                        ║${plain}"
        echo -e "${cyan}╚════════════════════════════════════════════╝${plain}"

        while true; do
            echo -ne "${green}▶ Node 2 ID: ${plain}"
            read -r node2_id
            [[ "$node2_id" =~ ^[0-9]+$ ]] && break
            echo -e "${red}  ⚠ Chỉ nhập số!${plain}"
        done

        echo ""
        echo -e "${yellow}Chọn loại giao thức cho Node 2:${plain}"
        echo -e "  ${cyan}1${plain} → VMESS"
        echo -e "  ${cyan}2${plain} → VLESS"
        echo -e "  ${cyan}3${plain} → Trojan"
        echo -e "  ${cyan}4${plain} → Shadowsocks"

        while true; do
            echo -ne "${green}▶ Chọn [1-4]: ${plain}"
            read -r n2_choice
            case "$n2_choice" in
                # FIX: VlessFlow chỉ dùng cho VLESS
                1) node2_type="V2ray"       ; node2_vless="false" ; node2_flow="" ; break ;;
                2) node2_type="V2ray"       ; node2_vless="true"  ; node2_flow="xtls-rprx-vision" ; break ;;
                3) node2_type="Trojan"      ; node2_vless="false" ; node2_flow="" ; break ;;
                4) node2_type="Shadowsocks" ; node2_vless="false" ; node2_flow="" ; break ;;
                *) echo -e "${red}  ⚠ Chỉ nhập 1, 2, 3 hoặc 4!${plain}" ;;
            esac
        done
    fi

    # ── Redis ──
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║  REDIS - GIỚI HẠN THIẾT BỊ                 ║${plain}"
    echo -e "${cyan}╚════════════════════════════════════════════╝${plain}"
    echo -ne "${green}▶ Bạn có Redis không? [y/N]: ${plain}"
    read -r redis_choice

    if [[ "$redis_choice" =~ ^[Yy] ]]; then
        redis_enabled="true"

        echo -ne "${green}▶ Redis Addr (127.0.0.1:6379): ${plain}"
        read -r redis_addr
        [[ -z "$redis_addr" ]] && redis_addr="127.0.0.1:6379"

        echo -ne "${green}▶ Redis Password (Enter = không có): ${plain}"
        read -r redis_pass

        echo -ne "${green}▶ Redis DB [0]: ${plain}"
        read -r redis_db
        [[ -z "$redis_db" ]] && redis_db=0
    else
        redis_enabled="false"
        redis_addr="127.0.0.1:6379"
        redis_pass=""
        redis_db=0
    fi
}

#============================================================
#  XEM LẠI CẤU HÌNH
#============================================================
review() {
    echo ""
    echo -e "${cyan}╔════════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║  XEM LẠI CẤU HÌNH                          ║${plain}"
    echo -e "${cyan}╚════════════════════════════════════════════╝${plain}"
    echo ""
    echo -e "${green}  Panel URL:${plain} $panel_url"
    echo -e "${green}  API Key:${plain}   ${api_key:0:20}..."
    echo ""
    echo -e "${green}  Node 1:${plain}"
    echo -e "    └─ ID: $node1_id"
    if [[ "$node1_type" == "V2ray" && "$node1_vless" == "true" ]]; then
        echo -e "    └─ Giao thức: VLESS (flow: xtls-rprx-vision)"
    elif [[ "$node1_type" == "V2ray" ]]; then
        echo -e "    └─ Giao thức: VMESS"
    else
        echo -e "    └─ Giao thức: $node1_type"
    fi

    if [[ "$num_nodes" == "2" ]]; then
        echo ""
        echo -e "${green}  Node 2:${plain}"
        echo -e "    └─ ID: $node2_id"
        if [[ "$node2_type" == "V2ray" && "$node2_vless" == "true" ]]; then
            echo -e "    └─ Giao thức: VLESS (flow: xtls-rprx-vision)"
        elif [[ "$node2_type" == "V2ray" ]]; then
            echo -e "    └─ Giao thức: VMESS"
        else
            echo -e "    └─ Giao thức: $node2_type"
        fi
    fi

    echo ""
    echo -e "${green}  Redis:${plain} $redis_enabled"
    if [[ "$redis_enabled" == "true" ]]; then
        echo -e "    └─ Địa chỉ: $redis_addr"
        echo -e "    └─ DB: $redis_db"
    fi

    echo ""
    echo -e "${cyan}════════════════════════════════════════════${plain}"
    echo ""
    echo -ne "${green}▶ Xác nhận cài đặt? [y/N]: ${plain}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy] ]]
}

#============================================================
#  GHI CONFIG
#  FIX: VlessFlow chỉ set khi VLESS, trống khi VMess/Trojan/SS
#============================================================
write_config() {
    echo ""
    echo -e "${blue}[●] Tạo cấu hình...${plain}"

    cat > "$XRAYR_CFG" << EOF
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
      ApiHost: "$panel_url"
      ApiKey: "$api_key"
      NodeID: $node1_id
      NodeType: $node1_type
      Timeout: 30
      EnableVless: $node1_vless
      VlessFlow: "$node1_flow"
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
        Enable: $redis_enabled
        RedisNetwork: tcp
        RedisAddr: $redis_addr
        RedisUsername:
        RedisPassword: $redis_pass
        RedisDB: $redis_db
        Timeout: 5
        Expiry: 60
      CertConfig:
        CertMode: none
        CertDomain: ""
        CertFile:
        KeyFile:
EOF

    # Node 2 nếu có
    if [[ "$num_nodes" == "2" ]]; then
        echo -e "${blue}[●] Thêm Node 2...${plain}"
        local node2_redis_db=$((redis_db + 1))

        cat >> "$XRAYR_CFG" << EOF

  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "$panel_url"
      ApiKey: "$api_key"
      NodeID: $node2_id
      NodeType: $node2_type
      Timeout: 30
      EnableVless: $node2_vless
      VlessFlow: "$node2_flow"
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
        Enable: $redis_enabled
        RedisNetwork: tcp
        RedisAddr: $redis_addr
        RedisUsername:
        RedisPassword: $redis_pass
        RedisDB: $node2_redis_db
        Timeout: 5
        Expiry: 60
      CertConfig:
        CertMode: none
        CertDomain: ""
        CertFile:
        KeyFile:
EOF
    fi

    echo -e "${green}[✓] Config đã tạo${plain}"
}

#============================================================
#  TẠO SYSTEMD SERVICE
#============================================================
create_service() {
    echo -e "${blue}[●] Tạo systemd service...${plain}"

    cat > "$XRAYR_SVC" << EOF
[Unit]
Description=XrayR Multi-Node Service
Documentation=https://github.com/XrayR-project/XrayR
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$XRAYR_BIN --config $XRAYR_CFG
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo -e "${green}[✓] Service đã tạo${plain}"
}

#============================================================
#  CÀI JOURNAL PARSER (đếm thiết bị theo SOURCE IP)
#============================================================
install_journal_parser() {
    # Cài Python3 + redis-py
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq python3 python3-pip 2>/dev/null
    pip3 install redis -q 2>/dev/null

    mkdir -p /opt/xrayr-journal-parser

    cat > /opt/xrayr-journal-parser/xrayr_journal_parser.py << 'EOFPY'
#!/usr/bin/env python3
"""XrayR Journal Parser v2 - SOURCE IP only"""
import re, redis, subprocess, sys
from datetime import datetime

REDIS_HOST = "160.30.137.171"
REDIS_PORT = 6379
REDIS_PASSWORD = "chungvpn12!@"
REDIS_DB = 0
TTL = 120

BLACKLIST_IPS = {'1.1.1.1','1.0.0.1','8.8.8.8','8.8.4.4','9.9.9.9','208.67.222.222','208.67.220.220','0.0.0.0'}

try:
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, db=REDIS_DB, decode_responses=True)
    r.ping()
    print(f"✓ Connected Redis {REDIS_HOST}")
except Exception as e:
    print(f"✗ Redis failed: {e}")
    sys.exit(1)

# Lấy SOURCE IP (trước "accepted"), KHÔNG lấy DEST IP (sau "accepted tcp:")
PATTERN = re.compile(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):\d+\s+accepted\s+(?:tcp|udp):.*?v2board\.user[|\[](\d+)')

stats = {"parsed": 0, "writes": 0, "skipped": 0}

def parse(line):
    m = PATTERN.search(line)
    if not m: return None, None
    ip, uid = m.group(1), m.group(2)
    if ip.startswith(('127.','10.','192.168.','172.')) or ip in BLACKLIST_IPS:
        stats["skipped"] += 1
        return None, None
    return ip, uid

def write(uid, ip):
    try:
        r.setex(f"0|{ip}:journal-{ip.replace('.', '-')}@v2board.user[{uid}]", TTL, "1")
        stats["writes"] += 1
        return True
    except: return False

try:
    proc = subprocess.Popen(["journalctl","-u","XrayR","-f","-n","0"], stdout=subprocess.PIPE, universal_newlines=True)
    print("✓ Watching XrayR logs | SOURCE IP only | TTL=120s")
    for line in iter(proc.stdout.readline, ''):
        ip, uid = parse(line.strip())
        if ip and uid:
            stats["parsed"] += 1
            if write(uid, ip):
                print(f"[{datetime.now().strftime('%H:%M:%S')}] User {uid} | {ip} | Total:{stats['parsed']}")
except KeyboardInterrupt:
    print(f"\nStopped | Parsed={stats['parsed']} Writes={stats['writes']} Skipped={stats['skipped']}")
EOFPY

    chmod +x /opt/xrayr-journal-parser/xrayr_journal_parser.py

    cat > /etc/systemd/system/xrayr-journal-parser.service << 'EOFSVC'
[Unit]
Description=XrayR Journal Parser v2 - Device Tracker
After=network.target XrayR.service
Requires=systemd-journald.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/xrayr-journal-parser
ExecStart=/usr/bin/python3 /opt/xrayr-journal-parser/xrayr_journal_parser.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSVC

    systemctl daemon-reload
    systemctl enable xrayr-journal-parser &>/dev/null
    systemctl restart xrayr-journal-parser
    sleep 2

    if systemctl is-active --quiet xrayr-journal-parser; then
        echo -e "${green}[✓] Journal Parser đang chạy${plain}"
    else
        echo -e "${red}[✗] Journal Parser lỗi — kiểm tra: journalctl -u xrayr-journal-parser -f${plain}"
    fi
}

#============================================================
#  CÀI ĐẶT (MAIN FLOW)
#============================================================
do_install() {
    header
    echo -e "${bold}${cyan}╔══════════════════════════════════════════════════════╗${plain}"
    echo -e "${bold}${cyan}║                 CÀI ĐẶT XrayR                        ║${plain}"
    echo -e "${bold}${cyan}╚══════════════════════════════════════════════════════╝${plain}"
    echo ""

    if is_installed; then
        echo -e "${yellow}⚠ Đã cài rồi. Cài lại sẽ xóa hết cấu hình cũ.${plain}"
        echo -ne "${green}▶ Tiếp tục? [y/N]: ${plain}"
        read -r ov
        [[ ! "$ov" =~ ^[Yy] ]] && return
    fi

    detect_os
    detect_arch
    install_deps
    disable_fw
    cleanup_old
    install_binary || { wait_key ; return ; }

    input_all_info
    review || { echo -e "${yellow}\n[—] Hủy cài đặt.${plain}" ; wait_key ; return ; }

    write_config
    create_quic_fix   # FIX: tắt QUIC sniffing tránh crash panic
    create_service

    echo ""
    echo -e "${blue}[●] Khởi động XrayR...${plain}"
    systemctl enable XrayR &>/dev/null
    systemctl start XrayR
    sleep 3

    echo ""
    if systemctl is-active --quiet XrayR; then
        echo -e "${green}${bold}╔══════════════════════════════════════════════════════╗${plain}"
        echo -e "${green}${bold}║          ✓ CÀI ĐẶT THÀNH CÔNG!                       ║${plain}"
        echo -e "${green}${bold}╚══════════════════════════════════════════════════════╝${plain}"
        echo ""
        echo -e "${green}XrayR đang chạy và tự đồng bộ với V2Board.${plain}"
        if [[ "$num_nodes" == "2" ]]; then
            echo -e "${cyan}→ Đã cài 2 nodes: ID $node1_id và $node2_id${plain}"
        else
            echo -e "${cyan}→ Đã cài 1 node: ID $node1_id${plain}"
        fi
        echo ""
        echo -e "${yellow}Lệnh kiểm tra log:${plain}"
        echo -e "${cyan}  journalctl -u XrayR -f --no-pager${plain}"

        # ── Cài Journal Parser tự động ──
        echo ""
        echo -e "${blue}[●] Cài Journal Parser (đếm thiết bị)...${plain}"
        install_journal_parser
    else
        echo -e "${red}╔══════════════════════════════════════════════════════╗${plain}"
        echo -e "${red}║          ✗ LỖI KHI KHỞI ĐỘNG                         ║${plain}"
        echo -e "${red}╚══════════════════════════════════════════════════════╝${plain}"
        echo ""
        echo -e "${yellow}Xem log lỗi:${plain}"
        journalctl -u XrayR -n 30 --no-pager
    fi

    wait_key
}

#============================================================
#  GỠ CÀI ĐẶT
#============================================================
do_uninstall() {
    header
    echo -e "${bold}${red}╔══════════════════════════════════════════════════════╗${plain}"
    echo -e "${bold}${red}║              GỠ CÀI ĐẶT XrayR                        ║${plain}"
    echo -e "${bold}${red}╚══════════════════════════════════════════════════════╝${plain}"
    echo ""

    if ! is_installed; then
        echo -e "${yellow}⚠ XrayR chưa được cài đặt.${plain}"
        wait_key
        return
    fi

    echo -e "${red}Sẽ xóa:${plain}"
    echo -e "  • $XRAYR_DIR"
    echo -e "  • /etc/XrayR"
    echo -e "  • Systemd service"
    echo ""
    echo -ne "${green}▶ Xác nhận gỡ cài đặt? [y/N]: ${plain}"
    read -r yn

    [[ ! "$yn" =~ ^[Yy] ]] && { echo -e "${yellow}[—] Hủy${plain}" ; return ; }

    echo ""
    echo -e "${blue}[●] Đang gỡ...${plain}"
    systemctl stop XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -rf "$XRAYR_DIR" /etc/XrayR "$XRAYR_SVC"
    systemctl daemon-reload 2>/dev/null

    echo -e "${green}[✓] Đã gỡ hoàn toàn.${plain}"
    wait_key
}

#============================================================
#  QUẢN LÝ
#============================================================
do_manage() {
    while true; do
        header
        echo -e "${bold}${cyan}╔══════════════════════════════════════════════════════╗${plain}"
        echo -e "${bold}${cyan}║                  QUẢN LÝ XrayR                       ║${plain}"
        echo -e "${bold}${cyan}╚══════════════════════════════════════════════════════╝${plain}"
        echo ""
        echo -e "  ${cyan}1${plain}  Khởi động         ${cyan}4${plain}  Xem trạng thái"
        echo -e "  ${cyan}2${plain}  Dừng              ${cyan}5${plain}  Xem log"
        echo -e "  ${cyan}3${plain}  Khởi động lại     ${cyan}6${plain}  Sửa config.yml"
        echo -e "  ${cyan}7${plain}  Cập nhật XrayR"
        echo ""
        echo -e "  ${cyan}0${plain}  Quay về menu chính"
        echo ""
        echo -ne "${green}▶ Chọn: ${plain}"
        read -r m

        case "$m" in
            1)
                systemctl start XrayR
                if systemctl is-active --quiet XrayR; then
                    echo -e "${green}[✓] Đã khởi động${plain}"
                else
                    echo -e "${red}[✗] Khởi động thất bại${plain}"
                fi
                wait_key
                ;;
            2)
                systemctl stop XrayR && echo -e "${green}[✓] Đã dừng${plain}"
                wait_key
                ;;
            3)
                systemctl restart XrayR
                sleep 2
                if systemctl is-active --quiet XrayR; then
                    echo -e "${green}[✓] Đã khởi động lại${plain}"
                else
                    echo -e "${red}[✗] Khởi động lại thất bại${plain}"
                    journalctl -u XrayR -n 20 --no-pager
                fi
                wait_key
                ;;
            4)
                echo ""
                systemctl status XrayR --no-pager
                wait_key
                ;;
            5)
                echo ""
                echo -e "${cyan}═══ LOG (100 dòng gần nhất) ═══${plain}"
                journalctl -u XrayR -n 100 --no-pager
                wait_key
                ;;
            6)
                echo ""
                echo -e "${blue}[●] Mở config.yml...${plain}"
                command -v nano &>/dev/null && nano "$XRAYR_CFG" || vi "$XRAYR_CFG"

                echo ""
                echo -ne "${green}▶ Khởi động lại để áp dụng? [y/N]: ${plain}"
                read -r rr

                if [[ "$rr" =~ ^[Yy] ]]; then
                    systemctl restart XrayR
                    sleep 2
                    if systemctl is-active --quiet XrayR; then
                        echo -e "${green}[✓] Đã khởi động lại${plain}"
                    else
                        echo -e "${red}[✗] Khởi động lại thất bại — kiểm tra config${plain}"
                        journalctl -u XrayR -n 20 --no-pager
                    fi
                fi
                wait_key
                ;;
            7)
                echo ""
                echo -e "${blue}[●] Đang cập nhật XrayR...${plain}"
                systemctl stop XrayR 2>/dev/null
                detect_arch
                local url="https://github.com/XrayR-project/XrayR/releases/latest/download/XrayR-linux-${arch}.zip"
                local zip_path="$XRAYR_DIR/XrayR.zip"
                if curl -fSL --connect-timeout 15 --max-time 600 --progress-bar -o "$zip_path" "$url" 2>&1; then
                    cd "$XRAYR_DIR" && unzip -oq "$zip_path" && rm -f "$zip_path"
                    chmod +x "$XRAYR_BIN"
                    create_quic_fix
                    systemctl start XrayR
                    sleep 2
                    if systemctl is-active --quiet XrayR; then
                        echo -e "${green}[✓] Cập nhật thành công${plain}"
                    else
                        echo -e "${red}[✗] Lỗi sau cập nhật${plain}"
                        journalctl -u XrayR -n 20 --no-pager
                    fi
                else
                    echo -e "${red}[✗] Tải thất bại${plain}"
                    systemctl start XrayR
                fi
                wait_key
                ;;
            0) return ;;
            *)
                echo -e "${red}⚠ Chọn từ 0-7 thôi!${plain}"
                sleep 1
                ;;
        esac
    done
}

#============================================================
#  MENU CHÍNH
#============================================================
main() {
    check_root

    while true; do
        header
        echo -e "${cyan}╔══════════════════════════════════════════════════════╗${plain}"
        echo -e "${cyan}║                                                      ║${plain}"
        echo -e "${cyan}║  ${bold}1${plain}  ${cyan}Cài đặt XrayR                                   ${cyan}║${plain}"
        echo -e "${cyan}║  ${bold}2${plain}  ${cyan}Quản lý XrayR                                   ${cyan}║${plain}"
        echo -e "${cyan}║  ${bold}3${plain}  ${cyan}Gỡ cài đặt XrayR                                ${cyan}║${plain}"
        echo -e "${cyan}║  ${bold}0${plain}  ${cyan}Thoát                                           ${cyan}║${plain}"
        echo -e "${cyan}║                                                      ║${plain}"
        echo -e "${cyan}╚══════════════════════════════════════════════════════╝${plain}"
        echo ""
        echo -ne "${green}▶ Chọn: ${plain}"
        read -r opt

        case "$opt" in
            1) do_install ;;
            2) do_manage ;;
            3) do_uninstall ;;
            0)
                echo ""
                echo -e "${green}Tạm biệt! 👋${plain}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${red}⚠ Chọn từ 0-3 thôi!${plain}"
                sleep 1
                ;;
        esac
    done
}

main
