#!/bin/bash
#============================================================
#   XrayR Auto Install — V2Board (TAR.GZ Version)

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

# Config từ GitHub repo của bạn
CONFIG_DOWNLOAD_URL="https://raw.githubusercontent.com/Chung-VPN/XrayR-ChungNG/main/config.yml"

# Mirrors cho download - ưu tiên CDN
DOWNLOAD_SOURCES=(
    "jsdelivr|https://cdn.jsdelivr.net/gh/XrayR-project/XrayR@{VERSION}/release/XrayR-linux-{ARCH}"
    "direct|https://github.com/XrayR-project/XrayR/releases/download/{VERSION}/XrayR-linux-{ARCH}.tar.gz"
    "ghproxy|https://ghproxy.com/https://github.com/XrayR-project/XrayR/releases/download/{VERSION}/XrayR-linux-{ARCH}.tar.gz"
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
        echo -e "  Trạng thái: ${yellow}● Đã cài, chưa chạy${plain}"
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
            apt-get install -y -qq curl wget tar gzip > /dev/null 2>&1 ;;
        centos)
            yum install -y -q curl wget tar gzip > /dev/null 2>&1 ;;
    esac
    echo -e "${green}[✓] OK${plain}"
}

get_latest_version() {
    echo -e "${blue}[*] Lấy phiên bản mới nhất...${plain}"
    
    last_version=$(curl -sSL --connect-timeout 10 --max-time 20 \
        "https://api.github.com/repos/XrayR-project/XrayR/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null)
    
    if [[ -z "$last_version" ]]; then
        echo -e "${yellow}[!] API chậm, dùng v0.9.4${plain}"
        last_version="v0.9.4"
    fi
    
    echo -e "${green}[✓] Version: $last_version  |  Arch: $arch${plain}"
}

download_binary_direct() {
    local url="$1"
    local output="$2"
    
    echo -e "${blue}[*] Tải binary...${plain}"
    
    if wget -q --show-progress --timeout=60 --tries=3 --no-check-certificate -O "$output" "$url" 2>&1; then
        local size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)
        if [[ -s "$output" ]] && [[ "$size" -gt 5000000 ]]; then
            chmod +x "$output"
            if [[ -x "$output" ]]; then
                echo -e "${green}[✓] Tải thành công (${size} bytes)${plain}"
                return 0
            fi
        fi
    fi
    
    echo -e "${red}[✗] Thất bại${plain}"
    return 1
}

download_tarball() {
    local url="$1"
    local tarfile="$2"
    
    echo -e "${blue}[*] Tải tar.gz...${plain}"
    
    if wget -q --show-progress --timeout=60 --tries=3 --no-check-certificate -O "$tarfile" "$url" 2>&1; then
        if [[ -s "$tarfile" ]]; then
            local size=$(stat -c%s "$tarfile" 2>/dev/null || stat -f%z "$tarfile" 2>/dev/null)
            
            if [[ "$size" -lt 1048576 ]]; then
                echo -e "${yellow}[!] File quá nhỏ ($size bytes)${plain}"
                return 1
            fi
            
            if command -v file >/dev/null 2>&1; then
                local ftype=$(file -b "$tarfile")
                if [[ "$ftype" =~ HTML ]]; then
                    echo -e "${yellow}[!] File là HTML (bị chặn)${plain}"
                    return 1
                fi
            fi
            
            echo -e "${green}[✓] Tải OK (${size} bytes)${plain}"
            return 0
        fi
    fi
    
    return 1
}

install_binary() {
    get_latest_version
    
    mkdir -p "$XRAYR_DIR"
    cd "$XRAYR_DIR"
    
    local success=false
    local method=""
    
    for source in "${DOWNLOAD_SOURCES[@]}"; do
        local type="${source%%|*}"
        local url_template="${source#*|}"
        local url="${url_template//\{VERSION\}/$last_version}"
        url="${url//\{ARCH\}/$arch}"
        
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "${cyan}[*] Thử: $type${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        
        rm -f XrayR XrayR-linux.tar.gz 2>/dev/null
        
        case "$type" in
            jsdelivr)
                if download_binary_direct "$url" "$XRAYR_BIN"; then
                    method="jsDelivr CDN"
                    success=true
                    break
                fi
                ;;
            *)
                if download_tarball "$url" "XrayR-linux.tar.gz"; then
                    echo -e "${blue}[*] Giải nén...${plain}"
                    if tar -xzf XrayR-linux.tar.gz 2>&1; then
                        if [[ -f "XrayR" ]]; then
                            mv XrayR "$XRAYR_BIN"
                            chmod +x "$XRAYR_BIN"
                            method="$type"
                            success=true
                            rm -f XrayR-linux.tar.gz
                            break
                        fi
                    fi
                    rm -f XrayR-linux.tar.gz
                fi
                ;;
        esac
        echo ""
    done
    
    if ! $success; then
        echo -e "${red}╔══════════════════════════════════════╗${plain}"
        echo -e "${red}║  [✗] TẤT CẢ NGUỒN ĐỀU THẤT BẠI      ║${plain}"
        echo -e "${red}╠══════════════════════════════════════╣${plain}"
        echo -e "${yellow}║  Giải pháp:                          ║${plain}"
        echo -e "${yellow}║  1. Tải từ máy:                      ║${plain}"
        echo -e "${yellow}║     github.com/XrayR-project/XrayR   ║${plain}"
        echo -e "${yellow}║     /releases                        ║${plain}"
        echo -e "${yellow}║  2. Upload lên /usr/local/XrayR/     ║${plain}"
        echo -e "${yellow}║  3. Giải nén: tar -xzf file.tar.gz   ║${plain}"
        echo -e "${yellow}║  4. Chạy lại script                  ║${plain}"
        echo -e "${red}╚══════════════════════════════════════╝${plain}"
        return 1
    fi
    
    if [[ ! -x "$XRAYR_BIN" ]]; then
        echo -e "${red}[✗] Binary lỗi!${plain}"
        return 1
    fi
    
    if "$XRAYR_BIN" version >/dev/null 2>&1; then
        local ver=$("$XRAYR_BIN" version 2>/dev/null | head -1)
        echo -e "${green}[✓] Cài OK qua $method${plain}"
        echo -e "${green}    → $ver${plain}"
    else
        echo -e "${green}[✓] Binary: $XRAYR_BIN${plain}"
    fi
}

install_mgmt_cmd() {
    echo -e "${blue}[*] Cài lệnh quản lý...${plain}"
    curl -o /usr/bin/XrayR -Ls "$XRAYR_RELEASE_SH" 2>/dev/null && chmod +x /usr/bin/XrayR 2>/dev/null
    ln -sf /usr/bin/XrayR /usr/bin/xrayr 2>/dev/null
    echo -e "${green}[✓] OK${plain}"
}

download_config() {
    echo -e "${blue}[*] Tải config.yml...${plain}"
    mkdir -p /etc/XrayR

    if ! wget -q --timeout=15 --tries=3 --no-check-certificate -O "$XRAYR_CFG" "$CONFIG_DOWNLOAD_URL"; then
        echo -e "${red}[✗] Thất bại!${plain}"
        return 1
    fi

    if [[ ! -s "$XRAYR_CFG" ]]; then
        echo -e "${red}[✗] File rỗng!${plain}"
        return 1
    fi
    
    echo -e "${green}[✓] OK${plain}"
}

input_api_host() {
    echo ""
    echo -e "${cyan}───────────────────────────────${plain}"
    echo -e "${yellow}API URL (VD: https://panel.com)${plain}"
    while true; do
        echo -ne "${green}URL: ${plain}"
        read -r api_host
        api_host="${api_host%/}"
        [[ -z "$api_host" ]] && { echo -e "${red}Không rỗng!${plain}" ; continue ; }
        [[ "$api_host" =~ ^https?:// ]] && { echo -e "${green}✓ $api_host${plain}" ; break ; }
        echo -e "${red}Phải có http:// hoặc https://${plain}"
    done
}

input_api_key() {
    echo ""
    echo -e "${cyan}───────────────────────────────${plain}"
    echo -e "${yellow}API Key (từ V2Board Settings)${plain}"
    while true; do
        echo -ne "${green}Key: ${plain}"
        read -r api_key
        [[ -z "$api_key" ]] && { echo -e "${red}Không rỗng!${plain}" ; continue ; }
        echo -e "${green}✓ OK${plain}"
        break
    done
}

input_node_id() {
    echo ""
    echo -e "${cyan}───────────────────────────────${plain}"
    echo -e "${yellow}Node ID (từ V2Board Nodes)${plain}"
    while true; do
        echo -ne "${green}ID: ${plain}"
        read -r node_id
        [[ -z "$node_id" ]] && { echo -e "${red}Không rỗng!${plain}" ; continue ; }
        [[ "$node_id" =~ ^[0-9]+$ ]] && { echo -e "${green}✓ $node_id${plain}" ; break ; }
        echo -e "${red}Phải là số!${plain}"
    done
}

input_node_type() {
    echo ""
    echo -e "${cyan}───────────────────────────────${plain}"
    echo -e "${yellow}NodeType: ${cyan}1${plain}=V2ray ${cyan}2${plain}=Trojan ${cyan}3${plain}=SS${plain}"
    while true; do
        echo -ne "${green}Chọn: ${plain}"
        read -r ch
        case "$ch" in
            1) node_type="V2ray" ; echo -e "${green}✓ V2ray${plain}" ; break ;;
            2) node_type="Trojan" ; echo -e "${green}✓ Trojan${plain}" ; break ;;
            3) node_type="Shadowsocks" ; echo -e "${green}✓ SS${plain}" ; break ;;
            *) echo -e "${red}Nhập 1/2/3${plain}" ;;
        esac
    done
}

input_redis() {
    echo ""
    echo -e "${cyan}───────────────────────────────${plain}"
    echo -ne "${yellow}Bật Redis Device Limit? [y/N]: ${plain}"
    read -r re

    if [[ "$re" =~ ^[Yy] ]]; then
        redis_on="true"
        echo -ne "${green}Redis Addr [127.0.0.1:6379]: ${plain}"
        read -r redis_addr
        [[ -z "$redis_addr" ]] && redis_addr="127.0.0.1:6379"
        echo -ne "${green}Password: ${plain}"
        read -r redis_pass
        echo -ne "${green}DB [0]: ${plain}"
        read -r redis_db
        [[ -z "$redis_db" ]] && redis_db="0"
        redis_timeout="5"
        redis_expiry="60"
    else
        redis_on="false"
    fi
}

review() {
    echo ""
    echo -e "${cyan}═══════════════════════════${plain}"
    echo -e "${yellow}URL    :${plain} $api_host"
    echo -e "${yellow}Key    :${plain} ****"
    echo -e "${yellow}NodeID :${plain} $node_id"
    echo -e "${yellow}Type   :${plain} $node_type"
    echo -e "${yellow}Redis  :${plain} $redis_on"
    echo -e "${cyan}═══════════════════════════${plain}"
    echo -ne "${green}OK? [y/N]: ${plain}"
    read -r c
    [[ "$c" =~ ^[Yy] ]]
}

patch_config() {
    echo -e "${blue}[*] Cập nhật config...${plain}"
    sed -i -E 's|^( +)ApiHost:.*$|      ApiHost: "'"$api_host"'"|' "$XRAYR_CFG"
    sed -i -E 's|^( +)ApiKey:.*$|      ApiKey: "'"$api_key"'"|' "$XRAYR_CFG"
    sed -i -E 's/^( +)NodeID:.*$/      NodeID: '"$node_id"'/' "$XRAYR_CFG"
    sed -i -E 's/^( +)NodeType:.*$/      NodeType: '"$node_type"'/' "$XRAYR_CFG"
    
    if [[ "$redis_on" == "true" ]]; then
        sed -i -E '/GlobalDeviceLimitConfig/{n; s/^( +)Enable:.*$/        Enable: true/}' "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisAddr:.*$/        RedisAddr: '"$redis_addr"'/' "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisPassword:.*$/        RedisPassword: '"$redis_pass"'/' "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisDB:.*$/        RedisDB: '"$redis_db"'/' "$XRAYR_CFG"
    fi
    echo -e "${green}[✓] OK${plain}"
}

create_service() {
    echo -e "${blue}[*] Tạo service...${plain}"
    cat > "$XRAYR_SVC" <<EOF
[Unit]
Description=XrayR
After=network.target

[Service]
Type=simple
User=root
ExecStart=$XRAYR_BIN --config $XRAYR_CFG
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo -e "${green}[✓] OK${plain}"
}

do_install() {
    header
    echo -e "${bold}${cyan}── CÀI ĐẶT ──${plain}\n"
    
    if is_installed; then
        echo -ne "${yellow}Đã cài. Cài lại? [y/N]: ${plain}"
        read -r ov
        [[ "$ov" =~ ^[Yy] ]] || return
    fi
    
    detect_os
    detect_arch
    install_deps
    install_binary || { read -p "Enter..." ; return ; }
    install_mgmt_cmd
    download_config || { read -p "Enter..." ; return ; }
    
    input_api_host
    input_api_key
    input_node_id
    input_node_type
    input_redis
    
    review || { echo -e "${yellow}Hủy${plain}" ; read -p "Enter..." ; return ; }
    
    patch_config
    create_service
    
    echo -e "${blue}[*] Khởi động...${plain}"
    systemctl enable XrayR >/dev/null 2>&1
    systemctl start XrayR
    sleep 2
    
    if systemctl is-active --quiet XrayR; then
        echo -e "${green}[✓✓] Chạy OK!${plain}"
    else
        echo -e "${red}[✗] Lỗi${plain}"
        systemctl status XrayR --no-pager
    fi
    read -p "Enter..."
}

do_uninstall() {
    header
    echo -ne "${red}Xóa XrayR? [y/N]: ${plain}"
    read -r yn
    [[ "$yn" =~ ^[Yy] ]] || return
    systemctl stop XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -rf "$XRAYR_DIR" /etc/XrayR "$XRAYR_SVC" /usr/bin/XrayR /usr/bin/xrayr
    systemctl daemon-reload
    echo -e "${green}[✓] Đã xóa${plain}"
    read -p "Enter..."
}

do_manage() {
    while true; do
        header
        echo -e "${cyan}1${plain}=Start ${cyan}2${plain}=Stop ${cyan}3${plain}=Restart ${cyan}4${plain}=Log ${cyan}0${plain}=Exit"
        echo -ne "${green}Chọn: ${plain}"
        read -r m
        case "$m" in
            1) systemctl start XrayR ; sleep 1 ;;
            2) systemctl stop XrayR ; sleep 1 ;;
            3) systemctl restart XrayR ; sleep 1 ;;
            4) journalctl -u XrayR -n 50 -f ;;
            0) return ;;
        esac
    done
}

main() {
    check_root
    while true; do
        header
        echo -e "${cyan}1${plain}=Cài ${cyan}2${plain}=Quản lý ${cyan}3${plain}=Gỡ ${cyan}0${plain}=Thoát"
        echo -ne "${green}Chọn: ${plain}"
        read -r opt
        case "$opt" in
            1) do_install ;;
            2) do_manage ;;
            3) do_uninstall ;;
            0) exit 0 ;;
        esac
    done
}

main