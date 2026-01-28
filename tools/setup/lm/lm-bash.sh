#!/bin/bash
# 系统初始化工具集（独立函数版）- 适配62种Linux发行版
# 特点：各核心函数独立运行，无强制流程依赖，支持单独调用
# ==================== 基础配置（全局通用，所有函数依赖） ====================
# 颜色定义
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
GRAY="\033[90m"
RED="\033[31m"
YELLOW="\033[33m"
# 核心参数（函数执行前自动初始化，无需手动设置）
DISTRO_FULLNAME=""    # 完整发行版名（如：Debian 12 Bookworm）
DISTRO_FAMILY=""      # 发行版家族（debian/rhel/alpine等）
PKG_CMD=""            # 包管理器更新命令
PKG_INSTALL=""        # 包管理器安装命令
SSH_CONFIG="/etc/ssh/sshd_config"
MIRROR_SCRIPT_URL="https://linuxmirrors.cn/main.sh"
TMOE_SCRIPT_CMD='bash -c "$(/usr/local/lm/curl -L l.tmoe.me)"'
# fix_systemd 函数依赖：软链接路径配置（需按实际源脚本路径调整）
SERVICECTL_SRC="/usr/local/lm/servicectl-master/servicectl"  # servicectl源脚本路径（关键！不符则修改）
SERVICED_SRC="/usr/local/lm/servicectl-master/serviced" 
SERVICECTL_DST="/usr/bin/servicectl"                  
SERVICED_DST="/usr/bin/serviced"                      
# ==================== 工具函数（通用辅助，供核心函数调用） ====================
# 初始化发行版信息（所有核心函数执行前自动调用，确保环境适配）
init_distro() {
    # 若已初始化，直接返回
    [ -n "$DISTRO_FAMILY" ] && return 0
    echo -n -e "${BOLD}【工具】检测系统发行版...${RESET}"
    local os_release="/etc/os-release"
    local distro_name=""
    local distro_version=""
    local distro_codename=""
    # 1. 校验核心依赖文件 /etc/os-release
    if [ ! -f "$os_release" ]; then
        echo -e "\n${RED}❌ 检测失败：未找到 $os_release 文件，不支持当前系统${RESET}" >&2
        return 1
    fi
    # 2. 从 os-release 提取并清理系统信息（去引号、去首尾空格）
    distro_name=$(grep -E '^NAME=' "$os_release" | cut -d'=' -f2- | sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
    distro_version=$(grep -E '^VERSION_ID=' "$os_release" | cut -d'=' -f2- | sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
    distro_codename=$(grep -E '^VERSION_CODENAME=' "$os_release" | cut -d'=' -f2- | sed -e 's/"//g' -e 's/^ //' -e 's/ $//')
    DISTRO_FULLNAME="$distro_name $distro_version${distro_codename:+(($distro_codename))}"
    # 3. 绑定发行版家族与包管理命令（支持62种发行版，按家族归类）
    case "$distro_name" in
        # Debian家族（含Devuan/BackBox/Parrot/OpenKylin等11种）
        "Debian GNU/Linux" | "Kali GNU/Linux" | "Deepin" | "Ubuntu" | "OpenKylin" | \
        "Devuan GNU/Linux" | "BackBox Linux" | "Parrot Security")
            DISTRO_FAMILY="debian"
            PKG_CMD="apt-get update -y"
            PKG_INSTALL="apt-get install -y"
            ;;
        # RHEL家族（含Amazon/Oracle/Alma/Rocky/CentOS Stream等9种）
        "CentOS Linux" | "AlmaLinux" | "Rocky Linux" | "openEuler" | "Fedora Linux" | "Fedora" | \
        "Amazon Linux" | "Oracle Linux Server" | "CentOS Stream")
            DISTRO_FAMILY="rhel"
            if echo "$distro_version" | grep -qE '^8|^9|^10|^2[2-9]|^[3-9]'; then
                PKG_CMD="dnf check-update"
                PKG_INSTALL="dnf install -y"
            else
                PKG_CMD="yum check-update"   
                PKG_INSTALL="yum install -y"
            fi
            ;;
        # SUSE家族（含Leap/Tumbleweed等3种）
        "openSUSE Leap" | "openSUSE Tumbleweed")
            DISTRO_FAMILY="suse"
            PKG_CMD="zypper refresh"
            PKG_INSTALL="zypper install -y"
            ;;
        # Alpine家族（3.16-3.22等7种）
        "Alpine Linux")
            DISTRO_FAMILY="alpine"
            PKG_CMD="apk update"
            PKG_INSTALL="apk add"
            ;;
        # Arch家族（含Artix/Manjaro ARM等3种）
        "Arch Linux" | "Manjaro ARM" | "Artix Linux")
            DISTRO_FAMILY="arch"
            PKG_CMD="pacman -Syy"
            PKG_INSTALL="pacman -S --noconfirm"
            ;;
        # VoidLinux家族（musl/glibc等2种）
        "Void Linux")
            DISTRO_FAMILY="void"
            PKG_CMD="xbps-install -S"
            PKG_INSTALL="xbps-install -y"
            ;;
        # Slackware家族（14.2/15.0等2种）
        "Slackware Linux")
            DISTRO_FAMILY="slackware"
            PKG_CMD="slackpkg update"
            PKG_INSTALL="slackpkg install"
            ;;
        # Gentoo家族（OpenRC/systemd等2种）
        "Gentoo Linux")
            DISTRO_FAMILY="gentoo"
            PKG_CMD="emerge --sync"
            PKG_INSTALL="emerge -v"
            ;;
        # ALT Linux家族（P11/Sisyphus等2种）
        "ALT Linux")
            DISTRO_FAMILY="alt"
            PKG_CMD="apt-get update -y"
            PKG_INSTALL="apt-get install -y"
            ;;
        # Adelie Linux（1种）
        "Adélie Linux")
            DISTRO_FAMILY="adelie"
            PKG_CMD="apk update"
            PKG_INSTALL="apk add"
            ;;
        # Chimera Linux（1种）
        "Chimera Linux")
            DISTRO_FAMILY="chimera"
            PKG_CMD="apk update"
            PKG_INSTALL="apk add"
            ;;
        # Pardus Linux（1种）
        "Pardus Linux")
            DISTRO_FAMILY="pardus"
            PKG_CMD="apt update -y"
            PKG_INSTALL="apt install -y"
            ;;
        # 未匹配到已知系统，直接报错
        *)
            echo -e "\n${RED}❌ 检测失败：不支持 $distro_name 系统（仅支持 Debian/RHEL/SUSE/Alpine/Arch/Void/Slackware/Gentoo/ALT/Adelie/Chimera/Pardus 家族）${RESET}" >&2
            return 1
            ;;
    esac
    # 4. 输出检测结果
    echo -e "✅ 检测完成"
    echo -e "├─ 系统：${GREEN}$DISTRO_FULLNAME${RESET}"
    echo -e "├─ 家族：${GREEN}$DISTRO_FAMILY${RESET}"
    echo -e "└─ 包管理：更新=${GRAY}$PKG_CMD${RESET} | 安装=${GRAY}$PKG_INSTALL${RESET}"
    return 0
}
# 检查Root权限（需Root的函数自动调用）
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：该操作需root权限，请使用 sudo 运行${RESET}" >&2
        return 1
    fi
    return 0
}
# ==================== 核心函数1：安装基础依赖（独立运行） ====================
# 功能：安装bash/ca-certificates，设置上海时区，适配所有系统
# 调用方式：./lm.sh install_deps
install_deps() {
    # 前置检查：Root权限 + 发行版初始化
    check_root || return 1
    init_distro || return 1
    echo -e "\n${BOLD}【核心功能】安装基础依赖${RESET}"
    local REQUIRED_DEPS=("bash" "ca-certificates")
    # 1. 设置系统时区
    echo -e "${GRAY}1. 设置时区为 Asia/Shanghai${RESET}"
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    # 2. 执行依赖安装（适配各家族包管理命令）
    echo -e "${GRAY}2. 执行命令：$PKG_CMD && $PKG_INSTALL ${REQUIRED_DEPS[*]}${RESET}"
    if $PKG_CMD && $PKG_INSTALL "${REQUIRED_DEPS[@]}"; then
        echo -e "${GREEN}✅ 基础依赖安装完成${RESET}"
        return 0
    else
        echo -e "${RED}❌ 依赖安装失败，检查网络或源配置${RESET}" >&2
        return 1
    fi
}
# ==================== 核心函数2：切换国内源（独立运行） ====================
# 功能：调用linuxmirrors.cn脚本切换国内源，自动验证源可用性
# 调用方式：./lm.sh change_mirror
change_mirror() {
    # 前置检查：Root权限 + 发行版初始化
    check_root || return 1
    init_distro || return 1
    echo -e "\n${BOLD}【核心功能】切换国内源${RESET}"
    echo -e "${GRAY}说明：调用 $MIRROR_SCRIPT_URL 脚本，支持主流系统${RESET}"
    # 1. 提示用户交互注意事项
    echo -e "\nℹ️  操作提示：启动后需按脚本指引选择对应系统的源（如Debian→清华源）"
    read -p "按回车键开始换源（或Ctrl+C取消）..."
    # 2. 执行换源脚本
    echo -e "${GRAY}执行命令：bash <(/usr/local/lm/curl -sSL $MIRROR_SCRIPT_URL)${RESET}"
    bash <(/usr/local/lm/curl -sSL "$MIRROR_SCRIPT_URL") || {
        echo -e "${RED}❌ 换源脚本执行失败，检查网络连接${RESET}" >&2
        return 1
    }
    # 3. 验证源可用性
    echo -e "\n${BOLD}3. 验证换源结果：执行 $PKG_CMD${RESET}"
    local verify_output=$($PKG_CMD 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 换源成功，系统源可正常更新${RESET}"
        return 0
    else
        echo -e "${RED}⚠️  换源后更新异常，错误摘要（前5行）：${RESET}"
        echo "$verify_output" | head -5
        return 1
    fi
}
# ==================== 核心函数3：配置SSH服务（独立运行） ====================
# 功能：自定义端口、开关公钥登录、自动安装服务、配置自启
# 调用方式：./lm.sh config_ssh
config_ssh() {
    # 前置检查：Root权限 + 发行版初始化
    check_root || return 1
    init_distro || return 1
    echo -e "\n${BOLD}【核心功能】配置SSH服务（chroot适配版）${RESET}"
    local ssh_port="" allow_pubkey="" ssh_start_cmd="" 
    local default_pwd="root"  # 默认登录密码
    local user_pwd=""         # 用户输入密码
    local BASHRC_PATH="$HOME/.bashrc"  # chroot环境用户bash配置文件
    # ============== 1. 设置登录密码（留空默认root） ==============
    echo -e "\n1. 设置SSH登录密码（当前操作用户：$(whoami)）"
    # 读取密码（隐藏输入，支持留空）
    while true; do
        echo -n -e "   请输入密码（留空默认使用 '$default_pwd'）："
        read -s user_pwd  # -s 隐藏输入内容
        echo -e "\n   请再次确认密码（留空默认使用 '$default_pwd'）："
        read -s user_pwd_confirm
        echo  # 换行，避免输出拥挤
        # 处理密码逻辑：留空则用默认值，非空则校验一致性
        if [ -z "$user_pwd" ] && [ -z "$user_pwd_confirm" ]; then
            user_pwd="$default_pwd"
            user_pwd_confirm="$default_pwd"
        fi
        if [ "$user_pwd" = "$user_pwd_confirm" ]; then
            break
        else
            echo -e "${RED}⚠️  两次密码不一致，请重新输入${RESET}" >&2
        fi
    done
    # 执行passwd命令设置密码（通过管道避免交互）
    echo -e "${GRAY}   正在应用密码设置...${RESET}"
    echo -e "$user_pwd\n$user_pwd" | passwd "$(whoami)" >/dev/null 2>&1 || {
        echo -e "${RED}❌ 密码设置失败，请手动执行 'passwd $(whoami)' 重试${RESET}" >&2
        return 1
    }
    echo -e "${GREEN}   ✅ 密码设置完成（留空时默认密码为 '$default_pwd'）${RESET}"
    # ============== 2. 检查并安装SSH服务（适配所有家族） ==============
    echo -e "\n2. 检查SSH服务安装状态"
    if ! command -v sshd >/dev/null 2>&1; then
        echo -e "${YELLOW}   ⚠️  未检测到openssh-server，开始安装...${RESET}"
        case "$DISTRO_FAMILY" in
            "debian" | "rhel" | "alt" | "pardus") $PKG_INSTALL openssh-server ;;
            "arch" | "void" | "slackware") $PKG_INSTALL openssh ;;
            "alpine" | "adelie" | "chimera") $PKG_INSTALL openssh-server ;;
            "gentoo") $PKG_INSTALL net-misc/openssh ;;
            *) 
                echo -e "${RED}❌ 暂不支持 $DISTRO_FAMILY 家族系统的SSH自动安装${RESET}" >&2
                return 1
                ;;
        esac
        # 二次校验安装结果
        if ! command -v sshd >/dev/null 2>&1; then
            echo -e "${RED}❌ openssh-server 安装失败，请检查源配置${RESET}" >&2
            return 1
        fi
    fi
    echo -e "${GREEN}   ✅ SSH服务（sshd）已就绪${RESET}"
    # ============== 3. 自定义SSH端口（22-65535） ==============
    while true; do
        echo -n -e "\n3.设置端口 22-65535）："
        read -r ssh_port
        if [[ "$ssh_port" =~ ^[0-9]+$ ]] && [ "$ssh_port" -ge 22 ] && [ "$ssh_port" -le 65535 ]; then
            break
        else
            echo -e "${RED}⚠️  无效端口！需输入22-65535之间的纯数字${RESET}" >&2
        fi
    done
    # ============== 4. 开关公钥登录（默认开启） ==============
    while true; do
        echo -n -e "4. 是否开启公钥登录（y=开启，n=关闭，默认y）："
        read -r allow_pubkey
        allow_pubkey="${allow_pubkey:-y}"  # 留空默认开启
        if [[ "$allow_pubkey" =~ ^[yYnN]$ ]]; then
            allow_pubkey=$(echo "$allow_pubkey" | tr '[:upper:]' '[:lower:]')
            break
        else
            echo -e "${RED}⚠️  无效输入！仅支持 y 或 n${RESET}" >&2
        fi
    done
    # ============== 5. 备份并修改SSH配置文件 ==============
    local backup_file="${SSH_CONFIG}.bak_$(date +%Y%m%d_%H%M%S)"
    echo -e "\n5. 备份原SSH配置至：${GRAY}$backup_file${RESET}"
    if ! cp "$SSH_CONFIG" "$backup_file" 2>/dev/null; then
        echo -e "${RED}❌ 配置备份失败，请检查 $SSH_CONFIG 的读写权限${RESET}" >&2
        return 1
    fi
    # 修改核心配置（适配chroot）
    sed -i "s/^#*Port 22/Port $ssh_port/" "$SSH_CONFIG"  # 替换默认端口（防扫描）
    sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" "$SSH_CONFIG"  # 强制开密码登录
    sed -i "s/^#*UseDNS.*/UseDNS no/" "$SSH_CONFIG"  # 禁用DNS反向解析（加速连接）
    sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" "$SSH_CONFIG"  # 允许root登录
    # 配置公钥登录
    if [ "$allow_pubkey" = "y" ]; then
        sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" "$SSH_CONFIG"
        sed -i "s/^#*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/" "$SSH_CONFIG"
        [ -d "$HOME/.ssh" ] || mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
        echo -e "   ✅ 已开启：密码登录 + 公钥登录"
        echo -e "      📌 客户端公钥部署：ssh-copy-id -p $ssh_port $(whoami)@服务器IP"
    else
        sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication no/" "$SSH_CONFIG"
        echo -e "   ✅ 已开启：仅密码登录（公钥登录关闭）"
    fi
    # ============== 6. 配置SSH自启动（Runit/Bashrc） ==============
    if [ -d "/etc/service" ]; then
        echo -e "\n6. 检测到 Runit 环境，配置 runit 服务..."
        mkdir -p /etc/service/sshd
        # Create run script
        cat > /etc/service/sshd/run <<EOF
#!/bin/sh
mkdir -p /run/sshd
exec /usr/sbin/sshd -f $SSH_CONFIG -D
EOF
        chmod +x /etc/service/sshd/run
        echo -e "   ✅ Runit 服务配置完成 (/etc/service/sshd/run)"
        # Clean up legacy .bashrc entry if exists
        sed -i "/\/usr\/sbin\/sshd -f \$SSH_CONFIG -D \&/d" "$BASHRC_PATH" 2>/dev/null
    else
        ssh_start_cmd="mkdir -p /run/sshd && /usr/sbin/sshd -f $SSH_CONFIG -D &"
        echo -e "\n6. 配置自启动（写入 ${GRAY}$BASHRC_PATH${RESET}）"
        # 先删旧命令（避免重复启动）
        sed -i "/\/usr\/sbin\/sshd -f \$SSH_CONFIG -D \&/d" "$BASHRC_PATH" 2>/dev/null
        # 追加新命令
        echo -e "\n# SSH auto-start (chroot compatible)" >> "$BASHRC_PATH"
        echo "$ssh_start_cmd" >> "$BASHRC_PATH" || {
            echo -e "${RED}❌ 写入失败！手动执行：echo '$ssh_start_cmd' >> $BASHRC_PATH${RESET}" >&2
            return 1
        }
        echo -e "   ✅ 自启动命令已写入，下次进chroot自动启动SSH"
    fi

    # ============== 7. 立即启动SSH并验证 ==============
    printf "%b\n" "\n7. 立即启动SSH并验证..."
    # 确保 /run/sshd 存在
    mkdir -p /run/sshd
    # 自动生成SSH主机密钥（解决“no hostkeys available”问题）
    if [ ! -f "/etc/ssh/ssh_host_rsa_key" ]; then
        printf "%b" "${GRAY}   无主机密钥，自动生成...${RESET}\n"
        ssh-keygen -A || {
            printf "%b\n" "${RED}   ❌ 密钥生成失败！手动执行 'ssh-keygen -A'${RESET}" >&2
            return 1
        }
    fi
    
    if [ -d "/etc/service" ] && [ -x "/etc/service/sshd/run" ]; then
        echo -e "${GRAY}   等待 Runit 启动服务...${RESET}"
        sleep 5
    else
        # 终止旧进程→启动新进程→延迟验证
        pkill -f "/usr/sbin/sshd -f $SSH_CONFIG" >/dev/null 2>&1
        /usr/sbin/sshd -f "$SSH_CONFIG" -D & >/dev/null 2>&1
        sleep 2
    fi
    # 三层校验（进程+配置+端口）
    local ssh_running=0
    pgrep -f "/usr/sbin/sshd -f $SSH_CONFIG" >/dev/null 2>&1 && ssh_running=1
    if /usr/sbin/sshd -t -f "$SSH_CONFIG" >/dev/null 2>&1; then
        if (echo >/dev/tcp/127.0.0.1/"$ssh_port") >/dev/null 2>&1; then
            echo -e "\n${GREEN}🎉 SSH配置完成！${RESET}"
            echo -e "   📌 连接命令：ssh $(whoami)@服务器IP -p $ssh_port"
            echo -e "   📌 登录密码：$( [ "$user_pwd" = "$default_pwd" ] && echo "默认 '$default_pwd'" || echo "自定义密码" )"
            return 0
        elif [ $ssh_running -eq 1 ]; then
            echo -e "\n${YELLOW}⚠️  进程已启动，本地连接失败（可能是chroot网络限制）${RESET}"
            echo -e "   📌 建议外部测试：ssh $(whoami)@服务器IP -p $ssh_port"
            return 0
        fi
    fi
    # 校验失败提示
    echo -e "\n${RED}❌ SSH启动失败！${RESET}"
    echo -e "   📌 排查：1. /usr/sbin/sshd -t -f $SSH_CONFIG（查配置错）；2. pgrep -f '/usr/sbin/sshd -f $SSH_CONFIG'（查进程）"
    return 1
}
# ==================== 核心函数4：启动tmoe工具（独立运行） ====================
# 功能：启动tmoe Linux管理工具（系统管理、容器部署等）
# 调用方式：./lm.sh start_tmoe
start_tmoe() {
    # 前置检查：仅需发行版初始化（tmoe内部管权限）
    init_distro || return 1
    echo -e "\n${BOLD}【核心功能】启动tmoe Linux工具${RESET}"
    echo -e "${GRAY}功能：系统安装、Docker部署、环境配置（交互式界面）${RESET}"
    echo -e "${GRAY}执行命令：$TMOE_SCRIPT_CMD${RESET}"
    # 提示注意事项
    echo -e "\nℹ️  提示：1. 启动后进交互界面；2. 部分操作需root密码"
    read -p "按回车键启动（或Ctrl+C取消）..."
    # 执行tmoe
    eval "$TMOE_SCRIPT_CMD"
    # 输出结果
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}✅ tmoe正常退出${RESET}"
        return 0
    else
        echo -e "\n${RED}⚠️  tmoe执行异常！检查网络（如加DNS：8.8.8.8）${RESET}"
        return 1
    fi
}
# ==================== 核心函数5：fix_systemd（新增，独立运行） ====================
# 功能：安装Systemd依赖（无则装）+ 直接复制servicectl/serviced到/usr/bin
# 调用方式：1. 命令行：./lm.sh fix_systemd；2. 脚本菜单选5号选项
fix_systemd() {
    # 前置检查：Root权限 + 发行版初始化
    check_root || return 1
    init_distro || return 1
    echo -e "\n${BOLD}【核心功能（新增）】修复Systemd（装依赖+直接复制到/usr/bin/目录下）${RESET}"

    # 1. 检查并安装Systemd依赖
    echo -e "\n1. 检查Systemd依赖"
    local SYSTEMD_DEPS="systemd"
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${YELLOW}   ⚠️  未检测到Systemd，开始安装...${RESET}"
        echo -e "${GRAY}   执行：$PKG_CMD && $PKG_INSTALL $SYSTEMD_DEPS${RESET}"
        # 先更源再安装（避免版本错）
        if ! $PKG_CMD || ! $PKG_INSTALL "$SYSTEMD_DEPS"; then
            echo -e "${RED}❌ Systemd安装失败！手动执行 '$PKG_INSTALL $SYSTEMD_DEPS' 重试${RESET}" >&2
            return 1
        fi
        # 二次校验
        if ! command -v systemctl >/dev/null 2>&1; then
            echo -e "${RED}❌ 安装后仍无法调用，排查系统源是否损坏${RESET}" >&2
            return 1
        fi
    fi
    echo -e "${GREEN}   ✅ Systemd依赖已就绪（已装/无需装）${RESET}"

    # 2. 校验servicectl源脚本（避免无效软链接）
    echo -e "\n2. 校验源脚本路径"
    if [ ! -f "$SERVICECTL_SRC" ]; then
        echo -e "${RED}❌ 源脚本不存在！当前路径：$SERVICECTL_SRC${RESET}" >&2
        echo -e "${GRAY}   提示：修改脚本中 'SERVICECTL_SRC' 为实际路径${RESET}" >&2
        return 1
    fi
    echo -e "${GREEN}   ✅ 源脚本校验通过：$SERVICECTL_SRC${RESET}"
     
    echo -e "\n3.复制serviced/servicectl到/usr/bin"
    #3.核心操作，复制/usr/bin简单粗暴/易用。避免奇怪问题
    cp -R ${SERVICECTL_SRC} ${SERVICECTL_DST} 
    cp -R ${SERVICED_SRC} ${SERVICED_DST} 
    chmod 755 ${SERVICED_DST} ${SERVICECTL_DST} 
    mkdir -p /usr/bin/enabled
    chmod 755 -R /usr/bin/enabled
    echo "已将测试服务test-servicectl.service复制到/usr/lib/systemd/systemm目录下"
    cp /usr/local/lm/servicectl-master/test-servicectl.service /usr/lib/systemd/system
     
 
    # 4. 验证可用性
    echo -e "\n4. 验证servicectl可用性"
    if command -v servicectl >/dev/null 2>&1 && command -v serviced >/dev/null 2>&1; then
       echo -e "\n${GREEN} 已设置test-servicectl.service为容器启动时自动启动，如果成功则会有（1233,这是一个测试，如果显示此内容则说明servicectl开机自启动运行成功）的提示信息,若失败则不提示${RESET}"
        servicectl enable test-servicectl
        echo -e "\n${GREEN}🎉 Systemd修复完成！，使用方法详细见/usr/local/lm/servicectl-master/README.md${RESET}"
        echo -e "   📌 servicectl路径：$(command -v servicectl)"
        echo -e "   📌 serviced路径：$(command -v serviced)"
        return 0
    else
        echo -e "\n${YELLOW}⚠️  servicectl已复制到/usr/bin目录下但无法调用！${RESET}" >&2
        echo -e "${GRAY}   排查：echo $PATH，确认 /usr/bin 在环境变量中${RESET}" >&2
        return 0  # 仅环境变量问题，不返回失败
    fi
}
# ==================== 主菜单（含fix_systemd选项） ====================
# 调用方式：直接运行 ./lm.sh
show_main_menu() {
    clear
    echo -e "${BOLD}=================== 系统初始化工具集 ===================${RESET}"
    # 自动初始化发行版（用于菜单显示）
    init_distro &>/dev/null
    echo -e "当前系统：${GREEN}$DISTRO_FULLNAME${RESET}（${DISTRO_FAMILY} 家族）"
    echo -e "${BOLD}=======================================================${RESET}"
    echo -e "【核心功能调用】"
    echo -e "   1. 安装基础依赖（bash/证书 + 时区，必做）"
    echo -e "   2. 切换国内源（提升安装速度）"
    echo -e "   3. 配置SSH服务（自定义端口+登录）"
    echo -e "   4. 启动tmoe工具（系统管理/容器部署）"
    # echo -e "   5. 修复Systemd「类systemd实现」（装依赖+直接复制，使用servicectl start/stop/restart/reload/enable/disable} xxxx.service）"
    echo -e "   6. 退出"
    echo -e "${BOLD}=======================================================${RESET}"
    # 读取选择并调用函数
    echo -n -e "请输入功能编号（1-6）："
    read -r choice
    case "$choice" in
        1) install_deps ;;
        2) change_mirror ;;
        3) config_ssh ;;
        4) start_tmoe ;;
        # 5) fix_systemd ;;  
        6) echo -e "${GREEN}再见！${RESET}"; exit 0 ;;
        *) echo -e "${RED}⚠️  无效输入，请重新选${RESET}" >&2; sleep 2 ;;
    esac
    # 返回菜单
    echo -e "\n${GRAY}按回车键返回主菜单...${RESET}"
    read -r
    show_main_menu
}
# ==================== 脚本入口（支持fix_systemd调用） ====================
# 1. 命令行调用：./lm.sh 函数名（如 ./lm.sh fix_systemd）
# 2. 无参数：进菜单模式
if [ $# -eq 1 ]; then
    if declare -f "$1" >/dev/null; then
        "$1"
        exit $?
    else
        echo -e "${RED}错误：无函数「$1」${RESET}" >&2
        echo -e "${GRAY}支持函数：install_deps、change_mirror、config_ssh、start_tmoe、fix_systemd${RESET}"
        exit 1
    fi
else
    show_main_menu
fi
