#!/bin/bash
#============================================================
#   XrayR Tự-Cài — V2Board (HỖ TRỢ 2 NODE TRÊN 1 VPS)
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
    echo -e "${bold}${green}    XrayR Tự-Cài — V2Board (2 NODE / 1 VPS)${plain}"
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
#  NHẬP THÔNG TIN CHO NODE
#============================================================
input_node_config() {
    local node_num=$1  # 1 hoặc 2
    
    echo ""
    echo -e "${cyan}╔═══════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║         CẤU HÌNH NODE ${node_num}                  ║${plain}"
    echo -e "${cyan}╚═══════════════════════════════════════════╝${plain}"
    
    # API Host
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập địa chỉ V2Board Panel${plain}"
    echo -e "${cyan}   VD: https://panel.example.com${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   Địa chỉ Panel: ${plain}"
        read -r api_host_tmp
        api_host_tmp="${api_host_tmp%/}"
        [[ -z "$api_host_tmp" ]] && { echo -e "${red}    [!] Không thể rỗng.${plain}" ; continue ; }
        [[ ! "$api_host_tmp" =~ ^https?:// ]] && { echo -e "${red}    [!] Cần có http:// hoặc https://${plain}" ; continue ; }
        break
    done
    
    if [[ $node_num -eq 1 ]]; then
        api_host_node1="$api_host_tmp"
    else
        api_host_node2="$api_host_tmp"
    fi
    
    # API Key
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập API Key${plain}"
    echo -e "${cyan}   Lấy từ: V2Board → Settings → API${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   API Key: ${plain}"
        read -r api_key_tmp
        [[ -z "$api_key_tmp" ]] && { echo -e "${red}    [!] Không thể rỗng.${plain}" ; continue ; }
        break
    done
    
    if [[ $node_num -eq 1 ]]; then
        api_key_node1="$api_key_tmp"
    else
        api_key_node2="$api_key_tmp"
    fi
    
    # Node ID
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Nhập Node ID${plain}"
    echo -e "${cyan}   Lấy từ: V2Board → Nodes → Node ID${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   Node ID: ${plain}"
        read -r node_id_tmp
        [[ ! "$node_id_tmp" =~ ^[0-9]+$ ]] && { echo -e "${red}    [!] Chỉ nhập số.${plain}" ; continue ; }
        break
    done
    
    if [[ $node_num -eq 1 ]]; then
        node_id_node1="$node_id_tmp"
    else
        node_id_node2="$node_id_tmp"
    fi
    
    # Node Type
    echo ""
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    echo -e "${yellow}   Chọn loại Node${plain}"
    echo -e "${cyan}   1) V2ray   2) Trojan   3) Shadowsocks${plain}"
    echo -e "${cyan}  ───────────────────────────────────────${plain}"
    while true; do
        echo -ne "${green}   Chọn [1-3]: ${plain}"
        read -r nt_choice
        case "$nt_choice" in
            1) node_type_tmp="V2ray" ; break ;;
            2) node_type_tmp="Trojan" ; break ;;
            3) node_type_tmp="Shadowsocks" ; break ;;
            *) echo -e "${red}    [!] Chỉ nhập 1, 2 hoặc 3.${plain}" ;;
        esac
    done
    
    if [[ $node_num -eq 1 ]]; then
        node_type_node1="$node_type_tmp"
    else
        node_type_node2="$node_type_tmp"
    fi
}

#============================================================
#  NHẬP REDIS (CHUNG CHO CẢ 2 NODE)
#============================================================
input_redis() {
    echo ""
    echo -e "${cyan}╔═══════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║         CẤU HÌNH REDIS (CHUNG)            ║${plain}"
    echo -e "${cyan}╚═══════════════════════════════════════════╝${plain}"
    echo ""
    echo -e "${yellow}Bật GlobalDeviceLimit qua Redis?${plain}"
    echo -e "${cyan}(Giới hạn số thiết bị đồng thời trên nhiều node)${plain}"
    echo -ne "${green}[y/N]: ${plain}"
    read -r redis_choice
    
    if [[ "$redis_choice" =~ ^[Yy] ]]; then
        redis_on="true"
        
        echo ""
        echo -ne "${green}Redis Addr (VD: 127.0.0.1:6379): ${plain}"
        read -r redis_addr
        [[ -z "$redis_addr" ]] && redis_addr="127.0.0.1:6379"
        
        echo -ne "${green}Redis Password (bỏ trống nếu không có): ${plain}"
        read -r redis_pass
        [[ -z "$redis_pass" ]] && redis_pass='""'
        
        echo -ne "${green}Redis Timeout (giây, mặc định 5): ${plain}"
        read -r redis_timeout
        [[ -z "$redis_timeout" ]] && redis_timeout=5
        
        echo -ne "${green}Redis Expiry (giây, mặc định 60): ${plain}"
        read -r redis_expiry
        [[ -z "$redis_expiry" ]] && redis_expiry=60
    else
        redis_on="false"
    fi
}

#============================================================
#  XEM LẠI CẤU HÌNH
#============================================================
review() {
    echo ""
    echo -e "${cyan}╔═══════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║         XEM LẠI CẤU HÌNH                  ║${plain}"
    echo -e "${cyan}╚═══════════════════════════════════════════╝${plain}"
    
    if [[ "$install_mode" == "both" ]] || [[ "$install_mode" == "node1" ]]; then
        echo ""
        echo -e "${bold}${green}NODE 1:${plain}"
        echo -e "  Panel URL:  ${cyan}$api_host_node1${plain}"
        echo -e "  API Key:    ${cyan}${api_key_node1:0:20}...${plain}"
        echo -e "  Node ID:    ${cyan}$node_id_node1${plain}"
        echo -e "  Node Type:  ${cyan}$node_type_node1${plain}"
    fi
    
    if [[ "$install_mode" == "both" ]] || [[ "$install_mode" == "node2" ]]; then
        echo ""
        echo -e "${bold}${green}NODE 2:${plain}"
        echo -e "  Panel URL:  ${cyan}$api_host_node2${plain}"
        echo -e "  API Key:    ${cyan}${api_key_node2:0:20}...${plain}"
        echo -e "  Node ID:    ${cyan}$node_id_node2${plain}"
        echo -e "  Node Type:  ${cyan}$node_type_node2${plain}"
    fi
    
    echo ""
    echo -e "${bold}${green}REDIS:${plain}"
    if [[ "$redis_on" == "true" ]]; then
        echo -e "  Enable:     ${cyan}true${plain}"
        echo -e "  Addr:       ${cyan}$redis_addr${plain}"
        echo -e "  Timeout:    ${cyan}${redis_timeout}s${plain}"
        echo -e "  Expiry:     ${cyan}${redis_expiry}s${plain}"
    else
        echo -e "  Enable:     ${cyan}false${plain}"
    fi
    
    echo ""
    echo -ne "${green}Xác nhận cấu hình? [y/N]: ${plain}"
    read -r confirm
    [[ "$confirm" =~ ^[Yy] ]]
}

#============================================================
#  GHI CẤU HÌNH VÀO config.yml
#============================================================
patch_config() {
    echo ""
    echo -e "${blue}[*] Ghi cấu hình vào config.yml...${plain}"
    
    # Backup
    cp "$XRAYR_CFG" "$XRAYR_CFG.backup"
    
    # Cập nhật Node 1 (node đầu tiên trong file)
    if [[ "$install_mode" == "both" ]] || [[ "$install_mode" == "node1" ]]; then
        # Tìm dòng đầu tiên của Node 1 (YOUR_PANEL_URL_NODE1)
        sed -i "0,/YOUR_PANEL_URL_NODE1/s|YOUR_PANEL_URL_NODE1|$api_host_node1|" "$XRAYR_CFG"
        sed -i "0,/YOUR_API_KEY_NODE1/s|YOUR_API_KEY_NODE1|$api_key_node1|" "$XRAYR_CFG"
        
        # Tìm NodeID và NodeType đầu tiên (của Node 1)
        sed -i "0,/NodeID: 1/s|NodeID: 1|NodeID: $node_id_node1|" "$XRAYR_CFG"
        sed -i "0,/NodeType: V2ray/s|NodeType: V2ray|NodeType: $node_type_node1|" "$XRAYR_CFG"
    fi
    
    # Cập nhật Node 2 (node thứ hai trong file)
    if [[ "$install_mode" == "both" ]] || [[ "$install_mode" == "node2" ]]; then
        # Tìm dòng thứ hai của Node 2 (YOUR_PANEL_URL_NODE2)
        sed -i "0,/YOUR_PANEL_URL_NODE2/s|YOUR_PANEL_URL_NODE2|$api_host_node2|" "$XRAYR_CFG"
        sed -i "0,/YOUR_API_KEY_NODE2/s|YOUR_API_KEY_NODE2|$api_key_node2|" "$XRAYR_CFG"
        
        # Tìm NodeID và NodeType thứ hai (của Node 2)
        sed -i "0,/NodeID: 2/s|NodeID: 2|NodeID: $node_id_node2|" "$XRAYR_CFG"
        sed -i "0,/NodeType: Trojan/s|NodeType: Trojan|NodeType: $node_type_node2|" "$XRAYR_CFG"
    fi
    
    # Cập nhật Redis cho cả 2 node nếu bật
    if [[ "$redis_on" == "true" ]]; then
        # Enable Redis cho Node 1 (lần xuất hiện đầu tiên)
        sed -i "0,/Enable: false.*# ← Script/s|Enable: false.*# ← Script.*|Enable: true                     # ← Script tự đổi thành true nếu enable Redis|" "$XRAYR_CFG"
        # Enable Redis cho Node 2 (lần xuất hiện thứ hai)
        sed -i "0,/Enable: false.*# ← Script/s|Enable: false.*# ← Script.*|Enable: true                     # ← Script tự đổi thành true nếu enable Redis|" "$XRAYR_CFG"
        
        # Cập nhật RedisAddr, RedisPassword, v.v. cho cả 2 node
        sed -i "s|RedisAddr: 127.0.0.1:6379.*|RedisAddr: $redis_addr|g" "$XRAYR_CFG"
        
        if [[ "$redis_pass" != '""' ]]; then
            sed -i "s|RedisPassword:.*# ← Script|RedisPassword: $redis_pass       # ← Script|g" "$XRAYR_CFG"
        fi
        
        sed -i "s|Timeout: 5.*# ← Script|Timeout: $redis_timeout                        # ← Script|g" "$XRAYR_CFG"
        sed -i "s|Expiry: 60.*# ← Script|Expiry: $redis_expiry                        # ← Script|g" "$XRAYR_CFG"
    fi
    
    # Xóa node không dùng
    if [[ "$install_mode" == "node1" ]]; then
        # Xóa Node 2 khỏi config
        sed -i '/# ====== NODE 2 ======/,$ d' "$XRAYR_CFG"
    elif [[ "$install_mode" == "node2" ]]; then
        # Xóa Node 1, giữ Node 2
        # Tìm dòng "# ====== NODE 2 ======" và xóa từ "Nodes:" đến trước dòng này
        awk '/# ====== NODE 2 ======/{flag=1} flag; !flag && /^Nodes:/{print; getline; next}' "$XRAYR_CFG" > "$XRAYR_CFG.tmp"
        mv "$XRAYR_CFG.tmp" "$XRAYR_CFG"
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
Description=XrayR V2Board Multi-Node
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

    # Chọn chế độ cài đặt
    echo -e "${cyan}╔═══════════════════════════════════════════╗${plain}"
    echo -e "${cyan}║       CHỌN CHẾ ĐỘ CÀI ĐẶT                ║${plain}"
    echo -e "${cyan}╚═══════════════════════════════════════════╝${plain}"
    echo ""
    echo -e "  ${green}1${plain}  Cài cả 2 node (Node 1 + Node 2)"
    echo -e "  ${green}2${plain}  Chỉ cài Node 1"
    echo -e "  ${green}3${plain}  Chỉ cài Node 2"
    echo ""
    
    while true; do
        echo -ne "${green}  Chọn [1-3]: ${plain}"
        read -r mode_choice
        case "$mode_choice" in
            1) install_mode="both" ; break ;;
            2) install_mode="node1" ; break ;;
            3) install_mode="node2" ; break ;;
            *) echo -e "${red}  [!] Chỉ nhập 1, 2 hoặc 3${plain}" ;;
        esac
    done

    detect_os
    detect_arch
    install_deps
    disable_fw
    install_binary       || { wait_key ; return ; }
    download_config      || { wait_key ; return ; }

    # Nhập thông tin cho từng node
    if [[ "$install_mode" == "both" ]]; then
        input_node_config 1
        input_node_config 2
    elif [[ "$install_mode" == "node1" ]]; then
        input_node_config 1
    else
        input_node_config 2
    fi
    
    input_redis

    review || { echo -e "${yellow}\n[—] Hủy cài đặt.${plain}" ; wait_key ; return ; }

    patch_config
    create_service

    echo ""
    echo -e "${blue}[*] Khởi động XrayR...${plain}"
    systemctl enable XrayR > /dev/null 2>&1
    systemctl start  XrayR
    sleep 3

    if systemctl is-active --quiet XrayR; then
        echo -e "${green}${bold}[✓✓] XrayR đang chạy thành công!${plain}"
        if [[ "$install_mode" == "both" ]]; then
            echo -e "${green}     Cả 2 node sẽ tự đồng bộ với V2Board panel trong vài giây.${plain}"
        else
            echo -e "${green}     Node sẽ tự đồng bộ với V2Board panel trong vài giây.${plain}"
        fi
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
    read -r yn ; [[ "$yn" =~ ^[Yy] ]] || { echo -e "${yellow}[—] Hủy${plain}" ; wait_key ; return ; }

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
            *) echo -e "${red}[!] Chỉ nhập 0–6${plain}" ; wait_key ;;
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
            *) echo -e "${red}  [!] Chỉ nhập 0–3${plain}" ; wait_key ;;
        esac
    done
}

main
