#!/bin/sh
# 系统初始化工具集（Alpine 源优化版）- 适配bash/ash/sh + 62种Linux发行版
# 核心改进：Alpine系统自动备份并替换apk源为清华源，其他系统不变
# ==================== 基础配置（全局通用） ====================
# 颜色定义（POSIX兼容）
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
GRAY="\033[90m"
RED="\033[31m"
YELLOW="\033[33m"
# 核心参数
DISTRO_FULLNAME=""
DISTRO_FAMILY=""
PKG_CMD=""
PKG_INSTALL=""
SSH_CONFIG="/etc/ssh/sshd_config"
MIRROR_SCRIPT_URL="https://linuxmirrors.cn/main.sh"
TMOE_SCRIPT_CMD='bash -c "$(/usr/local/lm/curl -L l.tmoe.me)"'
# 工具路径（优先busybox，无则空）
BB="/usr/local/lm/busybox"
if command -v busybox >/dev/null 2>&1; then
    BB="busybox"
fi
# ==================== 通用输入函数（替代read，无busybox依赖） ====================
get_input() {
    local prompt="$1"
    local output_var="$2"
    local input=""
    
    if [ -n "$prompt" ]; then
        printf "%b" "$prompt"
    fi
    
    if command -v read >/dev/null 2>&1; then
        read -r input
    else
        input=$(cat)
    fi
    
    eval "$output_var='$input'"
    return 0
}
# ==================== 工具函数（POSIX标准实现） ====================
# 初始化发行版信息
init_distro() {
    [ -n "$DISTRO_FAMILY" ] && return 0
    printf "%b" "${BOLD}【工具】检测系统发行版...${RESET}"
    local os_release="/etc/os-release"
    local distro_name=""
    local distro_version=""
    local distro_codename=""
    
    if [ ! -f "$os_release" ]; then
        printf "%b\n" "\n${RED}❌ 检测失败：未找到 $os_release 文件，不支持当前系统${RESET}" >&2
        return 1
    fi
    
    if [ -n "$BB" ]; then
        distro_name=$($BB grep -E '^NAME=' "$os_release" | $BB cut -d'=' -f2- | $BB sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
        distro_version=$($BB grep -E '^VERSION_ID=' "$os_release" | $BB cut -d'=' -f2- | $BB sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
        distro_codename=$($BB grep -E '^VERSION_CODENAME=' "$os_release" | $BB cut -d'=' -f2- | $BB sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
    else
        distro_name=$(grep -E '^NAME=' "$os_release" | cut -d'=' -f2- | sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
        distro_version=$(grep -E '^VERSION_ID=' "$os_release" | cut -d'=' -f2- | sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
        distro_codename=$(grep -E '^VERSION_CODENAME=' "$os_release" | cut -d'=' -f2- | sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
    fi
    
    if [ -n "$distro_codename" ]; then
        DISTRO_FULLNAME="$distro_name $distro_version($distro_codename)"
    else
        DISTRO_FULLNAME="$distro_name $distro_version"
    fi
    
    # 绑定发行版家族
    case "$distro_name" in
        "Debian GNU/Linux" | "Kali GNU/Linux" | "Deepin" | "Ubuntu" | "OpenKylin" | \
        "Devuan GNU/Linux" | "BackBox Linux" | "Parrot Security")
            DISTRO_FAMILY="debian"
            PKG_CMD="apt-get update -y"
            PKG_INSTALL="apt-get install -y"
            ;;
        "CentOS Linux" | "AlmaLinux" | "Rocky Linux" | "openEuler" | "Fedora Linux" | "Fedora" | \
        "Amazon Linux" | "Oracle Linux Server" | "CentOS Stream")
            DISTRO_FAMILY="rhel"
            if [ -n "$BB" ]; then
                if $BB echo "$distro_version" | $BB grep -qE '^8|^9|^10|^2[2-9]|^[3-9]'; then
                    PKG_CMD="dnf check-update"
                    PKG_INSTALL="dnf install -y"
                else
                    PKG_CMD="yum check-update"
                    PKG_INSTALL="yum install -y"
                fi
            else
                if echo "$distro_version" | grep -qE '^8|^9|^10|^2[2-9]|^[3-9]'; then
                    PKG_CMD="dnf check-update"
                    PKG_INSTALL="dnf install -y"
                else
                    PKG_CMD="yum check-update"
                    PKG_INSTALL="yum install -y"
                fi
            fi
            ;;
        "openSUSE Leap" | "openSUSE Tumbleweed")
            DISTRO_FAMILY="suse"
            PKG_CMD="zypper refresh"
            PKG_INSTALL="zypper install -y"
            ;;
        "Alpine Linux")
            DISTRO_FAMILY="alpine"
            PKG_CMD="apk update"
            PKG_INSTALL="apk add"
            ;;
        "Arch Linux" | "Manjaro ARM" | "Artix Linux")
            DISTRO_FAMILY="arch"
            PKG_CMD="pacman -Syy"
            PKG_INSTALL="pacman -S --noconfirm"
            ;;
        "Void Linux")
            DISTRO_FAMILY="void"
            PKG_CMD="xbps-install -S"
            PKG_INSTALL="xbps-install -y"
            ;;
        "Slackware Linux")
            DISTRO_FAMILY="slackware"
            PKG_CMD="slackpkg update"
            PKG_INSTALL="slackpkg install"
            ;;
        "Gentoo Linux")
            DISTRO_FAMILY="gentoo"
            PKG_CMD="emerge --sync"
            PKG_INSTALL="emerge -v"
            ;;
        "ALT Linux")
            DISTRO_FAMILY="alt"
            PKG_CMD="apt-get update -y"
            PKG_INSTALL="apt-get install -y"
            ;;
        "Adélie Linux")
            DISTRO_FAMILY="adelie"
            PKG_CMD="apk update"
            PKG_INSTALL="apk add"
            ;;
        "Chimera Linux")
            DISTRO_FAMILY="chimera"
            PKG_CMD="apk update"
            PKG_INSTALL="apk add"
            ;;
        "Pardus Linux")
            DISTRO_FAMILY="pardus"
            PKG_CMD="apt update -y"
            PKG_INSTALL="apt install -y"
            ;;
        *)
            printf "%b\n" "\n${RED}❌ 检测失败：不支持 $distro_name 系统${RESET}" >&2
            return 1
            ;;
    esac
    
    printf "%b\n" "✅ 检测完成"
    printf "%b\n" "├─ 系统：${GREEN}$DISTRO_FULLNAME${RESET}"
    printf "%b\n" "├─ 家族：${GREEN}$DISTRO_FAMILY${RESET}"
    printf "%b\n" "└─ 包管理：更新=${GRAY}$PKG_CMD${RESET} | 安装=${GRAY}$PKG_INSTALL${RESET}"
    return 0
}
# 检查Root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf "%b\n" "${RED}错误：该操作需root权限，请使用 sudo 运行${RESET}" >&2
        return 1
    fi
    return 0
}
# ==================== 核心函数1：安装基础依赖（Alpine 源优化） ====================
install_deps() {
    check_root || return 1
    init_distro || return 1
    printf "%b\n" "\n${BOLD}【核心功能】安装基础依赖${RESET}"
    
    local deps="bash ca-certificates openrc"
    
    # -------------------------- 新增：Alpine 专属源修改 --------------------------
    if [ "$DISTRO_FAMILY" = "alpine" ]; then
        printf "%b\n" "${GRAY}1. 检测到 Alpine 系统，自动备份并替换 apk 源为清华源${RESET}"
        local repo_path="/etc/apk/repositories"
        local repo_bak="${repo_path}.bak"
        
        # 1.1 备份原 repositories 文件
        if [ -n "$BB" ]; then
            if $BB cp "$repo_path" "$repo_bak" 2>/dev/null; then
                printf "%b\n" "   ✅ 已备份原源列表至：$repo_bak${RESET}"
            else
                printf "%b\n" "${YELLOW}⚠️  备份 $repo_path 失败，继续执行源替换（可能影响回滚）${RESET}"
            fi
            # 1.2 替换源为ustc
            $BB sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' "$repo_path"
        else
            if cp "$repo_path" "$repo_bak" 2>/dev/null; then
                printf "%b\n" "   ✅ 已备份原源列表至：$repo_bak${RESET}"
            else
                printf "%b\n" "${YELLOW}⚠️  备份 $repo_path 失败，继续执行源替换（可能影响回滚）${RESET}"
            fi
            sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g'  "$repo_path"
        fi
        
        printf "%b\n" "   ✅ 已将官方源替换为mirtors.ustc.edu.${RESET}"
    else
        # 非 Alpine 系统：仅设置时区（原有逻辑）
        printf "%b\n" "${GRAY}1. 设置时区为 Asia/Shanghai${RESET}"
    fi
    # -------------------------- 原有逻辑：时区设置（Alpine 系统也需执行） --------------------------
    if [ -n "$BB" ]; then
        $BB ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    else
        ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    fi
    
    # 2. 安装依赖（所有系统通用）
    printf "%b\n" "${GRAY}2. 执行命令：$PKG_CMD && $PKG_INSTALL $deps${RESET}"
    if eval "$PKG_CMD && $PKG_INSTALL $deps"; then
        printf "%b\n" "${GREEN}✅ 基础依赖安装完成${RESET}"
        return 0
    else
        printf "%b\n" "${RED}❌ 依赖安装失败，检查网络或源配置${RESET}" >&2
        return 1
    fi
}
# ==================== 核心函数2：切换国内源（用get_input替代read） ====================
change_mirror() {
    check_root || return 1
    init_distro || return 1
    printf "%b\n" "\n${BOLD}【核心功能】切换国内源${RESET}"
    printf "%b\n" "${GRAY}说明：调用 $MIRROR_SCRIPT_URL 脚本，支持主流系统${RESET}"
    
    printf "%b\n" "\nℹ️  操作提示：启动后需按脚本指引选择对应系统的源"
    get_input "按回车键开始换源（或Ctrl+C取消）..." dummy_input
    
    printf "%b\n" "${GRAY}执行命令：bash <(/usr/local/lm/curl -sSL $MIRROR_SCRIPT_URL)${RESET}"
    if bash <(/usr/local/lm/curl -sSL "$MIRROR_SCRIPT_URL"); then
        printf "%b\n" "\n${BOLD}3. 验证换源结果：执行 $PKG_CMD${RESET}"
        local verify_output
        if [ -n "$BB" ]; then
            verify_output=$($PKG_CMD 2>&1)
        else
            verify_output=$($PKG_CMD 2>&1)
        fi
        if [ $? -eq 0 ]; then
            printf "%b\n" "${GREEN}✅ 换源成功，系统源可正常更新${RESET}"
            return 0
        else
            printf "%b\n" "${RED}⚠️  换源后更新异常，错误摘要（前5行）：${RESET}"
            if [ -n "$BB" ]; then
                $BB echo "$verify_output" | $BB head -5
            else
                echo "$verify_output" | head -5
            fi
            return 1
        fi
    else
        printf "%b\n" "${RED}❌ 换源脚本执行失败，检查网络连接${RESET}" >&2
        return 1
    fi
}
# ==================== 核心函数3：配置SSH服务（全用get_input替代read） ====================
config_ssh() {
    check_root || return 1
    init_distro || return 1
    printf "%b\n" "\n${BOLD}【核心功能】配置SSH服务（chroot适配版）${RESET}"
    
    local ssh_port=""
    local allow_pubkey=""
    local ssh_start_cmd=""
    local default_pwd="root"
    local user_pwd=""
    local user_pwd_confirm=""
    local BASHRC_PATH
    if [ -n "$HOME" ]; then
        BASHRC_PATH="$HOME/.bashrc"
    else
        BASHRC_PATH="/root/.bashrc"
    fi
    
    printf "%b\n" "\n1. 设置SSH登录密码（当前操作用户：$(whoami)）"
    while true; do
        get_input "   请输入密码（留空默认使用 '$default_pwd'）：" user_pwd
        get_input "   请再次确认密码（留空默认使用 '$default_pwd'）：" user_pwd_confirm
        
        if [ -z "$user_pwd" ] && [ -z "$user_pwd_confirm" ]; then
            user_pwd="$default_pwd"
            user_pwd_confirm="$default_pwd"
        fi
        
        if [ "$user_pwd" = "$user_pwd_confirm" ]; then
            break
        else
            printf "%b\n" "${RED}⚠️  两次密码不一致，请重新输入${RESET}" >&2
        fi
    done
    
    printf "%b\n" "${GRAY}   正在应用密码设置...${RESET}"
    if [ -n "$BB" ]; then
        $BB echo -e "$user_pwd\n$user_pwd" | passwd "$(whoami)" >/dev/null 2>&1 || {
            printf "%b\n" "${RED}❌ 密码设置失败，请手动执行 'passwd $(whoami)' 重试${RESET}" >&2
            return 1
        }
    else
        echo -e "$user_pwd\n$user_pwd" | passwd "$(whoami)" >/dev/null 2>&1 || {
            printf "%b\n" "${RED}❌ 密码设置失败，请手动执行 'passwd $(whoami)' 重试${RESET}" >&2
            return 1
        }
    fi
    printf "%b\n" "${GREEN}   ✅ 密码设置完成（留空时默认密码为 '$default_pwd'）${RESET}"
    
    printf "%b\n" "\n2. 检查SSH服务安装状态"
    if ! command -v sshd >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}   ⚠️  未检测到openssh-server，开始安装...${RESET}"
        case "$DISTRO_FAMILY" in
            "debian" | "rhel" | "alt" | "pardus") eval "$PKG_INSTALL openssh-server" ;;
            "arch" | "void" | "slackware") eval "$PKG_INSTALL openssh" ;;
            "alpine" | "adelie" | "chimera") eval "$PKG_INSTALL openssh-server" ;;
            "gentoo") eval "$PKG_INSTALL net-misc/openssh" ;;
            *) 
                printf "%b\n" "${RED}❌ 暂不支持 $DISTRO_FAMILY 家族系统的SSH自动安装${RESET}" >&2
                return 1
                ;;
        esac
        
        if ! command -v sshd >/dev/null 2>&1; then
            printf "%b\n" "${RED}❌ openssh-server 安装失败，请检查源配置${RESET}" >&2
            return 1
        fi
    fi
    printf "%b\n" "${GREEN}   ✅ SSH服务（sshd）已就绪${RESET}"
    
    while true; do
        get_input "\n3. 输入SSH自定义端口（1024-65535）：" ssh_port
        if [ -n "$BB" ]; then
            if $BB echo "$ssh_port" | $BB grep -q '^[0-9]\+$' && [ "$ssh_port" -ge 1024 ] && [ "$ssh_port" -le 65535 ]; then
                break
            else
                printf "%b\n" "${RED}⚠️  无效端口！需输入1024-65535之间的纯数字${RESET}" >&2
            fi
        else
            if echo "$ssh_port" | grep -q '^[0-9]\+$' && [ "$ssh_port" -ge 1024 ] && [ "$ssh_port" -le 65535 ]; then
                break
            else
                printf "%b\n" "${RED}⚠️  无效端口！需输入1024-65535之间的纯数字${RESET}" >&2
            fi
        fi
    done
    
    while true; do
        get_input "4. 是否开启公钥登录（y=开启，n=关闭，默认y）：" allow_pubkey
        if [ -z "$allow_pubkey" ]; then
            allow_pubkey="y"
        fi
        if [ -n "$BB" ]; then
            if $BB echo "$allow_pubkey" | $BB grep -q '^[yYnN]$'; then
                allow_pubkey=$($BB echo "$allow_pubkey" | $BB tr '[:upper:]' '[:lower:]')
                break
            else
                printf "%b\n" "${RED}⚠️  无效输入！仅支持 y 或 n${RESET}" >&2
            fi
        else
            if echo "$allow_pubkey" | grep -q '^[yYnN]$'; then
                allow_pubkey=$(echo "$allow_pubkey" | tr '[:upper:]' '[:lower:]')
                break
            else
                printf "%b\n" "${RED}⚠️  无效输入！仅支持 y 或 n${RESET}" >&2
            fi
        fi
    done
    
    local backup_file
    if [ -n "$BB" ]; then
        backup_file="${SSH_CONFIG}.bak_$($BB date +%Y%m%d_%H%M%S)"
        $BB cp "$SSH_CONFIG" "$backup_file" 2>/dev/null || {
            printf "%b\n" "${RED}❌ 配置备份失败，请检查 $SSH_CONFIG 的读写权限${RESET}" >&2
            return 1
        }
        $BB sed -i "s/^#*Port 22/Port $ssh_port/" "$SSH_CONFIG"
        $BB sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" "$SSH_CONFIG"
        $BB sed -i "s/^#*UseDNS.*/UseDNS no/" "$SSH_CONFIG"
        $BB sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" "$SSH_CONFIG"
        if [ "$allow_pubkey" = "y" ]; then
            $BB sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" "$SSH_CONFIG"
            $BB sed -i "s/^#*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/" "$SSH_CONFIG"
            [ -d "$HOME/.ssh" ] || $BB mkdir -p "$HOME/.ssh" && $BB chmod 700 "$HOME/.ssh"
        else
            $BB sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication no/" "$SSH_CONFIG"
        fi
    else
        backup_file="${SSH_CONFIG}.bak_$(date +%Y%m%d_%H%M%S)"
        cp "$SSH_CONFIG" "$backup_file" 2>/dev/null || {
            printf "%b\n" "${RED}❌ 配置备份失败，请检查 $SSH_CONFIG 的读写权限${RESET}" >&2
            return 1
        }
        sed -i "s/^#*Port 22/Port $ssh_port/" "$SSH_CONFIG"
        sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" "$SSH_CONFIG"
        sed -i "s/^#*UseDNS.*/UseDNS no/" "$SSH_CONFIG"
        sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" "$SSH_CONFIG"
        if [ "$allow_pubkey" = "y" ]; then
            sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" "$SSH_CONFIG"
            sed -i "s/^#*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/" "$SSH_CONFIG"
            [ -d "$HOME/.ssh" ] || mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        else
            sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication no/" "$SSH_CONFIG"
        fi
    fi
    printf "%b\n" "\n5. 备份原SSH配置至：${GRAY}$backup_file${RESET}"
    if [ "$allow_pubkey" = "y" ]; then
        printf "%b\n" "   ✅ 已开启：密码登录 + 公钥登录"
        printf "%b\n" "      📌 客户端公钥部署命令：ssh-copy-id -p $ssh_port $(whoami)@服务器IP"
    else
        printf "%b\n" "   ✅ 已开启：仅密码登录（公钥登录关闭）"
    fi
    
    ssh_start_cmd="/usr/sbin/sshd -f $SSH_CONFIG -D &"
    printf "%b\n" "\n6. 配置SSH自启动（写入 ${GRAY}$BASHRC_PATH${RESET}"
    if [ -n "$BB" ]; then
        $BB sed -i "/\/usr\/sbin\/sshd -f $SSH_CONFIG -D &/d" "$BASHRC_PATH" 2>/dev/null
        $BB echo -e "\n# SSH auto-start (chroot compatible)" >> "$BASHRC_PATH"
        $BB echo "$ssh_start_cmd" >> "$BASHRC_PATH" || {
            printf "%b\n" "${RED}❌ 写入.bashrc失败，请手动执行：echo '$ssh_start_cmd' >> $BASHRC_PATH${RESET}" >&2
            return 1
        }
    else
        sed -i "/\/usr\/sbin\/sshd -f $SSH_CONFIG -D &/d" "$BASHRC_PATH" 2>/dev/null
        echo -e "\n# SSH auto-start (chroot compatible)" >> "$BASHRC_PATH"
        echo "$ssh_start_cmd" >> "$BASHRC_PATH" || {
            printf "%b\n" "${RED}❌ 写入.bashrc失败，请手动执行：echo '$ssh_start_cmd' >> $BASHRC_PATH${RESET}" >&2
            return 1
        }
    fi
    printf "%b\n" "   ✅ 自启动命令已写入.bashrc，下次进入chroot会话自动启动SSH"
    
    printf "%b\n" "\n7. 立即启动SSH服务并验证..."
    if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
        printf "%b" "${GRAY}   检测到无SSH主机密钥，自动生成...${RESET}\n"
        ssh-keygen -A 
        if [ $? -ne 0 ]; then
            printf "%b\n" "${RED}   ❌ 主机密钥生成失败，请手动执行 'ssh-keygen -A'${RESET}" >&2
            return 1
        fi
    fi
    
    if [ -n "$BB" ]; then
        $BB pkill -f "/usr/sbin/sshd -f $SSH_CONFIG" >/dev/null 2>&1
        /usr/sbin/sshd -f "$SSH_CONFIG" -D & >/dev/null 2>&1
        $BB sleep 2
        local ssh_running=0
        if $BB pgrep -f "/usr/sbin/sshd -f $SSH_CONFIG" >/dev/null 2>&1; then
            ssh_running=1
        fi
    else
        pkill -f "/usr/sbin/sshd -f $SSH_CONFIG" >/dev/null 2>&1
        /usr/sbin/sshd -f "$SSH_CONFIG" -D & >/dev/null 2>&1
        sleep 2
        local ssh_running=0
        if pgrep -f "/usr/sbin/sshd -f $SSH_CONFIG" >/dev/null 2>&1; then
            ssh_running=1
        fi
    fi
    
    if /usr/sbin/sshd -t -f "$SSH_CONFIG" >/dev/null 2>&1; then
        if [ "$ssh_running" -eq 1 ]; then
            printf "%b\n" "\n${GREEN}🎉 SSH配置全部完成！${RESET}"
            printf "%b\n" "   📌 连接命令：ssh $(whoami)@服务器IP -p $ssh_port"
            if [ "$user_pwd" = "$default_pwd" ]; then
                printf "%b\n" "   📌 登录密码：默认 '$default_pwd'"
            else
                printf "%b\n" "   📌 登录密码：自定义密码"
            fi
            return 0
        else
            printf "%b\n" "\n${RED}❌ SSH进程启动失败，请检查配置文件${RESET}" >&2
            return 1
        fi
    else
        printf "%b\n" "\n${RED}❌ SSH配置文件错误！执行 '/usr/sbin/sshd -t -f $SSH_CONFIG' 查看详情${RESET}" >&2
        return 1
    fi
}
# ==================== 核心函数4：启动tmoe工具（用get_input替代read） ====================
start_tmoe() {
    init_distro || return 1
    printf "%b\n" "\n${BOLD}【核心功能】启动tmoe Linux工具${RESET}"
    printf "%b\n" "${GRAY}功能：系统安装、Docker部署、环境配置等（交互式界面）${RESET}"
    printf "%b\n" "${GRAY}执行命令：$TMOE_SCRIPT_CMD${RESET}"
    
    printf "%b\n" "\nℹ️  操作提示："
    printf "%b\n" "   - 启动后进入交互界面，按需求选择功能"
    printf "%b\n" "   - 部分操作需输入root密码，请保持终端活跃"
    get_input "按回车键启动tmoe（或Ctrl+C取消）..." dummy_input
    
    eval "$TMOE_SCRIPT_CMD"
    if [ $? -eq 0 ]; then
        printf "%b\n" "\n${GREEN}✅ tmoe工具正常退出${RESET}"
        return 0
    else
        printf "%b\n" "\n${RED}⚠️  tmoe执行异常，建议检查网络（如添加DNS：8.8.8.8）${RESET}"
        return 1
    fi
}
# ==================== 主菜单（全用get_input替代read） ====================
show_main_menu() {
    if [ -n "$BB" ]; then
        $BB clear
    else
        clear
    fi
    
    printf "%b\n" "${BOLD}=================== 系统初始化工具集 ===================${RESET}"
    init_distro &>/dev/null
    printf "%b\n" "当前系统：${GREEN}$DISTRO_FULLNAME${RESET}（${DISTRO_FAMILY} 家族）"
    printf "%b\n" "${BOLD}=======================================================${RESET}"
    printf "%b\n" "【核心功能调用】"
    printf "%b\n" "   1. 安装基础依赖（bash/ca-certificates + 时区设置）"
    printf "%b\n" "   2. 切换国内源（提升软件安装速度）"
    printf "%b\n" "   3. 配置SSH服务（自定义端口+公钥登录）"
    printf "%b\n" "   4. 启动tmoe工具（系统管理/容器部署）"
    printf "%b\n" "   5. 退出"
    printf "%b\n" "${BOLD}=======================================================${RESET}"
    
    local choice
    get_input "请输入功能编号（1-5）：" choice
    
    case "$choice" in
        1) install_deps ;;
        2) change_mirror ;;
        3) config_ssh ;;
        4) start_tmoe ;;
        5) printf "%b\n" "${GREEN}再见！${RESET}"; exit 0 ;;
        *) 
            printf "%b\n" "${RED}⚠️  无效输入，请重新选择${RESET}" >&2
            if [ -n "$BB" ]; then
                $BB sleep 2
            else
                sleep 2
            fi
            ;;
    esac
    
    printf "%b\n" "\n${GRAY}按回车键返回主菜单...${RESET}"
    get_input "" dummy_input
    show_main_menu
}
# ==================== 脚本入口（POSIX兼容） ====================
if [ $# -eq 1 ]; then
    case "$1" in
        install_deps | change_mirror | config_ssh | start_tmoe)
            "$1"
            exit $?
            ;;
        *)
            printf "%b\n" "${RED}错误：不存在的函数「$1」${RESET}" >&2
            printf "%b\n" "${GRAY}支持的函数：install_deps、change_mirror、config_ssh、start_tmoe${RESET}"
            exit 1
            ;;
    esac
else
    show_main_menu
fi
