#!/bin/bash
# 软件源管理模块

# 引入通用脚本
source "$(dirname "$0")/common.sh"

# --- 内部函数 ---
backup_sources() {
    msg_info "正在备份当前源..."
    case $OS in
        debian|ubuntu)
            [ ! -f /etc/apt/sources.list.bak ] && sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
            ;;
        centos|rhel|fedora)
            sudo mkdir -p /etc/yum.repos.d/bak
            # 只有在bak目录为空时才移动，避免覆盖原始备份
            [ -z "$(ls -A /etc/yum.repos.d/bak)" ] && sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ || true
            ;;
        *)
            msg_warn "当前系统 $OS 的源备份逻辑未实现。"
            ;;
    esac
}

set_mirror() {
    local provider=$1
    local mirror_url=""
    check_sudo

    msg_info "准备切换到 $provider 源..."
    backup_sources

    case $OS in
        debian|ubuntu)
            case $provider in
                aliyun) mirror_url="mirrors.aliyun.com" ;;
                tencent) mirror_url="mirrors.tencent.com" ;;
                huawei) mirror_url="repo.huaweicloud.com" ;;
            esac
            local proto="https"
            [ "$provider" == "tencent" ] && proto="http"

            if [ "$OS" = "debian" ]; then
                sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${proto}://${mirror_url}/debian/ ${OS_VERSION_CODENAME} main contrib non-free
deb ${proto}://${mirror_url}/debian/ ${OS_VERSION_CODENAME}-updates main contrib non-free
deb ${proto}://${mirror_url}/debian-security/ ${OS_VERSION_CODENAME}-security main contrib non-free
EOF
            else # ubuntu
                sudo tee /etc/apt/sources.list > /dev/null <<EOF
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME} main restricted universe multiverse
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME}-updates main restricted universe multiverse
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME}-backports main restricted universe multiverse
deb ${proto}://${mirror_url}/ubuntu/ ${OS_VERSION_CODENAME}-security main restricted universe multiverse
EOF
            fi
            msg_info "正在刷新APT缓存..."
            sudo apt-get update
            ;;
        centos|rhel)
             case $provider in
                aliyun) repo_url="https://mirrors.aliyun.com/repo/Centos-${OS_VERSION_ID}.repo" ;;
                tencent) repo_url="http://mirrors.tencent.com/repo/centos${OS_VERSION_ID}_tencent_tsinghua.repo" ;;
                huawei) repo_url="https://repo.huaweicloud.com/repository/conf/CentOS-${OS_VERSION_ID}-reg.repo" ;;
            esac
            sudo rm -f /etc/yum.repos.d/*.repo
            sudo curl -o /etc/yum.repos.d/${provider}.repo ${repo_url}
            msg_info "正在刷新YUM缓存..."
            sudo yum clean all && sudo yum makecache
            ;;
        *)
            msg_error "当前操作系统 $OS 的自动切换源功能暂不支持。"
            return 1
            ;;
    esac
    msg_ok "已成功切换到 ${provider} 源。"
}

restore_sources() {
    check_sudo
    msg_info "正在恢复原始备份源..."
    case $OS in
        debian|ubuntu)
            if [ -f /etc/apt/sources.list.bak ]; then
                sudo mv /etc/apt/sources.list.bak /etc/apt/sources.list
                sudo apt-get update
                msg_ok "APT源已恢复。"
            else
                msg_warn "未找到APT源备份文件。"
            fi
            ;;
        centos|rhel|fedora)
            if [ -d /etc/yum.repos.d/bak ] && [ -n "$(ls -A /etc/yum.repos.d/bak)" ]; then
                sudo rm -f /etc/yum.repos.d/*.repo
                sudo mv /etc/yum.repos.d/bak/* /etc/yum.repos.d/
                sudo rmdir /etc/yum.repos.d/bak
                sudo $PKG_MANAGER clean all && sudo $PKG_MANAGER makecache
                msg_ok "YUM/DNF源已恢复。"
            else
                msg_warn "未找到YUM/DNF源备份文件。"
            fi
            ;;
        *)
            msg_error "当前系统 $OS 的源恢复逻辑未实现。"
            ;;
    esac
}

status_sources() {
    echo -n "   软件源: "
    local current_source="未知或官方源"
    local source_file=""

    if [ "$OS" = "debian" ] || [ "$OS" = "ubuntu" ]; then
        source_file="/etc/apt/sources.list"
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        source_file=$(ls /etc/yum.repos.d/*.repo 2>/dev/null | head -n 1)
    fi

    if [ -n "$source_file" ] && [ -f "$source_file" ]; then
        if grep -q "aliyun" "$source_file"; then
            current_source="阿里云"
        elif grep -q "tencent" "$source_file"; then
            current_source="腾讯云"
        elif grep -q "huaweicloud" "$source_file"; then
            current_source="华为云"
        elif grep -q -E "debian.org|ubuntu.com|centos.org" "$source_file"; then
            current_source="官方源"
        fi
    fi
    echo -e "${C_CYAN}${current_source}${C_RESET}"
}

# --- 主逻辑 ---
case "$1" in
    set)
        set_mirror "$2"
        ;;
    restore)
        restore_sources
        ;;
    status)
        status_sources
        ;;
    *)
        msg_error "用法: $0 {set <aliyun|tencent|huawei> | restore | status}"
        exit 1
        ;;
esac
