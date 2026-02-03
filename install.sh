#!/bin/bash
#============================================================
#   XrayR One-Click Install — V2Board
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

# ── PATHS ───────────────────────────────────────────────
XRAYR_DIR="/usr/local/XrayR"
XRAYR_BIN="$XRAYR_DIR/XrayR"
XRAYR_CFG="/etc/XrayR/config.yml"
XRAYR_SVC="/etc/systemd/system/XrayR.service"
XRAYR_RELEASE_SH="https://raw.githubusercontent.com/XrayR-project/XrayR-release/master/XrayR.sh"

# ── QUAN TRỌNG ──────────────────────────────────────────
# Sau khi fork repo về GitHub của bạn, thay 2 giá trị dưới đây
# bằng username và repo thật của bạn.
# config.yml trong repo đó chứa API URL + API Key của panel (đã set sẵn).
CONFIG_DOWNLOAD_URL="https://cdn.jsdelivr.net/gh/Chung-VPN/XrayR-ChungNG/config.yml"

#============================================================
#  UTILITY
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
        echo -e "  Status: ${red}● Chưa cài đặt${plain}"
    elif systemctl is-active --quiet XrayR 2>/dev/null; then
        echo -e "  Status: ${green}● Đang chạy${plain}"
    else
        echo -e "  Status: ${yellow}● Cài rồi, chưa chạy${plain}"
    fi
}

header() {
    clear
    echo -e "${cyan}============================================================${plain}"
    echo -e "${bold}${green}       XrayR One-Click Install — V2Board${plain}"
    echo -e "${cyan}============================================================${plain}"
    svc_badge
    echo ""
}

#============================================================
#  INSTALL DEPENDENCIES
#============================================================
install_deps() {
    echo -e "${blue}[*] Cài dependencies...${plain}"
    case "$release" in
        debian|ubuntu)
            apt-get update  -qq            > /dev/null 2>&1
            apt-get install -y -qq curl wget unzip > /dev/null 2>&1 ;;
        centos)
            yum install -y -q curl wget unzip > /dev/null 2>&1 ;;
    esac
    echo -e "${green}[✓] OK${plain}"
}

#============================================================
#  DOWNLOAD XrayR BINARY
#============================================================
install_binary() {
    echo -e "${blue}[*] Lấy phiên bản mới nhất...${plain}"

    last_version=$(curl -Ls "https://api.github.com/repos/XrayR-project/XrayR/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [[ -z "$last_version" ]]; then
        echo -e "${red}[✗] Không lấy được version (rate-limit?). Thử lại sau.${plain}"
        return 1
    fi
    echo -e "${green}[✓] Version: $last_version  |  Arch: $arch${plain}"

    mkdir -p "$XRAYR_DIR"
    local url="https://github.com/XrayR-project/XrayR/releases/download/${last_version}/XrayR-linux-${arch}.zip"

    echo -e "${blue}[*] Download & unzip...${plain}"
    wget -q -N --no-check-certificate -O "$XRAYR_DIR/XrayR-linux.zip" "$url" || { echo -e "${red}[✗] Download thất bại${plain}" ; return 1 ; }

    cd "$XRAYR_DIR"
    unzip -o XrayR-linux.zip > /dev/null 2>&1
    rm -f XrayR-linux.zip
    chmod +x "$XRAYR_BIN"
    echo -e "${green}[✓] Binary: $XRAYR_BIN${plain}"
}

#============================================================
#  INSTALL MANAGEMENT COMMAND
#============================================================
install_mgmt_cmd() {
    echo -e "${blue}[*] Cài lệnh quản lý (XrayR start/stop/restart/log)...${plain}"
    curl -o /usr/bin/XrayR -Ls "$XRAYR_RELEASE_SH"
    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
    echo -e "${green}[✓] Xong${plain}"
}

#============================================================
#  DOWNLOAD config.yml TỪ GITHUB CỦA BẠN
#============================================================
download_config() {
    echo -e "${blue}[*] Download config.yml...${plain}"
    mkdir -p /etc/XrayR

    wget -q --no-check-certificate -O "$XRAYR_CFG" "$CONFIG_DOWNLOAD_URL"

    if [[ ! -s "$XRAYR_CFG" ]]; then
        echo -e "${red}[✗] Download config.yml thất bại!${plain}"
        echo -e "${yellow}    URL: $CONFIG_DOWNLOAD_URL${plain}"
        echo -e "${yellow}    → Kiểm tra lại YOUR_USERNAME / YOUR_REPO trong install.sh${plain}"
        return 1
    fi
    echo -e "${green}[✓] config.yml OK${plain}"
}

#============================================================
#  INPUT WIZARD
#============================================================
input_node_id() {
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập Node ID${plain}"
    echo -e "${cyan}   (V2Board Admin → Nodes → chọn node → ID)${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   Node ID: ${plain}"
        read -r node_id
        [[ -z "$node_id" ]]          && { echo -e "${red}    [!] Không rỗng.${plain}" ; continue ; }
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
            echo -ne "${green}   Redis Address (VD 127.0.0.1:6379): ${plain}"
            read -r redis_addr
            [[ -n "$redis_addr" ]] && { echo -e "${green}    [✓] $redis_addr${plain}" ; break ; }
            echo -e "${red}    [!] Không rỗng${plain}"
        done

        # Password
        echo ""
        echo -ne "${green}   Redis Password (Enter = không có): ${plain}"
        read -r redis_pass
        [[ -z "$redis_pass" ]] && echo -e "${yellow}    [—] Không có password${plain}" || echo -e "${green}    [✓] OK${plain}"

        # DB
        echo ""
        echo -ne "${green}   Redis DB [0]: ${plain}"
        read -r redis_db ; [[ -z "$redis_db" ]] && redis_db=0
        echo -e "${green}    [✓] DB = $redis_db${plain}"

        # Timeout
        echo ""
        echo -ne "${green}   Timeout (s) [5]: ${plain}"
        read -r redis_timeout ; [[ -z "$redis_timeout" ]] && redis_timeout=5
        echo -e "${green}    [✓] Timeout = ${redis_timeout}s${plain}"

        # Expiry
        echo ""
        echo -ne "${green}   Expiry (s) [60]: ${plain}"
        read -r redis_expiry ; [[ -z "$redis_expiry" ]] && redis_expiry=60
        echo -e "${green}    [✓] Expiry = ${redis_expiry}s${plain}"
    else
        redis_on="false"
        echo -e "${yellow}    [—] Redis disable${plain}"
    fi
}

#============================================================
#  REVIEW & CONFIRM
#============================================================
review() {
    echo ""
    echo -e "${cyan}============================================================${plain}"
    echo -e "${bold}${yellow}   XÁC NHẬN TRƯỚC KHI CÀI${plain}"
    echo -e "${cyan}============================================================${plain}"
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

#============================================================
#  PATCH config.yml
#============================================================
patch_config() {
    echo ""
    echo -e "${blue}[*] Patch config.yml...${plain}"

    # NodeID & NodeType (indent 6 spaces, bên trong ApiConfig)
    sed -i -E 's/^( +)NodeID:.*$/      NodeID: '"$node_id"'/'       "$XRAYR_CFG"
    sed -i -E 's/^( +)NodeType:.*$/      NodeType: '"$node_type"'/' "$XRAYR_CFG"

    if [[ "$redis_on" == "true" ]]; then
        # Redis block indent 8 spaces (bên trong ControllerConfig → GlobalDeviceLimitConfig)
        sed -i -E '/GlobalDeviceLimitConfig/{n; s/^( +)Enable:.*$/        Enable: true/}' "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisAddr:.*$/        RedisAddr: '"$redis_addr"'/'         "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisPassword:.*$/        RedisPassword: '"$redis_pass"'/' "$XRAYR_CFG"
        sed -i -E 's/^( +)RedisDB:.*$/        RedisDB: '"$redis_db"'/'             "$XRAYR_CFG"
        # Timeout & Expiry chỉ patch bên trong block GlobalDeviceLimitConfig
        sed -i -E '/GlobalDeviceLimitConfig/,/^[^ ]/{
            s/^( +)Timeout:.*$/        Timeout: '"$redis_timeout"'/
            s/^( +)Expiry:.*$/        Expiry: '"$redis_expiry"'/
        }' "$XRAYR_CFG"
    fi

    echo -e "${green}[✓] Patch xong${plain}"
}

#============================================================
#  SYSTEMD SERVICE
#============================================================
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

#============================================================
#  DISABLE FIREWALL
#============================================================
disable_fw() {
    echo -e "${blue}[*] Tắt firewall...${plain}"
    if command -v ufw &>/dev/null; then
        ufw disable > /dev/null 2>&1 ; echo -e "${green}[✓] UFW off${plain}"
    elif command -v firewall-cmd &>/dev/null; then
        systemctl stop disable firewalld > /dev/null 2>&1 ; echo -e "${green}[✓] firewalld off${plain}"
    else
        echo -e "${yellow}[—] Không có UFW / firewalld${plain}"
    fi
}

#============================================================
#  FULL INSTALL
#============================================================
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
    install_binary       || { read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ; return ; }
    install_mgmt_cmd
    download_config      || { read -rp "$(echo -e "${cyan}Enter...${plain}")" _ ; return ; }

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

    read -rp "$(echo -e "${cyan}\nÄn Enter...${plain}")" _
}

#============================================================
#  UNINSTALL
#============================================================
do_uninstall() {
    header
    echo -e "${bold}${red}── GỡI CÀI ĐẶT ──${plain}"
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

#============================================================
#  MANAGE
#============================================================
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

#============================================================
#  MAIN
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
            *) echo -e "${red}  [!] Nhập 0–3${plain}" ;;
        esac
    done
}

main
