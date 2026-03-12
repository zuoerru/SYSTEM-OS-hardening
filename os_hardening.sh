#!/bin/bash

# 系统OS加固脚本 - 基于CIS标准
# 参考dev-sec/ansible-os-hardening角色

set -e

echo "开始系统OS加固..."

# 检查系统类型
detect_os() {
    if [ -f /etc/redhat-release ]; then
        echo "检测到RHEL/CentOS系统"
        OS_TYPE="rhel"
    elif [ -f /etc/debian_version ]; then
        echo "检测到Debian/Ubuntu系统"
        OS_TYPE="debian"
    else
        echo "警告: 无法检测系统类型，将使用通用配置"
        OS_TYPE="generic"
    fi
}

# 系统更新
update_system() {
    echo "更新系统包..."
    if [ "$OS_TYPE" = "rhel" ]; then
        yum update -y
    elif [ "$OS_TYPE" = "debian" ]; then
        apt-get update && apt-get upgrade -y
    fi
}

# 安装必要的包
install_packages() {
    echo "安装必要的包..."
    if [ "$OS_TYPE" = "rhel" ]; then
        yum install -y auditd cronie pam pam-devel
    elif [ "$OS_TYPE" = "debian" ]; then
        apt-get install -y auditd cron libpam-modules
    fi
}

# 配置auditd
configure_auditd() {
    echo "配置auditd..."
    if [ -f /etc/audit/auditd.conf ]; then
        sed -i 's/^max_log_file = .*/max_log_file = 100/' /etc/audit/auditd.conf
        sed -i 's/^max_log_file_action = .*/max_log_file_action = rotate/' /etc/audit/auditd.conf
        systemctl enable auditd
        systemctl start auditd
    fi
}

# 配置cron
configure_cron() {
    echo "配置cron..."
    if [ -f /etc/crontab ]; then
        chmod 600 /etc/crontab
        chmod 600 /etc/cron.d/*
    fi
    systemctl enable crond || systemctl enable cron
    systemctl start crond || systemctl start cron
}

# 配置登录定义
configure_login_defs() {
    echo "配置登录定义..."
    if [ -f /etc/login.defs ]; then
        sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
        sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 7/' /etc/login.defs
        sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE 7/' /etc/login.defs
        sed -i 's/^UID_MIN.*/UID_MIN 1000/' /etc/login.defs
        sed -i 's/^GID_MIN.*/GID_MIN 1000/' /etc/login.defs
    fi
}

# 配置资源限制
configure_limits() {
    echo "配置资源限制..."
    cat > /etc/security/limits.d/os-hardening.conf << 'EOF'
# 基于CIS标准的资源限制
* soft nofile 1024
* hard nofile 4096
* soft nproc 1024
* hard nproc 4096
EOF
}

# 最小化文件系统访问
minimize_fs_access() {
    echo "最小化文件系统访问..."
    chmod 700 /etc/crontab
    chmod 700 /etc/cron.d
    chmod 700 /etc/cron.daily
    chmod 700 /etc/cron.hourly
    chmod 700 /etc/cron.monthly
    chmod 700 /etc/cron.weekly
    chmod 600 /etc/passwd
    chmod 600 /etc/shadow
    chmod 600 /etc/group
    chmod 600 /etc/gshadow
}

# 配置PAM
configure_pam() {
    echo "配置PAM..."
    if [ "$OS_TYPE" = "rhel" ]; then
        if [ -f /etc/pam.d/system-auth ]; then
            sed -i '/pam_pwquality.so/s/$/ minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1/' /etc/pam.d/system-auth
        fi
    elif [ "$OS_TYPE" = "debian" ]; then
        if [ -f /etc/pam.d/common-password ]; then
            sed -i '/pam_unix.so/s/$/ sha512/' /etc/pam.d/common-password
        fi
    fi
}

# 配置SELinux
configure_selinux() {
    echo "配置SELinux..."
    if [ -f /etc/selinux/config ]; then
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        setenforce 1 || true
    fi
}

# 配置系统内核参数
configure_sysctl() {
    echo "配置系统内核参数..."
    cat > /etc/sysctl.d/99-os-hardening.conf << 'EOF'
# 基于CIS标准的内核参数配置

# 网络安全
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_rfc1337 = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 内存保护
kernel.randomize_va_space = 2
kernel.exec-shield = 1
kernel.sysrq = 0

# 文件系统
fs.suid_dumpable = 0
EOF
    sysctl -p /etc/sysctl.d/99-os-hardening.conf
}

# 清理SUID/SGID文件
cleanup_suid_sgid() {
    echo "清理SUID/SGID文件..."
    # 查找并记录SUID/SGID文件
    find / -type f -perm /6000 -exec ls -l {} \; > /tmp/suid_sgid_files.txt
    echo "SUID/SGID文件已记录到 /tmp/suid_sgid_files.txt"
}

# 主函数
main() {
    detect_os
    update_system
    install_packages
    configure_auditd
    configure_cron
    configure_login_defs
    configure_limits
    minimize_fs_access
    configure_pam
    configure_selinux
    configure_sysctl
    cleanup_suid_sgid
    
    echo "系统OS加固完成！"
    echo "请检查 /tmp/suid_sgid_files.txt 文件，确认SUID/SGID文件是否需要进一步处理"
}

# 执行主函数
main