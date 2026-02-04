#!/bin/bash
#============================================================
#   XrayR Tự-Cài — V2Board
#   Cách dùng:
#     bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/install.sh)
#============================================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
cyan='\033[0;36m'
blue='\033[0;34m'
bold='\033[1m'
plain='\033[0m'

# ── ĐƯỜNG DẪN ───────────────────────────────────────────
XRAYR_DIR="/usr/local/XrayR"
XRAYR_BIN="$XRAYR_DIR/XrayR"
XRAYR_CFG="/etc/XrayR/config.yml"
XRAYR_SVC="/etc/systemd/system/XrayR.service"

CONFIG_DOWNLOAD_URL="https://cdn.jsdelivr.net/gh/Chung-VPN/XrayR-ChungNG@main/config.yml"

#============================================================
#  TIỆN ÍCH
#============================================================
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
    else echo -e "${red}Không phát hiện được hệ điều hành!${plain}" ; exit 1 ; fi
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
    echo -e "${bold}${green}         XrayR Tự-Cài — V2Board${plain}"
    echo -e "${cyan}============================================================${plain}"
    svc_badge
    echo ""
}

wait_key() {
    read -rp "$(echo -e "${cyan}Ấn Enter để tiếp tục...${plain}")" _
}

#============================================================
#  CÀI DEPENDENCIES
#============================================================
install_deps() {
    echo -e "${blue}[*] Cài các gói cần thiết...${plain}"
    case "$release" in
        debian|ubuntu)
            apt-get update  -qq > /dev/null 2>&1
            apt-get install -y -qq curl wget unzip > /dev/null 2>&1 ;;
        centos)
            yum install -y -q curl wget unzip > /dev/null 2>&1 ;;
    esac
    echo -e "${green}[✓] Xong${plain}"
}

#============================================================
#  TẤT FIREWALL
#============================================================
disable_fw() {
    echo -e "${blue}[*] Tắt firewall...${plain}"
    if command -v ufw &>/dev/null; then
        ufw disable > /dev/null 2>&1
        echo -e "${green}[✓] UFW đã tắt${plain}"
    elif command -v firewall-cmd &>/dev/null; then
        systemctl stop    firewalld > /dev/null 2>&1
        systemctl disable firewalld > /dev/null 2>&1
        echo -e "${green}[✓] Firewalld đã tắt${plain}"
    else
        echo -e "${yellow}[—] Không có firewall để tắt${plain}"
    fi
}

#============================================================
#  TẢI XrayR — DÙNG LINK CỐ ĐỊNH /releases/latest/download/
#============================================================
install_binary() {
    echo -e "${blue}[*] Tải XrayR phiên bản mới nhất...${plain}"
    echo -e "${blue}    Kiến trúc: $arch${plain}"

    mkdir -p "$XRAYR_DIR"
    local zip_path="$XRAYR_DIR/XrayR-linux.zip"

    # Link GitHub cố định — luôn là phiên bản mới nhất
    local url="https://github.com/XrayR-project/XrayR/releases/latest/download/XrayR-linux-${arch}.zip"

    # Danh sách mirror (GitHub → jsdelivr CDN fallback)
    local mirrors=(
        "$url"
        "https://cdn.jsdelivr.net/gh/XrayR-project/XrayR@latest/releases/XrayR-linux-${arch}.zip"
        "https://ghproxy.com/$url"
    )

    local downloaded=false

    for mirror in "${mirrors[@]}"; do
        echo -e "${blue}[*] Đang tải từ: ${mirror##*/}${plain}"

        # Thử 3 lần cho mỗi mirror
        for attempt in 1 2 3; do
            if curl -fSL --connect-timeout 15 --max-time 600 \
                    --progress-bar -o "$zip_path" "$mirror" 2>&1; then

                # Kiểm tra file có hợp lệ không
                if [[ -s "$zip_path" ]] && file "$zip_path" 2>/dev/null | grep -qi "zip\|archive"; then
                    echo -e "${green}[✓] Tải thành công (lần thử $attempt)${plain}"
                    downloaded=true
                    break 2
                else
                    echo -e "${yellow}[!] File tải về không hợp lệ, thử lại...${plain}"
                    rm -f "$zip_path"
                fi
            else
                echo -e "${yellow}[!] Lần thử $attempt/3 thất bại${plain}"
                rm -f "$zip_path"
                [ $attempt -lt 3 ] && sleep 2
            fi
        done

        echo -e "${yellow}[!] Thử mirror khác...${plain}"
    done

    if [[ "$downloaded" != true ]]; then
        echo -e "${red}[✗] Không tải được file sau khi thử tất cả mirror.${plain}"
        echo -e "${yellow}    Kiểm tra kết nối mạng Internet và thử lại.${plain}"
        return 1
    fi

    # Giải nén
    echo -e "${blue}[*] Giải nén...${plain}"
    cd "$XRAYR_DIR"

    if ! unzip -o "$zip_path" > /dev/null 2>&1; then
        echo -e "${red}[✗] Giải nén thất bại. File có thể bị hỏng.${plain}"
        rm -f "$zip_path"
        return 1
    fi

    rm -f "$zip_path"

    if [[ ! -f "$XRAYR_BIN" ]]; then
        echo -e "${red}[✗] Không tìm thấy file XrayR sau khi giải nén.${plain}"
        echo -e "${yellow}    Nội dung thư mục:${plain}"
        ls -lh "$XRAYR_DIR"
        return 1
    fi

    chmod +x "$XRAYR_BIN"
    echo -e "${green}[✓] Cài xong: $XRAYR_BIN${plain}"
}

#============================================================
#  TẢI config.yml
#============================================================
download_config() {
    echo -e "${blue}[*] Tải config.yml...${plain}"
    mkdir -p /etc/XrayR

    # Thử curl trước
    if curl -fsSL --connect-timeout 10 -o "$XRAYR_CFG" "$CONFIG_DOWNLOAD_URL" 2>/dev/null; then
        :
    # Fallback wget
    elif wget -q --no-check-certificate -O "$XRAYR_CFG" "$CONFIG_DOWNLOAD_URL" 2>/dev/null; then
        :
    fi

    if [[ ! -s "$XRAYR_CFG" ]]; then
        echo -e "${red}[✗] Tải config.yml thất bại!${plain}"
        echo -e "${yellow}    URL: $CONFIG_DOWNLOAD_URL${plain}"
        echo -e "${yellow}    → Kiểm tra YOUR_USERNAME / YOUR_REPO trong install.sh${plain}"
        return 1
    fi
    echo -e "${green}[✓] config.yml đã tải${plain}"
}

#============================================================
#  NHẬP THÔNG TIN
#============================================================
input_api_host() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập địa chỉ V2Board Panel${plain}"
    echo -e "${cyan}   VD: https://panel.example.com${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   Địa chỉ Panel: ${plain}"
        read -r api_host
        api_host="${api_host%/}"
        [[ -z "$api_host" ]]            && { echo -e "${red}    [!] Không thể rỗng.${plain}" ; continue ; }
        [[ "$api_host" =~ ^https?:// ]] && { echo -e "${green}    [✓] $api_host${plain}" ; break ; }
        echo -e "${red}    [!] Phải bắt đầu bằng http:// hoặc https://${plain}"
    done
}

input_api_key() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập API Key${plain}"
    echo -e "${cyan}   (V2Board → Cài đặt → API)${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   API Key: ${plain}"
        read -r api_key
        [[ -z "$api_key" ]] && { echo -e "${red}    [!] Không thể rỗng.${plain}" ; continue ; }
        echo -e "${green}    [✓] Đã nhập${plain}"
        break
    done
}

input_node_id() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập Node ID${plain}"
    echo -e "${cyan}   (V2Board → Quản lý Nút → chọn nút → ID)${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   Node ID: ${plain}"
        read -r node_id
        [[ -z "$node_id" ]]          && { echo -e "${red}    [!] Không thể rỗng.${plain}" ; continue ; }
        [[ "$node_id" =~ ^[0-9]+$ ]] && { echo -e "${green}    [✓] Node ID = $node_id${plain}" ; break ; }
        echo -e "${red}    [!] Chỉ nhập số.${plain}"
    done
}

input_node_type() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Chọn giao thức${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "    ${cyan}1${plain}  VMESS / VLESS"
    echo -e "    ${cyan}2${plain}  Trojan"
    echo -e "    ${cyan}3${plain}  Shadowsocks"
    echo ""
    echo -e "  ${blue}💡 VMESS và VLESS đều chọn mục 1.${plain}"
    echo -e "  ${blue}   Nếu nút là VLESS → sau cài đổi EnableVless: true trong config.yml.${plain}"
    echo ""
    while true; do
        echo -ne "${green}   Chọn [1/2/3]: ${plain}"
        read -r ch
        case "$ch" in
            1) node_type="V2ray"       ; echo -e "${green}    [✓] VMESS / VLESS${plain}"  ; break ;;
            2) node_type="Trojan"      ; echo -e "${green}    [✓] Trojan${plain}"         ; break ;;
            3) node_type="Shadowsocks" ; echo -e "${green}    [✓] Shadowsocks${plain}"    ; break ;;
            *) echo -e "${red}    [!] Chỉ nhập 1, 2 hoặc 3.${plain}" ;;
        esac
    done
}

input_redis() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Giới hạn số thiết bị (Redis)${plain}"
    echo -e "${cyan}   Khóa 1 tài khoản chỉ đăng nhập được N máy${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -ne "${green}   Bạn có Redis không? [y/N]: ${plain}"
    read -r re

    if [[ "$re" =~ ^[Yy] ]]; then
        redis_on="true"
        echo ""

        while true; do
            echo -ne "${green}   Địa chỉ Redis (VD 127.0.0.1:6379): ${plain}"
            read -r redis_addr
            [[ -n "$redis_addr" ]] && { echo -e "${green}    [✓] $redis_addr${plain}" ; break ; }
            echo -e "${red}    [!] Không thể rỗng${plain}"
        done

        echo ""
        echo -ne "${green}   Mật khẩu Redis (Enter = không có): ${plain}"
        read -r redis_pass
        [[ -z "$redis_pass" ]] && echo -e "${yellow}    [—] Không có mật khẩu${plain}" || echo -e "${green}    [✓] Đã nhập${plain}"

        echo ""
        echo -ne "${green}   Redis DB [0]: ${plain}"
        read -r redis_db ; [[ -z "$redis_db" ]] && redis_db=0
        echo -e "${green}    [✓] DB = $redis_db${plain}"

        echo ""
        echo -ne "${green}   Thời gian chờ — Timeout (giây) [5]: ${plain}"
        read -r redis_timeout ; [[ -z "$redis_timeout" ]] && redis_timeout=5
        echo -e "${green}    [✓] Timeout = ${redis_timeout}s${plain}"

        echo ""
        echo -ne "${green}   Thời gian hết hạn — Expiry (giây) [60]: ${plain}"
        read -r redis_expiry ; [[ -z "$redis_expiry" ]] && redis_expiry=60
        echo -e "${green}    [✓] Expiry = ${redis_expiry}s${plain}"
    else
        redis_on="false"
        echo -e "${yellow}    [—] Bỏ qua giới hạn thiết bị${plain}"
    fi
}

#============================================================
#  XÁC NHẬN
#============================================================
review() {
    echo ""
    echo -e "${cyan}============================================================${plain}"
    echo -e "${bold}${yellow}   XÁC NHẬN THÔNG TIN${plain}"
    echo -e "${cyan}============================================================${plain}"
    echo -e "   ${yellow}Địa chỉ Panel :${plain} $api_host"
    echo -e "   ${yellow}API Key        :${plain} $(echo "$api_key" | sed 's/.\{4\}/****/')"
    echo -e "   ${yellow}Node ID        :${plain} $node_id"
    echo -e "   ${yellow}Giao thức      :${plain} $node_type"
    [[ "$node_type" == "V2ray" ]] && echo -e "   ${blue}   → Nếu VLESS nhớ đổi EnableVless: true sau cài${plain}"
    echo -e "   ${yellow}Giới hạn máy   :${plain} $redis_on"
    if [[ "$redis_on" == "true" ]]; then
        echo -e "     ${yellow}Địa chỉ Redis :${plain} $redis_addr"
        echo -e "     ${yellow}DB            :${plain} $redis_db"
        echo -e "     ${yellow}Timeout       :${plain} ${redis_timeout}s"
        echo -e "     ${yellow}Expiry        :${plain} ${redis_expiry}s"
    fi
    echo -e "${cyan}============================================================${plain}"
    echo ""
    echo -ne "${green}   Thông tin đúng rồi? Tiếp tục cài? [y/N]: ${plain}"
    read -r c
    [[ "$c" =~ ^[Yy] ]]
}

#============================================================
#  PATCH config.yml
#============================================================
patch_config() {
    echo ""
    echo -e "${blue}[*] Ghi cấu hình vào config.yml...${plain}"

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

    echo -e "${green}[✓] Ghi xong${plain}"
}

#============================================================
#  TẠO SYSTEMD SERVICE
#============================================================
create_service() {
    echo -e "${blue}[*] Tạo dịch vụ hệ thống...${plain}"
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
    echo -e "${green}[✓] Dịch vụ đã tạo${plain}"
}

#============================================================
#  CÀI ĐẶT
#============================================================
do_install() {
    header
    echo -e "${bold}${cyan}── CÀI ĐẶT XrayR ──${plain}"
    echo ""

    if is_installed; then
        echo -e "${yellow}[!] XrayR đã được cài rồi. Cài lại sẽ ghi đè.${plain}"
        echo -ne "${green}    Tiếp tục? [y/N]: ${plain}"
        read -r ov ; [[ "$ov" =~ ^[Yy] ]] || return
        echo ""
    fi

    detect_os
    detect_arch
    install_deps
    disable_fw
    install_binary       || { wait_key ; return ; }
    download_config      || { wait_key ; return ; }

    input_api_host
    input_api_key
    input_node_id
    input_node_type
    input_redis

    review || { echo -e "${yellow}\n[—] Hủy cài đặt.${plain}" ; wait_key ; return ; }

    patch_config
    create_service

    echo ""
    echo -e "${blue}[*] Khởi động XrayR...${plain}"
    systemctl enable XrayR > /dev/null 2>&1
    systemctl start  XrayR
    sleep 2

    if systemctl is-active --quiet XrayR; then
        echo -e "${green}${bold}[✓✓] XrayR đang chạy thành công!${plain}"
        echo -e "${green}     Nút sẽ tự đồng bộ với V2Board panel trong vài giây.${plain}"
    else
        echo -e "${red}[✗] XrayR chưa chạy được. Kiểm tra log bằng:${plain}"
        echo -e "${yellow}    Chọn mục 2 → 5 (Xem thông tin lỗi)${plain}"
        systemctl status XrayR --no-pager 2>/dev/null || true
    fi

    wait_key
}

#============================================================
#  GỠ CÀI ĐẶT
#============================================================
do_uninstall() {
    header
    echo -e "${bold}${red}── GỠ CÀI ĐẶT XrayR ──${plain}"
    echo ""
    if ! is_installed; then
        echo -e "${yellow}[!] XrayR chưa được cài đặt.${plain}"
        wait_key ; return
    fi

    echo -e "${red}  Sẽ xóa:${plain}"
    echo -e "${red}    • $XRAYR_DIR${plain}"
    echo -e "${red}    • /etc/XrayR/${plain}"
    echo -e "${red}    • Dịch vụ systemd${plain}"
    echo ""
    echo -ne "${green}  Xác nhận gỡ cài đặt? [y/N]: ${plain}"
    read -r yn ; [[ "$yn" =~ ^[Yy] ]] || { echo -e "${yellow}[—] Hủy${plain}" ; return ; }

    systemctl stop    XrayR 2>/dev/null
    systemctl disable XrayR 2>/dev/null
    rm -rf  "$XRAYR_DIR"  /etc/XrayR  "$XRAYR_SVC"
    systemctl daemon-reload 2>/dev/null

    echo -e "${green}[✓] Đã gỡ cài đặt hoàn toàn.${plain}"
    wait_key
}

#============================================================
#  QUẢN LÝ
#============================================================
do_manage() {
    while true; do
        header
        echo -e "${bold}${cyan}── QUẢN LÝ XrayR ──${plain}"
        echo ""
        echo -e "  ${cyan}1${plain}  Khởi động          ${cyan}4${plain}  Xem trạng thái"
        echo -e "  ${cyan}2${plain}  Dừng               ${cyan}5${plain}  Xem thông tin lỗi"
        echo -e "  ${cyan}3${plain}  Khởi động lại      ${cyan}6${plain}  Sửa config.yml"
        echo -e "  ${cyan}0${plain}  Quay về"
        echo ""
        echo -ne "${green}  Chọn: ${plain}"
        read -r m

        case "$m" in
            1)
                systemctl start XrayR
                if systemctl is-active --quiet XrayR; then
                    echo -e "${green}[✓] Đã khởi động${plain}"
                else
                    echo -e "${red}[✗] Khởi động thất bại${plain}"
                fi
                wait_key ;;
            2)
                systemctl stop XrayR && echo -e "${green}[✓] Đã dừng${plain}" || echo -e "${red}[✗] Dừng thất bại${plain}"
                wait_key ;;
            3)
                systemctl restart XrayR
                if systemctl is-active --quiet XrayR; then
                    echo -e "${green}[✓] Đã khởi động lại${plain}"
                else
                    echo -e "${red}[✗] Khởi động lại thất bại${plain}"
                fi
                wait_key ;;
            4)
                echo ""
                systemctl status XrayR --no-pager || true
                wait_key ;;
            5)
                echo ""
                if [[ -f /var/log/XrayR/error.log ]]; then
                    echo -e "${yellow}── Nội dung lỗi (error.log) ──${plain}"
                    tail -n 80 /var/log/XrayR/error.log
                else
                    echo -e "${yellow}── Thông tin từ systemd ──${plain}"
                    journalctl -u XrayR --no-pager -n 80
                fi
                wait_key ;;
            6)
                echo ""
                echo -e "${blue}[*] Mở config.yml để sửa...${plain}"
                command -v nano &>/dev/null && nano "$XRAYR_CFG" || vi "$XRAYR_CFG"
                echo ""
                echo -ne "${green}   Khởi động lại để áp dụng thay đổi? [y/N]: ${plain}"
                read -r rr
                if [[ "$rr" =~ ^[Yy] ]]; then
                    systemctl restart XrayR
                    if systemctl is-active --quiet XrayR; then
                        echo -e "${green}[✓] Đã khởi động lại${plain}"
                    else
                        echo -e "${red}[✗] Khởi động lại thất bại — kiểm tra config.yml${plain}"
                    fi
                fi
                wait_key ;;
            0) return ;;
            *) echo -e "${red}[!] Chỉ nhập 0–6${plain}" ;;
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
            *) echo -e "${red}  [!] Chỉ nhập 0–3${plain}" ;;
        esac
    done
}

main