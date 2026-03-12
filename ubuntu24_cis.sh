#!/bin/bash

# Ubuntu 24.04 CIS加固脚本
# 基于ansible-lockdown/UBUNTU24-CIS仓库
# 参考CIS Ubuntu 24.04 Benchmark v1.0.0

set -e

echo "开始Ubuntu 24.04 CIS加固..."

# 检查系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$NAME" == "Ubuntu" && "$VERSION_ID" == "24.04" ]]; then
            echo "检测到Ubuntu 24.04系统"
            return 0
        else
            echo "错误: 此脚本仅适用于Ubuntu 24.04系统"
            return 1
        fi
    else
        echo "错误: 无法检测系统类型"
        return 1
    fi
}

# 系统更新
update_system() {
    echo "更新系统包..."
    apt-get update && apt-get upgrade -y
    apt-get autoremove -y
    apt-get autoclean -y
}

# 安装必要的包
install_packages() {
    echo "安装必要的包..."
    apt-get install -y \n        auditd \n        cron \n        libpam-modules \n        openssh-server \n        ufw \n        fail2ban \n        logrotate \n        debsums \n        aptitude
}

# 1. 文件系统安全
section_1() {
    echo "执行第1节: 文件系统安全..."
    
    # 1.1.1 确保/etc目录权限正确
    chmod 755 /etc
    
    # 1.1.2 确保重要文件权限正确
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 644 /etc/group
    chmod 600 /etc/gshadow
    chmod 644 /etc/sudoers
    chmod 750 /etc/sudoers.d
    
    # 1.1.3 确保/tmp目录配置正确
    if ! grep -q "^tmpfs /tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    
    # 1.2.1 禁用不必要的文件系统
    cat > /etc/modprobe.d/blacklist-filesystems.conf << 'EOF'
# 禁用不必要的文件系统
blacklist cramfs
blacklist freevxfs
blacklist jffs2
blacklist hfs
blacklist hfsplus
blacklist squashfs
blacklist udf
EOF
    
    # 1.3.1 确保文件系统完整性检查
    apt-get install -y e2fsprogs
    for fs in $(lsblk -no MOUNTPOINT,FSTYPE | grep -E 'ext[234]|btrfs' | awk '{print $1}'); do
        if [ -n "$fs" ] && [ "$fs" != "/" ]; then
            tune2fs -c 30 "$(findmnt -n -o SOURCE "$fs")" || true
        fi
    done
    
    # 1.4 确保 sticky bit设置
    chmod +t /tmp
    chmod +t /var/tmp
    
    # 1.5 确保nosuid和noexec设置
    if ! grep -q "^/tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    if ! grep -q "^/var/tmp" /etc/fstab; then
        echo "tmpfs /var/tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
}

# 2. 系统服务
section_2() {
    echo "执行第2节: 系统服务..."
    
    # 2.1 禁用不必要的服务
    services_to_disable=("avahi-daemon" "bluetooth" "cups" "isc-dhcp-server" "nfs-common" "rpcbind" "samba" "winbind")
    for service in "${services_to_disable[@]}"; do
        systemctl disable --now "$service" 2>/dev/null || true
    done
    
    # 2.2 确保关键服务启用
    services_to_enable=("auditd" "cron" "ssh" "ufw" "fail2ban")
    for service in "${services_to_enable[@]}"; do
        systemctl enable --now "$service" 2>/dev/null || true
    done
}

# 3. 网络配置
section_3() {
    echo "执行第3节: 网络配置..."
    
    # 3.1 配置UFW防火墙
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw enable
    
    # 3.2 配置网络参数
    cat > /etc/sysctl.d/99-cis.conf << 'EOF'
# CIS网络安全参数
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
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF
    sysctl -p /etc/sysctl.d/99-cis.conf
    
    # 3.3 禁用IPv6（如果不需要）
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-cis.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.d/99-cis.conf
    sysctl -p /etc/sysctl.d/99-cis.conf
}

# 4. 日志和审计
section_4() {
    echo "执行第4节: 日志和审计..."
    
    # 4.1 配置auditd
    cat > /etc/audit/auditd.conf << 'EOF'
local_events = yes
write_logs = yes
log_file = /var/log/audit/audit.log
log_group = adm
log_format = RAW
flush = INCREMENTAL_ASYNC
freq = 50
max_log_file = 8
num_logs = 5
priority_boost = 4
disp_qos = lossy
dispatcher = /usr/sbin/audispd
name_format = NONE
##name = mydomain
max_log_file_action = ROTATE
space_left = 75
space_left_action = SYSLOG
action_mail_acct = root
examine_watchdirs = no
EOF
    systemctl enable --now auditd
    
    # 4.2 配置审计规则
    cat > /etc/audit/rules.d/audit.rules << 'EOF'
# 系统调用审计
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# 认证和授权
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# 系统管理员操作
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# 网络配置
-w /etc/network/ -p wa -k network
-w /etc/netplan/ -p wa -k network

# 日志配置
-w /etc/rsyslog.conf -p wa -k logging
-w /etc/logrotate.conf -p wa -k logging

# 内核模块
-w /lib/modules/ -p wa -k modules
-w /etc/modules -p wa -k modules
-w /etc/modules-load.d/ -p wa -k modules
EOF
    systemctl restart auditd
    
    # 4.3 配置rsyslog
    cat > /etc/rsyslog.d/50-default.conf << 'EOF'
# 系统日志配置
*.*;auth,authpriv.none          -/var/log/syslog
auth,authpriv.*                /var/log/auth.log
*.*;auth,authpriv.none,cron.none  -/var/log/messages
cron.*                        /var/log/cron.log
daemon.*                      -/var/log/daemon.log
kern.*                        -/var/log/kern.log
lpr.*                         -/var/log/lpr.log
mail.*                        -/var/log/mail.log
user.*                        -/var/log/user.log

# 紧急消息
*.emerg                       :omusrmsg:*

# 远程日志（如果需要）
# *.* @remote-log-server:514
EOF
    systemctl restart rsyslog
}

# 5. 访问控制
section_5() {
    echo "执行第5节: 访问控制..."
    
    # 5.1 配置PAM
    cat > /etc/pam.d/common-password << 'EOF'
# PAM密码配置
password        [success=1 default=ignore]      pam_unix.so obscure sha512
password        [success=1 default=ignore]      pam_ldap.so use_authtok try_first_pass
password        requisite                       pam_pwquality.so retry=3 minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1
password        required                        pam_deny.so
EOF
    
    # 5.2 配置登录定义
    cat > /etc/login.defs << 'EOF'
# 登录定义
MAIL_DIR        /var/mail
PASS_MAX_DAYS   90
PASS_MIN_DAYS   7
PASS_WARN_AGE   7
UID_MIN         1000
UID_MAX         60000
GID_MIN         1000
GID_MAX         60000
CREATE_HOME     yes
UMASK           027
USERGROUPS_ENAB yes
ENCRYPT_METHOD  SHA512
EOF
    
    # 5.3 配置sudo
    cat > /etc/sudoers.d/01-cis << 'EOF'
# CIS sudo配置
Defaults        env_reset
Defaults        mail_badpass
Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults        !tty_tickets
Defaults        timestamp_timeout=15

# 允许wheel组使用sudo
%wheel ALL=(ALL:ALL) ALL

# 日志记录
Defaults        logfile="/var/log/sudo.log"
Defaults        log_input
Defaults        log_output
EOF
    
    # 5.4 配置SSH
    cat > /etc/ssh/sshd_config << 'EOF'
# SSH配置
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# 安全设置
PermitRootLogin no
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 3

# 认证
PubkeyAuthentication yes
AuthorizedKeysFile     .ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# 日志
SyslogFacility AUTH
LogLevel INFO

# 其他
X11Forwarding no
AllowTcpForwarding yes
PermitTunnel no
AllowAgentForwarding yes

# 匹配规则
Match Group admin
    AllowTcpForwarding yes
EOF
    systemctl restart sshd
}

# 6. 系统维护
section_6() {
    echo "执行第6节: 系统维护..."
    
    # 6.1 配置自动更新
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    
    # 6.2 配置logrotate
    cat > /etc/logrotate.d/syslog << 'EOF'
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
    rotate 4
    weekly
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF
    
    # 6.3 检查系统完整性
    debsums -c || true
}

# 7. 额外安全措施
section_7() {
    echo "执行第7节: 额外安全措施..."
    
    # 7.1 配置fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
ignoreip = 127.0.0.1/8
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
    systemctl restart fail2ban
    
    # 7.2 禁用不必要的SUID/SGID程序
    suid_sgid_files=("/usr/bin/chfn" "/usr/bin/chsh" "/usr/bin/newgrp" "/usr/bin/passwd" "/usr/bin/su" "/usr/bin/sudo")
    for file in "${suid_sgid_files[@]}"; do
        if [ -f "$file" ]; then
            chmod u-s "$file" 2>/dev/null || true
        fi
    done
    
    # 7.3 配置系统限制
    cat > /etc/security/limits.d/99-cis-limits.conf << 'EOF'
# CIS系统限制
* soft nofile 1024
* hard nofile 4096
* soft nproc 1024
* hard nproc 4096
* soft core 0
* hard core 0
EOF
}

# 主函数
main() {
    detect_os || exit 1
    update_system
    install_packages
    section_1
    section_2
    section_3
    section_4
    section_5
    section_6
    section_7
    
    echo "Ubuntu 24.04 CIS加固完成！"
    echo "建议重启系统以应用所有配置更改"
}

# 执行主函数
main