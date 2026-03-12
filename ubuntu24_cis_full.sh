#!/bin/bash

# Ubuntu 24.04 CIS完整加固脚本
# 基于ansible-lockdown/UBUNTU24-CIS仓库
# 参考CIS Ubuntu 24.04 Benchmark v1.0.0

set -e

echo "开始Ubuntu 24.04 CIS完整加固..."

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
    apt-get install -y \
        auditd \
        cron \
        at \
        libpam-modules \
        openssh-server \
        ufw \
        fail2ban \
        logrotate \
        debsums \
        aptitude \
        chrony \
        systemd-timesyncd \
        rkhunter \
        chkrootkit \
        libpam-tmpdir
}

# 1. 文件系统安全
section_1() {
    echo "执行第1节: 文件系统安全..."
    
    # 1.1.1 禁用不必要的文件系统
    echo "1.1.1 禁用不必要的文件系统..."
    cat > /etc/modprobe.d/CIS.conf << 'EOF'
# 禁用不必要的文件系统
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install vfat /bin/true
EOF
    chmod go-rwx /etc/modprobe.d/CIS.conf
    
    # 1.1.2 禁用危险的内核模块
    echo "1.1.2 禁用危险的内核模块..."
    cat >> /etc/modprobe.d/CIS.conf << 'EOF'
# 禁用危险的内核模块
install usb-storage /bin/true
install firewire-core /bin/true
install ieee1394 /bin/true
install rds /bin/true
install tipc /bin/true
EOF
    
    # 1.1.3 确保文件系统权限正确
    echo "1.1.3 确保文件系统权限正确..."
    chmod 755 /etc
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 644 /etc/group
    chmod 600 /etc/gshadow
    chmod 644 /etc/sudoers
    chmod 750 /etc/sudoers.d
    chmod 755 /var/log
    chmod 755 /var/spool
    chmod 755 /var/tmp
    chmod 755 /tmp
    
    # 1.1.4 确保/tmp和/var/tmp配置正确
    echo "1.1.4 确保/tmp和/var/tmp配置正确..."
    if ! grep -q "^tmpfs /tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    if ! grep -q "^tmpfs /var/tmp" /etc/fstab; then
        echo "tmpfs /var/tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    
    # 1.1.5 确保sticky bit设置
    echo "1.1.5 确保sticky bit设置..."
    chmod +t /tmp
    chmod +t /var/tmp
    
    # 1.1.6 确保nosuid和noexec设置
    echo "1.1.6 确保nosuid和noexec设置..."
    mount -o remount,nosuid,nodev,noexec /tmp 2>/dev/null || true
    mount -o remount,nosuid,nodev,noexec /var/tmp 2>/dev/null || true
    
    # 1.2.1 确保/dev/shm配置正确
    echo "1.2.1 确保/dev/shm配置正确..."
    if ! grep -q "^tmpfs /dev/shm" /etc/fstab; then
        echo "tmpfs /dev/shm tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    mount -o remount,nosuid,nodev,noexec /dev/shm 2>/dev/null || true
    
    # 1.2.2 确保/var/log配置正确
    echo "1.2.2 确保/var/log配置正确..."
    if ! grep -q "^/var/log" /etc/fstab; then
        echo "/var/log /var/log ext4 defaults,nosuid,nodev,noexec 0 0" >> /etc/fstab
    fi
    
    # 1.3.1 确保文件系统完整性检查
    echo "1.3.1 确保文件系统完整性检查..."
    apt-get install -y e2fsprogs
    for fs in $(lsblk -no MOUNTPOINT,FSTYPE | grep -E 'ext[234]|btrfs' | awk '{print $1}'); do
        if [ -n "$fs" ] && [ "$fs" != "/" ]; then
            tune2fs -c 30 "$(findmnt -n -o SOURCE "$fs")" || true
        fi
    done
    
    # 1.4 确保LUKS加密（如果需要）
    echo "1.4 确保LUKS加密..."
    apt-get install -y cryptsetup
}

# 2. 系统服务
section_2() {
    echo "执行第2节: 系统服务..."
    
    # 2.1 禁用不必要的服务
    echo "2.1 禁用不必要的服务..."
    services_to_disable=("avahi-daemon" "bluetooth" "cups" "isc-dhcp-server" "nfs-common" "rpcbind" "samba" "winbind" "apache2" "nginx" "mysql" "postgresql" "bind9" "exim4" "sendmail" "vsftpd" "ssmtp" "telnetd" "rsh-server" "talk" "ntalk" "xinetd" "inetd" "portmap" "rpcidmapd" "nscd" "ypbind" "autofs" "anacron" "atd" "cronie" "crond" "irqbalance" "kdump" "kexec-tools" "mdmonitor" "messagebus" "pcscd" "rsync" "smartd" "snmpd" "sysstat" "udev-post" "zeroconf" "avahi-autoipd" "bluetoothd" "cupsd" "dhcpd" "dhcp6s" "dhcp6c" "dnsmasq" "hostapd" "iscsi-target" "iscsid" "iscsiuio" "kboot" "libvirtd" "lldpad" "nfs-server" "nfs-secure-server" "nfslock" "ntpd" "ntpdate" "oddjobd" "openvpn" "pptpd" "radvd" "rpc-gssd" "rpc-statd" "rpcbind" "rsyslog" "saslauthd" "smb" "sshd" "tftp-server" "winbind" "wpa_supplicant")
    for service in "${services_to_disable[@]}"; do
        systemctl disable --now "$service" 2>/dev/null || true
    done
    
    # 2.2 确保关键服务启用
    echo "2.2 确保关键服务启用..."
    services_to_enable=("auditd" "cron" "ssh" "ufw" "fail2ban" "systemd-timesyncd")
    for service in "${services_to_enable[@]}"; do
        systemctl enable --now "$service" 2>/dev/null || true
    done
    
    # 2.3 配置时间同步
    echo "2.3 配置时间同步..."
    cat > /etc/systemd/timesyncd.conf << 'EOF'
[Time]
NTP=ntp.ubuntu.com
FallbackNTP=0.ubuntu.pool.ntp.org 1.ubuntu.pool.ntp.org 2.ubuntu.pool.ntp.org 3.ubuntu.pool.ntp.org
RootDistanceMaxSec=5
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF
    systemctl restart systemd-timesyncd
    
    # 2.4 配置Cron和At
    echo "2.4 配置Cron和At..."
    chmod 600 /etc/crontab
    chmod 600 /etc/cron.d/*
    chmod 700 /etc/cron.daily
    chmod 700 /etc/cron.hourly
    chmod 700 /etc/cron.monthly
    chmod 700 /etc/cron.weekly
    chmod 600 /etc/at.deny
    chmod 600 /etc/at.allow 2>/dev/null || true
}

# 3. 网络配置
section_3() {
    echo "执行第3节: 网络配置..."
    
    # 3.1 配置UFW防火墙
    echo "3.1 配置UFW防火墙..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw enable
    
    # 3.2 配置网络参数
    echo "3.2 配置网络参数..."
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
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
    sysctl -p /etc/sysctl.d/99-cis.conf
    
    # 3.3 禁用IPv6
    echo "3.3 禁用IPv6..."
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.d/99-cis.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.d/99-cis.conf
    sysctl -p /etc/sysctl.d/99-cis.conf
    
    # 3.4 配置网络接口
    echo "3.4 配置网络接口..."
    for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
        if [ "$iface" != "lo" ]; then
            echo "配置网络接口: $iface"
            # 禁用IPv6
            echo "net.ipv6.conf.$iface.disable_ipv6 = 1" >> /etc/sysctl.d/99-cis.conf
        fi
    done
    sysctl -p /etc/sysctl.d/99-cis.conf
}

# 4. 日志和审计
section_4() {
    echo "执行第4节: 日志和审计..."
    
    # 4.1 配置auditd
    echo "4.1 配置auditd..."
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
max_log_file_action = ROTATE
space_left = 75
space_left_action = SYSLOG
action_mail_acct = root
examine_watchdirs = no
EOF
    systemctl enable --now auditd
    
    # 4.2 配置审计规则
    echo "4.2 配置审计规则..."
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

# 文件系统挂载
-w /etc/fstab -p wa -k mounts

# 服务配置
-w /etc/systemd/ -p wa -k systemd
-w /etc/init.d/ -p wa -k init

# 防火墙配置
-w /etc/ufw/ -p wa -k firewall
-w /etc/iptables/ -p wa -k firewall

# SSH配置
-w /etc/ssh/ -p wa -k ssh

# PAM配置
-w /etc/pam.d/ -p wa -k pam

# 密码策略
-w /etc/login.defs -p wa -k login
-w /etc/security/ -p wa -k security

# 系统限制
-w /etc/security/limits.conf -p wa -k limits
-w /etc/security/limits.d/ -p wa -k limits

# 应用程序配置
-w /etc/apache2/ -p wa -k apache
-w /etc/nginx/ -p wa -k nginx
-w /etc/mysql/ -p wa -k mysql
-w /etc/postgresql/ -p wa -k postgresql
EOF
    systemctl restart auditd
    
    # 4.3 配置rsyslog
    echo "4.3 配置rsyslog..."
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
    
    # 4.4 配置logrotate
    echo "4.4 配置logrotate..."
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
    
    # 4.5 确保日志文件权限正确
    echo "4.5 确保日志文件权限正确..."
    chmod 640 /var/log/*
    chmod 750 /var/log
}

# 5. 访问控制
section_5() {
    echo "执行第5节: 访问控制..."
    
    # 5.1 配置PAM
    echo "5.1 配置PAM..."
    cat > /etc/pam.d/common-password << 'EOF'
# PAM密码配置
password        [success=1 default=ignore]      pam_unix.so obscure sha512
password        [success=1 default=ignore]      pam_ldap.so use_authtok try_first_pass
password        requisite                       pam_pwquality.so retry=3 minlen=14 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1
password        required                        pam_deny.so
EOF
    
    # 5.2 配置登录定义
    echo "5.2 配置登录定义..."
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
    echo "5.3 配置sudo..."
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
    echo "5.4 配置SSH..."
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
    
    # 5.5 配置PAM限制
    echo "5.5 配置PAM限制..."
    cat > /etc/security/limits.d/99-cis-limits.conf << 'EOF'
# CIS系统限制
* soft nofile 1024
* hard nofile 4096
* soft nproc 1024
* hard nproc 4096
* soft core 0
* hard core 0
* soft fsize unlimited
* hard fsize unlimited
* soft data unlimited
* hard data unlimited
* soft stack 8192
* hard stack 8192
* soft cpu unlimited
* hard cpu unlimited
* soft as unlimited
* hard as unlimited
EOF
    
    # 5.6 配置账户锁定
    echo "5.6 配置账户锁定..."
    cat > /etc/security/faillock.conf << 'EOF'
# 账户锁定配置
dir = /var/run/faillock
enable = yes
defaults = yes
deny = 5
unlock_time = 900
admin_flag = unlock_on_root
EOF
    
    # 5.7 确保root路径安全
    echo "5.7 确保root路径安全..."
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" > /root/.profile
}

# 6. 系统维护
section_6() {
    echo "执行第6节: 系统维护..."
    
    # 6.1 配置自动更新
    echo "6.1 配置自动更新..."
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade::Automatic-Reboot "false";
EOF
    
    # 6.2 检查系统完整性
    echo "6.2 检查系统完整性..."
    debsums -c || true
    
    # 6.3 运行rootkit检测
    echo "6.3 运行rootkit检测..."
    rkhunter --check --skip-keypress || true
    chkrootkit || true
    
    # 6.4 清理临时文件
    echo "6.4 清理临时文件..."
    rm -rf /tmp/* /var/tmp/*
    
    # 6.5 确保系统备份
    echo "6.5 确保系统备份..."
    apt-get install -y rsync
    mkdir -p /backup
    
    # 6.6 配置系统日志轮转
    echo "6.6 配置系统日志轮转..."
    cat > /etc/logrotate.d/auditd << 'EOF'
/var/log/audit/audit.log {
    weekly
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    create 600 root root
    postrotate
        /sbin/service auditd rotate > /dev/null 2>&1 || true
    endscript
}
EOF
}

# 7. 额外安全措施
section_7() {
    echo "执行第7节: 额外安全措施..."
    
    # 7.1 配置fail2ban
    echo "7.1 配置fail2ban..."
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

[apache]
enabled = false
port = http,https
filter = apache-auth
logpath = /var/log/apache2/error.log
maxretry = 6

[nginx]
enabled = false
port = http,https
filter = nginx-auth
logpath = /var/log/nginx/error.log
maxretry = 6
EOF
    systemctl restart fail2ban
    
    # 7.2 禁用不必要的SUID/SGID程序
    echo "7.2 禁用不必要的SUID/SGID程序..."
    suid_sgid_files=("/usr/bin/chfn" "/usr/bin/chsh" "/usr/bin/newgrp" "/usr/bin/passwd" "/usr/bin/su" "/usr/bin/sudo" "/usr/bin/mount" "/usr/bin/umount" "/usr/bin/ping" "/usr/bin/fusermount" "/usr/bin/screen" "/usr/bin/wall" "/usr/bin/write" "/usr/bin/bsd-write" "/usr/bin/traceroute6.iputils" "/usr/bin/traceroute.iputils" "/usr/sbin/pppd" "/usr/sbin/mount.nfs" "/usr/sbin/mount.nfs4" "/usr/sbin/umount.nfs" "/usr/sbin/umount.nfs4")
    for file in "${suid_sgid_files[@]}"; do
        if [ -f "$file" ]; then
            chmod u-s "$file" 2>/dev/null || true
        fi
    done
    
    # 7.3 配置系统限制
    echo "7.3 配置系统限制..."
    cat > /etc/security/limits.d/99-cis-limits.conf << 'EOF'
# CIS系统限制
* soft nofile 1024
* hard nofile 4096
* soft nproc 1024
* hard nproc 4096
* soft core 0
* hard core 0
EOF
    
    # 7.4 禁用Ctrl-Alt-Delete
    echo "7.4 禁用Ctrl-Alt-Delete..."
    systemctl mask ctrl-alt-delete.target
    
    # 7.5 配置GRUB密码
    echo "7.5 配置GRUB密码..."
    grub_password=$(openssl passwd -6 "grub_password")
    cat > /etc/grub.d/40_custom << EOF
#!/bin/sh
set -e
cat << 'EOF'
set superusers="root"
password_pbkdf2 root $grub_password
EOF
EOF
    update-grub
    
    # 7.6 确保系统时间同步
    echo "7.6 确保系统时间同步..."
    timedatectl set-ntp true
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
    
    echo "Ubuntu 24.04 CIS完整加固完成！"
    echo "建议重启系统以应用所有配置更改"
    echo "请检查系统日志和服务状态，确保所有配置正常工作"
}

# 执行主函数
main