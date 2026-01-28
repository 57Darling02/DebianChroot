#!/bin/sh
# 优化版自动启动脚本：按「系统类型+Shell优先级」执行对应脚本
# 核心规则：
# 1. 非Alpine系统：bash环境→执行lm-bash.sh；无bash→降级执行lm-bash.sh基础功能
# 2. Alpine系统：存在bash→优先执行lm-bash.sh；仅ash→执行lm-alpine.sh
# ==================== 环境检测函数 ====================
detect_env() {
    local is_alpine=0    # 1=Alpine系统，0=非Alpine系统
    local has_bash=0     # 1=系统存在bash，0=无bash
    local current_shell="" # 当前Shell（bash/ash/sh）

    # 1. 判定是否为Alpine系统（双重校验：os-release + apk命令）
    if [ -f "/etc/os-release" ] && grep -qE '^NAME="?Alpine Linux"?$' "/etc/os-release"; then
        is_alpine=1
    elif command -v apk >/dev/null 2>&1; then
        is_alpine=1
    fi

    # 2. 判定系统是否存在bash（优先检查命令，再检查路径）
    if command -v bash >/dev/null 2>&1 || [ -x "/bin/bash" ] || [ -x "/usr/bin/bash" ]; then
        has_bash=1
    fi

    # 3. 获取当前Shell（取basename避免路径干扰）
    current_shell=$(basename "$SHELL")

    # 返回结果：格式 "is_alpine:has_bash:current_shell"
    echo "${is_alpine}:${has_bash}:${current_shell}"
}

# ==================== 脚本校验函数 ====================
verify_scripts() {
    local lm_sh="$1"
    local lm_alpine_sh="$2"

    # 1. 检查脚本是否存在
    if [ ! -f "$lm_sh" ]; then
        echo "❌ 错误：lm-bash.sh 不存在（路径：$lm_sh）" >&2
        return 1
    fi
    if [ ! -f "$lm_alpine_sh" ]; then
        echo "❌ 错误：lm-alpine.sh 不存在（路径：$lm_alpine_sh）" >&2
        return 1
    fi

    # 2. 确保脚本可执行（无权限则自动添加）
    if [ ! -x "$lm_sh" ]; then
        echo "ℹ️  自动修复 lm-bash.sh 执行权限"
        chmod +x "$lm_sh" || {
            echo "❌ 修复 lm-bash.sh 权限失败，请手动执行 chmod +x $lm_sh" >&2
            return 1
        }
    fi
    if [ ! -x "$lm_alpine_sh" ]; then
        echo "ℹ️  自动修复 lm-alpine.sh 执行权限"
        chmod +x "$lm_alpine_sh" || {
            echo "❌ 修复 lm-alpine.sh 权限失败，请手动执行 chmod +x $lm_alpine_sh" >&2
            return 1
        }
    fi

    return 0
}

# ==================== 主执行逻辑 ====================
main() {
    # 1. 定义脚本路径（请根据实际部署路径修改，确保与文件位置一致）
    local LM_SH="/usr/local/lm/lm-bash.sh"
    local LM_ALPINE_SH="/usr/local/lm/lm-alpine.sh"

    # 2. 校验脚本完整性与权限
    if ! verify_scripts "$LM_SH" "$LM_ALPINE_SH"; then
        exit 1
    fi

    # 3. 获取环境检测结果
    local env_result=$(detect_env)
    local is_alpine=$(echo "$env_result" | cut -d':' -f1)
    local has_bash=$(echo "$env_result" | cut -d':' -f2)
    local current_shell=$(echo "$env_result" | cut -d':' -f3)

    # 4. 输出环境检测详情
    echo "========================================"
    echo "📊 环境检测详情："
    [ "$is_alpine" -eq 1 ] && echo "  系统类型：Alpine Linux" || echo "  系统类型：非Alpine Linux"
    [ "$has_bash" -eq 1 ] && echo "  bash状态：已安装（优先使用）" || echo "  bash状态：未安装"
    echo "  当前Shell：$current_shell"
    echo "========================================"

    # 5. 按规则执行对应脚本
    case "$is_alpine:$has_bash" in
        # 场景1：Alpine系统 + 已安装bash → 优先执行lm-bash.sh（bash环境完整功能）
        "1:1")
            echo "▶️ 执行：Alpine系统（含bash）→ $LM_SH（bash调用）"
            bash "$LM_SH"
            ;;
        # 场景2：Alpine系统 + 无bash → 执行lm-alpine.sh（仅ash环境适配）
        "1:0")
            echo "▶️ 执行：Alpine系统（仅ash）→ $LM_ALPINE_SH（ash调用）"
            sh "$LM_ALPINE_SH"
            ;;
        # 场景3：非Alpine系统 + 有bash → 执行lm-bash.sh（bash完整功能）
        "0:1")
            echo "▶️ 执行：非Alpine系统（bash环境）→ $LM_SH（bash调用）"
            bash "$LM_SH"
            ;;
        # 场景4：非Alpine系统 + 无bash → 降级执行lm-bash.sh基础功能（避免语法报错）
        "0:0")
            echo "⚠️ 执行：非Alpine系统（无bash）→ 降级运行lm-bash.sh基础功能"
            echo "   （仅执行：安装依赖 + 配置SSH，跳过bash特有语法功能）"
            sh "$LM_SH" install_deps && sh "$LM_SH" config_ssh
            ;;
    esac

    # 6. 执行结果反馈
    local exit_code=$?
    echo -e "\n========================================"
    if [ "$exit_code" -eq 0 ]; then
        echo "✅ 脚本执行成功！"
        # 额外提示：Alpine含bash场景的优势
        if [ "$is_alpine" -eq 1 ] && [ "$has_bash" -eq 1 ]; then
            echo "ℹ️  提示：Alpine已安装bash，后续可直接执行 'bash $LM_SH' 调用完整功能"
        fi
    else
        echo "❌ 脚本执行失败（退出码：$exit_code）" >&2
        echo "   📌 排查方向：1. 网络是否正常 2. 脚本路径是否正确 3. 是否有root权限" >&2
    fi
    echo "========================================"
    exit "$exit_code"
}

# 启动主逻辑（传递参数，支持命令行调用lm-bash.sh函数）
main "$@"
