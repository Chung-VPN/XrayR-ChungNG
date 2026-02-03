#!/bin/bash
#============================================================
#   XrayR Auto Install — V2Board

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

# Alternative mirrors for GitHub downloads
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
            apt-get install -y -qq curl wget unzip tar > /dev/null 2>&1 ;;
        centos)
            yum install -y -q curl wget unzip tar > /dev/null 2>&1 ;;
    esac
    echo -e "${green}[✓] OK${plain}"
}

# Hàm lấy version với fallback
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
    
    echo -e "${green}[✓] Version: $last_version  |  Kiến trúc: $arch${plain}"
}

# Hàm download với retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retry=3
    local retry=0
    
    while [ $retry -lt $max_retry ]; do
        echo -e "${blue}[*] Tải xuống (lần $((retry+1))/$max_retry)...${plain}"
        
        if wget -q --show-progress --timeout=30 --tries=2 --no-check-certificate -O "$output" "$url" 2>&1; then
            if [[ -s "$output" ]]; then
                echo -e "${green}[✓] Tải thành công${plain}"
                return 0
            fi
        fi
        
        retry=$((retry+1))
        [[ $retry -lt $max_retry ]] && echo -e "${yellow}[!] Thử lại sau 2s...${plain}" && sleep 2
    done
    
    echo -e "${red}[✗] Tải thất bại sau $max_retry lần thử${plain}"
    return 1
}

install_binary() {
    get_latest_version
    
    mkdir -p "$XRAYR_DIR"
    local filename="XrayR-linux-${arch}.zip"
    local zipfile="$XRAYR_DIR/XrayR-linux.zip"
    local download_success=false
    
    # Thử download từ các mirrors
    for mirror in "${GITHUB_MIRRORS[@]}"; do
        local url="${mirror}/XrayR-project/XrayR/releases/download/${last_version}/${filename}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        echo -e "${cyan}[*] Đang thử mirror: ${mirror}${plain}"
        echo -e "${cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
        
        # Xóa file cũ nếu có
        rm -f "$zipfile"
        
        if download_with_retry "$url" "$zipfile"; then
            # Kiểm tra file có phải zip hợp lệ không
            echo -e "${blue}[*] Kiểm tra file tải về...${plain}"
            
            # Kiểm tra size file (phải > 1MB)
            local filesize=$(stat -c%s "$zipfile" 2>/dev/null || stat -f%z "$zipfile" 2>/dev/null)
            if [[ -z "$filesize" ]] || [[ "$filesize" -lt 1048576 ]]; then
                echo -e "${yellow}[!] File quá nhỏ ($filesize bytes), có thể bị lỗi${plain}"
                continue
            fi
            
            # Kiểm tra file type
            if command -v file >/dev/null 2>&1; then
                local filetype=$(file -b "$zipfile")
                if [[ ! "$filetype" =~ [Zz]ip ]]; then
                    echo -e "${yellow}[!] File không phải định dạng ZIP: $filetype${plain}"
                    echo -e "${yellow}[!] Có thể là HTML error page hoặc file lỗi${plain}"
                    continue
                fi
            fi
            
            # Thử test unzip
            if ! unzip -t "$zipfile" >/dev/null 2>&1; then
                echo -e "${yellow}[!] File ZIP bị lỗi hoặc không đầy đủ${plain}"
                continue
            fi
            
            echo -e "${green}[✓] File hợp lệ (${filesize} bytes)${plain}"
            download_success=true
            break
        fi
        
        echo -e "${yellow}[!] Mirror này không hoạt động, thử mirror tiếp theo...${plain}"
        echo ""
    done
    
    if ! $download_success; then
        echo -e "${red}╔════════════════════════════════════════════════════════╗${plain}"
        echo -e "${red}║  [✗] TẤT CẢ MIRROR ĐỀU THẤT BẠI                       ║${plain}"
        echo -e "${red}╠════════════════════════════════════════════════════════╣${plain}"
        echo -e "${red}║  Nguyên nhân có thể:                                   ║${plain}"
        echo -e "${red}║  • GitHub bị chặn từ VPS của bạn                       ║${plain}"
        echo -e "${red}║  • Firewall/Security Group chặn kết nối ra ngoài       ║${plain}"
        echo -e "${red}║  • VPS chặn download file .zip                         ║${plain}"
        echo -e "${red}║  • Vấn đề DNS resolution                               ║${plain}"
        echo -e "${red}║                                                        ║${plain}"
        echo -e "${red}║  Cách khắc phục:                                       ║${plain}"
        echo -e "${yellow}║  1. Kiểm tra kết nối: ping github.com                  ║${plain}"
        echo -e "${yellow}║  2. Kiểm tra firewall của VPS                          ║${plain}"
        echo -e "${yellow}║  3. Thử download trực tiếp bằng tar.gz:                ║${plain}"
        echo -e "${yellow}║     wget https://github.com/XrayR-project/XrayR/\\     ║${plain}"
        echo -e "${yellow}║     releases/download/${last_version}/\\               ║${plain}"
        echo -e "${yellow}║     XrayR-linux-${arch}.tar.gz                         ║${plain}"
        echo -e "${yellow}║     tar -xzf XrayR-linux-${arch}.tar.gz                ║${plain}"
        echo -e "${red}╚════════════════════════════════════════════════════════╝${plain}"
        
        # Hiển thị thông tin debug nếu file tồn tại
        if [[ -f "$zipfile" ]]; then
            echo -e "${yellow}[DEBUG] File đã tải: $zipfile${plain}"
            ls -lh "$zipfile"
            echo -e "${yellow}[DEBUG] File type:${plain}"
            file "$zipfile" 2>/dev/null || echo "Không có lệnh 'file'"
            echo -e "${yellow}[DEBUG] 100 bytes đầu:${plain}"
            head -c 100 "$zipfile" | xxd 2>/dev/null || hexdump -C "$zipfile" | head -5
        fi
        
        return 1
    fi
    
    cd "$XRAYR_DIR"
    echo -e "${blue}[*] Giải nén file...${plain}"
    
    # Giải nén với output để debug
    if ! unzip -o "$zipfile" 2>&1 | grep -v "Archive:"; then
        echo -e "${red}[✗] Giải nén thất bại!${plain}"
        echo -e "${yellow}[DEBUG] Nội dung thư mục:${plain}"
        ls -lah "$XRAYR_DIR"
        return 1
    fi
    
    rm -f "$zipfile"
    
    # Kiểm tra file XrayR có tồn tại không
    if [[ ! -f "$XRAYR_BIN" ]]; then
        echo -e "${red}[✗] Không tìm thấy binary XrayR sau khi giải nén!${plain}"
        echo -e "${yellow}[DEBUG] Files trong $XRAYR_DIR:${plain}"
        ls -lah "$XRAYR_DIR"
        return 1
    fi
    
    chmod +x "$XRAYR_BIN"
    
    # Kiểm tra binary có thể chạy không
    if [[ ! -x "$XRAYR_BIN" ]]; then
        echo -e "${red}[✗] Binary không có quyền thực thi!${plain}"
        return 1
    fi
    
    # Thử chạy version check
    if "$XRAYR_BIN" version >/dev/null 2>&1; then
        local installed_ver=$("$XRAYR_BIN" version 2>/dev/null | head -1)
        echo -e "${green}[✓] Binary OK: $installed_ver${plain}"
    else
        echo -e "${green}[✓] Binary đã cài tại: $XRAYR_BIN${plain}"
    fi
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
    echo -e "${blue}[*] Tải config.yml từ GitHub repo...${plain}"
    mkdir -p /etc/XrayR

    if ! wget -q --timeout=15 --tries=3 --no-check-certificate -O "$XRAYR_CFG" "$CONFIG_DOWNLOAD_URL"; then
        echo -e "${red}[✗] Tải config.yml thất bại!${plain}"
        echo -e "${yellow}    URL: $CONFIG_DOWNLOAD_URL${plain}"
        echo -e "${yellow}    → Kiểm tra lại repo GitHub hoặc kết nối mạng${plain}"
        return 1
    fi

    if [[ ! -s "$XRAYR_CFG" ]]; then
        echo -e "${red}[✗] File config.yml rỗng hoặc không hợp lệ!${plain}"
        return 1
    fi
    
    echo -e "${green}[✓] config.yml đã tải về${plain}"
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
    echo -e "${blue}[*] Cập nhật config.yml...${plain}"

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

    echo -e "${green}[✓] Cập nhật xong${plain}"
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
    echo -e "${green}[✓] Service đã tạo${plain}"
}

disable_fw() {
    echo -e "${blue}[*] Tắt firewall...${plain}"
    if command -v ufw &>/dev/null; then
        ufw disable > /dev/null 2>&1 ; echo -e "${green}[✓] UFW đã tắt${plain}"
    elif command -v firewall-cmd &>/dev/null; then
        systemctl stop firewalld > /dev/null 2>&1
        systemctl disable firewalld > /dev/null 2>&1
        echo -e "${green}[✓] firewalld đã tắt${plain}"
    else
        echo -e "${yellow}[—] Không có UFW / firewalld${plain}"
    fi
}

do_install() {
    header
    echo -e "${bold}${cyan}── CÀI ĐẶT ──${plain}"
    echo ""

    if is_installed; then
        echo -e "${yellow}[!] Đã cài rồi. Cài lại sẽ ghi đè.${plain}"
        echo -ne "${green} Tiếp tục? [y/N]: ${plain}"
        read -r ov ; [[ "$ov" =~ ^[Yy] ]] || return
        echo ""
    fi

    detect_os
    detect_arch
    install_deps
    install_binary       || { read -rp "$(echo -e "${cyan}Ấn Enter để tiếp tục...${plain}")" _ ; return ; }
    install_mgmt_cmd
    download_config      || { read -rp "$(echo -e "${cyan}Ấn Enter để tiếp tục...${plain}")" _ ; return ; }

    input_api_host
    input_api_key
    input_node_id
    input_node_type
    input_redis

    review || { echo -e "${yellow}\n[—] Đã hủy.${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ; return ; }

    patch_config
    create_service
    disable_fw

    # START
    echo ""
    echo -e "${blue}[*] Khởi động XrayR...${plain}"
    systemctl enable XrayR > /dev/null 2>&1
    systemctl start  XrayR
    sleep 2

    if systemctl is-active --quiet XrayR; then
        echo -e "${green}${bold}[✓✓] XrayR đang chạy!${plain}"
        echo -e "${green}     Node sẽ tự đồng bộ với V2Board panel trong vài giây.${plain}"
    else
        echo -e "${red}[✗] Chưa chạy được. Kiểm tra lỗi:${plain}"
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
    read -r yn ; [[ "$yn" =~ ^[Yy] ]] || { echo -e "${yellow}[—] Đã hủy${plain}" ; return ; }

    systemctl stop    XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -rf  "$XRAYR_DIR"  /etc/XrayR  "$XRAYR_SVC"
    rm -f   /usr/bin/XrayR  /usr/bin/xrayr
    systemctl daemon-reload 2>/dev/null

    echo -e "${green}[✓] Đã gỡ hoàn toàn.${plain}"
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
            1) systemctl start   XrayR   && echo -e "${green}[✓] Đã start${plain}"   || echo -e "${red}[✗] Lỗi${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ;;
            2) systemctl stop    XrayR   && echo -e "${green}[✓] Đã stop${plain}"    || echo -e "${red}[✗] Lỗi${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ;;
            3) systemctl restart XrayR   && echo -e "${green}[✓] Đã restart${plain}" || echo -e "${red}[✗] Lỗi${plain}" ; read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ;;
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
                echo -ne "${green} Restart để áp dụng? [y/N]: ${plain}"
                read -r rr
                [[ "$rr" =~ ^[Yy] ]] && { systemctl restart XrayR && echo -e "${green}[✓] Đã restart${plain}" || echo -e "${red}[✗] Lỗi${plain}" ; }
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