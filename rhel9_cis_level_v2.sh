#!/bin/bash

# RHEL 9 / CentOS 9 CIS加固脚本 V2（基于官方RHEL9-CIS仓库）
# 支持Level 1和Level 2选择
# 基于CIS Red Hat Enterprise Linux 9 Benchmark v2.0.0

set -e

echo "RHEL 9 / CentOS 9 CIS加固脚本 V2"
echo "==================================="
echo "基于官方ansible-lockdown/RHEL9-CIS仓库"
echo ""
echo "CIS标准分为Level 1和Level 2两个安全级别："
echo "- Level 1：基础安全加固，适用于大多数系统"
echo "- Level 2：高级安全加固，适用于需要更高级别安全的系统"
echo ""

# 选择加固级别
read -p "请选择加固级别 (1/2): " LEVEL

if [[ "$LEVEL" != "1" && "$LEVEL" != "2" ]]; then
    echo "错误: 请输入有效的级别 (1/2)"
    exit 1
fi

echo ""
echo "开始RHEL 9 / CentOS 9 CIS Level $LEVEL加固..."
echo "==================================="

# 检查系统类型
detect_os() {
    if [ -f /etc/redhat-release ]; then
        if grep -q "release 9" /etc/redhat-release; then
            echo "检测到RHEL/CentOS 9系统"
            return 0
        else
            echo "错误: 此脚本仅适用于RHEL/CentOS 9系统"
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
    dnf update -y
    dnf autoremove -y
    dnf clean all
}

# 安装必要的包
install_packages() {
    echo "安装必要的包..."
    dnf install -y \
        audit \
        cronie \
        openssh-server \
        firewalld \
        fail2ban \
        fail2ban-firewalld \
        logrotate \
        yum-utils \
        chrony \
        aide \
        rsyslog \
        policycoreutils-python-utils
    
    # Level 2额外安装的包
    if [ "$LEVEL" == "2" ]; then
        echo "安装Level 2额外的包..."
        dnf install -y \
            rkhunter \
            chkrootkit \
            openscap-scanner \
            scap-security-guide
    fi
}

# 1. 初始设置
section_1() {
    echo "执行第1节: 初始设置..."
    
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
    
    # 1.1.3 确保/tmp和/var/tmp配置正确
    echo "1.1.3 确保/tmp和/var/tmp配置正确..."
    if ! grep -q "^tmpfs /tmp" /etc/fstab; then
        echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    if ! grep -q "^tmpfs /var/tmp" /etc/fstab; then
        echo "tmpfs /var/tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    
    # 1.1.4 确保sticky bit设置
    echo "1.1.4 确保sticky bit设置..."
    chmod +t /tmp
    chmod +t /var/tmp
    
    # 1.2.1 确保/dev/shm配置正确
    echo "1.2.1 确保/dev/shm配置正确..."
    if ! grep -q "^tmpfs /dev/shm" /etc/fstab; then
        echo "tmpfs /dev/shm tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
    fi
    mount -o remount,nosuid,nodev,noexec /dev/shm 2>/dev/null || true
    
    # 1.3.1 确保AIDE已安装
    echo "1.3.1 确保AIDE已安装..."
    dnf install -y aide
    if [ "$LEVEL" == "2" ]; then
        aide --init
        cp /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    fi
    
    # 1.4.1 确保引导加载程序密码已设置
    echo "1.4.1 确保引导加载程序密码已设置..."
    if [ "$LEVEL" == "2" ]; then
        grub2-setpassword <<EOF
grub_password
grub_password
EOF
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
    
    # 1.5.1 确保核心转储受到限制
    echo "1.5.1 确保核心转储受到限制..."
    echo "* hard core 0" >> /etc/security/limits.conf
    echo "fs.suid_dumpable = 0" >> /etc/sysctl.conf
    sysctl -p
    
    # 1.6.1 确保SELinux已安装并启用
    echo "1.6.1 确保SELinux已安装并启用..."
    dnf install -y policycoreutils-python-utils
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    setenforce 1 2>/dev/null || true
    
    # 1.7.1 确保消息传递已配置
    echo "1.7.1 确保消息传递已配置..."
    echo "Authorized users only. All activity may be monitored and reported." > /etc/motd
    
    # 1.8.1 确保GNOME显示管理器已配置（如果安装了GUI）
    if [ "$LEVEL" == "2" ]; then
        echo "1.8.1 确保GNOME显示管理器已配置..."
        if command -v gdm &> /dev/null; then
            echo "user-db:user" > /etc/dconf/profile/gdm
            echo "system-db:gdm" >> /etc/dconf/profile/gdm
            echo "file-db:/usr/share/gdm/greeter-dconf-defaults" >> /etc/dconf/profile/gdm
        fi
    fi
}

# 2. 服务配置
section_2() {
    echo "执行第2节: 服务配置..."
    
    # 2.1.1 确保时间同步已配置
    echo "2.1.1 确保时间同步已配置..."
    dnf install -y chrony
    cat > /etc/chrony.conf << 'EOF'
# 使用NTP服务器池
pool 2.rhel.pool.ntp.org iburst
# 记录日志
logdir /var/log/chrony
# 允许系统时钟快/慢调整
makestep 1.0 3
# 记录drift值
driftfile /var/lib/chrony/drift
# 允许与本地系统时钟比较精度
rtcsync
EOF
    systemctl enable --now chronyd
    
    # 2.2.1 确保Cron守护进程已启用
    echo "2.2.1 确保Cron守护进程已启用..."
    systemctl enable --now crond
    
    # 2.2.2 确保Cron权限已配置
    echo "2.2.2 确保Cron权限已配置..."
    chmod 600 /etc/crontab
    chmod 600 /etc/cron.d/*
    chmod 700 /etc/cron.daily
    chmod 700 /etc/cron.hourly
    chmod 700 /etc/cron.monthly
    chmod 700 /etc/cron.weekly
    
    # 2.3.1 确保SSH服务器已配置
    echo "2.3.1 确保SSH服务器已配置..."
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
EOF
    systemctl restart sshd
    
    # 2.4.1 确保系统日志记录已启用
    echo "2.4.1 确保系统日志记录已启用..."
    systemctl enable --now rsyslog
}

# 3. 网络配置
section_3() {
    echo "执行第3节: 网络配置..."
    
    # 3.1.1 确保firewalld已安装并启用
    echo "3.1.1 确保firewalld已安装并启用..."
    dnf install -y firewalld
    systemctl enable --now firewalld
    firewall-cmd --set-default-zone=drop
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
    
    # 3.2.1 确保网络参数已配置
    echo "3.2.1 确保网络参数已配置..."
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
EOF
    
    # Level 2额外的网络安全参数
    if [ "$LEVEL" == "2" ]; then
        cat >> /etc/sysctl.d/99-cis.conf << 'EOF'
# Level 2: 额外的网络安全参数
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
    fi
    
    sysctl -p /etc/sysctl.d/99-cis.conf
}

# 4. 日志和审计
section_4() {
    echo "执行第4节: 日志和审计..."
    
    # 4.1.1 确保auditd已安装并启用
    echo "4.1.1 确保auditd已安装并启用..."
    dnf install -y audit
    systemctl enable --now auditd
    
    # 4.1.2 确保auditd服务已启用
    echo "4.1.2 确保auditd服务已启用..."
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
    systemctl restart auditd
    
    # 4.1.3 确保审计规则已配置
    echo "4.1.3 确保审计规则已配置..."
    cat > /etc/audit/rules.d/audit.rules << 'EOF'
# 删除所有现有规则
-D

# 设置缓冲区大小
-b 8192

# 监控特权命令
-a always,exit -F arch=b64 -S setuid -S setgid -S setreuid -S setregid -k privilege_escalation
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k privilege_escalation
-a always,exit -F arch=b64 -S execve -C gid!=egid -F egid=0 -k privilege_escalation

# 监控用户和组修改
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# 监控sudoers文件
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# 监控SELinux配置
-w /etc/selinux/ -p wa -k MAC-policy

# 监控登录和注销
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins

# 监控会话启动信息
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# 监控对sudo日志文件的更改
-w /var/log/sudo.log -p wa -k sudo_log_file

# 使配置立即生效
-e 2
EOF
    
    # Level 2额外的审计规则
    if [ "$LEVEL" == "2" ]; then
        cat >> /etc/audit/rules.d/audit.rules << 'EOF'
# Level 2: 额外的审计规则
# 监控网络配置
-w /etc/sysconfig/network-scripts/ -p wa -k network
-w /etc/sysctl.conf -p wa -k network
-w /etc/sysctl.d/ -p wa -k network

# 监控SSH配置
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/ssh_config -p wa -k ssh_config

# 监控PAM配置
-w /etc/pam.d/ -p wa -k pam

# 监控系统启动配置
-w /etc/grub2.cfg -p wa -k grub
-w /etc/grub.d/ -p wa -k grub
EOF
    fi
    
    systemctl restart auditd
}

# 5. 访问控制
section_5() {
    echo "执行第5节: 访问控制..."
    
    # 5.1.1 确保密码创建要求已配置
    echo "5.1.1 确保密码创建要求已配置..."
    cat > /etc/security/pwquality.conf << 'EOF'
# 密码质量要求
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
minclass = 4
maxrepeat = 2
maxclassrepeat = 4
gecoscheck = 1
EOF
    
    # 5.2.1 确保密码过期策略已配置
    echo "5.2.1 确保密码过期策略已配置..."
    cat > /etc/login.defs << 'EOF'
# 登录定义
MAIL_DIR        /var/spool/mail
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
    
    # 5.3.1 确保PAM已配置
    echo "5.3.1 确保PAM已配置..."
    cat > /etc/pam.d/system-auth << 'EOF'
# PAM配置
auth        required      pam_env.so
auth        required      pam_faildelay.so delay=2000000
auth        sufficient    pam_unix.so nullok try_first_pass
auth        requisite     pam_succeed_if.so uid >= 1000 quiet_success
auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 1000 quiet
account     required      pam_permit.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=
password    sufficient    pam_unix.so sha512 shadow nullok try_first_pass use_authtok
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so
EOF
    
    # 5.4.1 确保用户账户和环境已配置
    echo "5.4.1 确保用户账户和环境已配置..."
    # 删除不安全的账户
    for user in games ftp nobody; do
        userdel "$user" 2>/dev/null || true
    done
    
    # 5.5.1 确保root登录已限制
    echo "5.5.1 确保root登录已限制..."
    echo "tty1" > /etc/securetty
    
    # 5.6.1 确保sudo已配置
    echo "5.6.1 确保sudo已配置..."
    cat > /etc/sudoers.d/01-cis << 'EOF'
# CIS sudo配置
Defaults        env_reset
Defaults        mail_badpass
Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults        !tty_tickets
Defaults        timestamp_timeout=15
Defaults        logfile="/var/log/sudo.log"
Defaults        log_input
Defaults        log_output

# 允许wheel组使用sudo
%wheel ALL=(ALL:ALL) ALL
EOF
    chmod 440 /etc/sudoers.d/01-cis
    
    # Level 2额外的访问控制
    if [ "$LEVEL" == "2" ]; then
        echo "5.7.1 Level 2: 确保账户锁定已配置..."
        cat > /etc/security/faillock.conf << 'EOF'
# 账户锁定配置
dir = /var/run/faillock
enable = yes
defaults = yes
deny = 5
unlock_time = 900
admin_flag = unlock_on_root
EOF
        
        echo "5.8.1 Level 2: 确保系统限制已配置..."
        cat > /etc/security/limits.d/99-cis-limits.conf << 'EOF'
# CIS系统限制
* soft nofile 1024
* hard nofile 4096
* soft nproc 1024
* hard nproc 4096
* soft core 0
* hard core 0
EOF
    fi
}

# 6. 系统维护
section_6() {
    echo "执行第6节: 系统维护..."
    
    # 6.1.1 确保系统文件权限已配置
    echo "6.1.1 确保系统文件权限已配置..."
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 644 /etc/group
    chmod 600 /etc/gshadow
    chmod 640 /etc/sudoers
    chmod 750 /etc/sudoers.d
    
    # 6.2.1 确保没有SUID/SGID的可执行文件存在
    echo "6.2.1 确保没有SUID/SGID的可执行文件存在..."
    # 查找并记录SUID/SGID文件
    find / -type f -perm /6000 -exec ls -l {} \; > /tmp/suid_sgid_files.txt 2>/dev/null || true
    echo "SUID/SGID文件已记录到 /tmp/suid_sgid_files.txt"
    
    # 6.3.1 确保软件包管理器已配置
    echo "6.3.1 确保软件包管理器已配置..."
    dnf install -y dnf-automatic
    cat > /etc/dnf/automatic.conf << 'EOF'
[commands]
upgrade_type = default
random_sleep = 300
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio

[base]
debuglevel = 1
EOF
    systemctl enable --now dnf-automatic.timer
    
    # Level 2额外的系统维护
    if [ "$LEVEL" == "2" ]; then
        echo "6.4.1 Level 2: 运行rootkit检测..."
        if command -v rkhunter &> /dev/null; then
            rkhunter --check --skip-keypress || true
        fi
        if command -v chkrootkit &> /dev/null; then
            chkrootkit || true
        fi
        
        echo "6.5.1 Level 2: 清理临时文件..."
        rm -rf /tmp/* /var/tmp/*
    fi
}

# 7. 系统加固选项
section_7() {
    echo "执行第7节: 系统加固选项..."
    
    # 7.1.1 确保警告横幅已配置
    echo "7.1.1 确保警告横幅已配置..."
    cat > /etc/issue << 'EOF'
Authorized users only. All activity may be monitored and reported.
EOF
    cat > /etc/issue.net << 'EOF'
Authorized users only. All activity may be monitored and reported.
EOF
    
    # 7.2.1 确保GDM登录横幅已配置
    if [ "$LEVEL" == "2" ]; then
        echo "7.2.1 Level 2: 确保GDM登录横幅已配置..."
        if [ -d /etc/dconf/db/gdm.d ]; then
            cat > /etc/dconf/db/gdm.d/01-banner-message << 'EOF'
[org/gnome/login-screen]
banner-message-enable=true
banner-message-text='Authorized users only. All activity may be monitored and reported.'
EOF
            dconf update
        fi
    fi
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
    
    echo ""
    echo "RHEL 9 / CentOS 9 CIS Level $LEVEL加固完成！"
    echo "==================================="
    echo "基于官方ansible-lockdown/RHEL9-CIS仓库"
    echo ""
    echo "建议重启系统以应用所有配置更改"
    echo "请检查系统日志和服务状态，确保所有配置正常工作"
    echo ""
    echo "可以使用以下命令检查CIS合规性："
    echo "  oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_cis_level1_server /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml"
}

# 执行主函数
main
