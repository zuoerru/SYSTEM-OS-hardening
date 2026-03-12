#!/bin/bash

# CIS合规性检查脚本
# 使用OpenSCAP验证系统是否符合CIS标准
# 支持RHEL 9 / CentOS 9和Ubuntu 24.04

set -e

echo "==================================="
echo "CIS合规性检查脚本"
echo "==================================="
echo ""

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        
        if [[ "$NAME" == "Ubuntu" && "$VERSION_ID" == "24.04" ]]; then
            echo "检测到系统: Ubuntu 24.04"
            OS_TYPE="ubuntu2404"
            return 0
        elif [[ "$NAME" == *"Red Hat"* && "$VERSION_ID" == "9"* ]]; then
            echo "检测到系统: RHEL 9"
            OS_TYPE="rhel9"
            return 0
        elif [[ "$NAME" == *"CentOS"* && "$VERSION_ID" == "9"* ]]; then
            echo "检测到系统: CentOS 9"
            OS_TYPE="rhel9"
            return 0
        elif [[ "$NAME" == *"AlmaLinux"* && "$VERSION_ID" == "9"* ]]; then
            echo "检测到系统: AlmaLinux 9"
            OS_TYPE="rhel9"
            return 0
        else
            echo "警告: 未完全支持的系统 - $NAME $VERSION_ID"
            echo "将尝试通用检查..."
            OS_TYPE="generic"
            return 0
        fi
    else
        echo "错误: 无法检测系统类型"
        return 1
    fi
}

# 安装OpenSCAP
install_openscap() {
    echo ""
    echo "安装OpenSCAP..."
    
    if command -v oscap &> /dev/null; then
        echo "OpenSCAP已安装"
        return 0
    fi
    
    case "$OS_TYPE" in
        "ubuntu2404")
            apt-get update
            apt-get install -y libopenscap25 openscap-scanner
            ;;
        "rhel9")
            dnf install -y openscap-scanner scap-security-guide
            ;;
        *)
            echo "错误: 无法自动安装OpenSCAP，请手动安装"
            exit 1
            ;;
    esac
    
    echo "OpenSCAP安装完成"
}

# 显示可用的检查配置文件
show_available_profiles() {
    echo ""
    echo "==================================="
    echo "可用的CIS检查配置文件"
    echo "==================================="
    
    case "$OS_TYPE" in
        "ubuntu2404")
            echo ""
            echo "Ubuntu 24.04 CIS配置文件:"
            echo "1) CIS Ubuntu 24.04 Level 1 Server"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level1_server"
            echo ""
            echo "2) CIS Ubuntu 24.04 Level 2 Server"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level2_server"
            echo ""
            echo "3) CIS Ubuntu 24.04 Level 1 Workstation"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level1_workstation"
            echo ""
            echo "4) CIS Ubuntu 24.04 Level 2 Workstation"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level2_workstation"
            ;;
        "rhel9")
            echo ""
            echo "RHEL 9 CIS配置文件:"
            echo "1) CIS RHEL 9 Level 1 Server"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level1_server"
            echo ""
            echo "2) CIS RHEL 9 Level 2 Server"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level2_server"
            echo ""
            echo "3) CIS RHEL 9 Level 1 Workstation"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level1_workstation"
            echo ""
            echo "4) CIS RHEL 9 Level 2 Workstation"
            echo "   配置文件: xccdf_org.ssgproject.content_profile_cis_level2_workstation"
            ;;
        *)
            echo "通用系统，请手动指定配置文件"
            ;;
    esac
    echo ""
}

# 获取SCAP内容路径
get_scap_content_path() {
    case "$OS_TYPE" in
        "ubuntu2404")
            if [ -f "/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml" ]; then
                echo "/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml"
            elif [ -f "/usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml" ]; then
                echo "/usr/share/xml/scap/ssg/content/ssg-ubuntu2204-ds.xml"
            else
                find /usr/share -name "ssg-ubuntu*.xml" 2>/dev/null | head -1
            fi
            ;;
        "rhel9")
            if [ -f "/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml" ]; then
                echo "/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml"
            else
                find /usr/share -name "ssg-rhel9*.xml" 2>/dev/null | head -1
            fi
            ;;
        *)
            find /usr/share -name "ssg-*.xml" 2>/dev/null | head -1
            ;;
    esac
}

# 执行CIS合规性检查
run_compliance_check() {
    echo ""
    echo "==================================="
    echo "执行CIS合规性检查"
    echo "==================================="
    
    # 获取SCAP内容路径
    SCAP_CONTENT=$(get_scap_content_path)
    
    if [ -z "$SCAP_CONTENT" ] || [ ! -f "$SCAP_CONTENT" ]; then
        echo "错误: 找不到SCAP内容文件"
        echo ""
        
        if [ "$OS_TYPE" == "ubuntu2404" ]; then
            echo "在Ubuntu 24.04上，scap-security-guide包可能不可用"
            echo "尝试自动下载SCAP内容文件..."
            
            # 确保目录存在
            mkdir -p /usr/share/xml/scap/ssg/content/
            
            # 下载并解压SCAP内容文件
            echo "下载SCAP内容文件..."
            if command -v wget &> /dev/null; then
                wget -O /tmp/scap-security-guide.zip https://github.com/ComplianceAsCode/content/releases/download/v0.1.68/scap-security-guide-0.1.68.zip
            elif command -v curl &> /dev/null; then
                curl -o /tmp/scap-security-guide.zip https://github.com/ComplianceAsCode/content/releases/download/v0.1.68/scap-security-guide-0.1.68.zip
            else
                echo "错误: 没有找到wget或curl，无法自动下载"
                echo "请手动下载SCAP内容文件："
                echo "  wget https://github.com/ComplianceAsCode/content/releases/download/v0.1.68/scap-security-guide-0.1.68.zip"
                echo "  unzip scap-security-guide-0.1.68.zip"
                echo "  cp scap-security-guide-0.1.68/content/ssg-ubuntu2404-ds.xml /usr/share/xml/scap/ssg/content/"
                exit 1
            fi
            
            # 解压文件
            echo "解压SCAP内容文件..."
            if command -v unzip &> /dev/null; then
                unzip -o /tmp/scap-security-guide.zip -d /tmp/
            else
                echo "错误: 没有找到unzip，无法自动解压"
                echo "请手动解压并复制文件"
                exit 1
            fi
            
            # 查找并复制文件
            echo "查找SCAP内容文件..."
            SCAP_FILE=$(find /tmp -name "ssg-ubuntu2404-ds.xml" 2>/dev/null | head -1)
            if [ -z "$SCAP_FILE" ]; then
                SCAP_FILE=$(find /tmp -name "ssg-ubuntu2204-ds.xml" 2>/dev/null | head -1)
            fi
            if [ -z "$SCAP_FILE" ]; then
                SCAP_FILE=$(find /tmp -name "ssg-ubuntu*.xml" 2>/dev/null | head -1)
            fi
            
            if [ -n "$SCAP_FILE" ]; then
                echo "找到SCAP内容文件: $SCAP_FILE"
                echo "复制到目标目录..."
                cp "$SCAP_FILE" /usr/share/xml/scap/ssg/content/
            else
                echo "错误: 无法找到适合的SCAP内容文件"
                echo "解压后的文件列表:"
                find /tmp -name "*.xml" 2>/dev/null | head -20
                exit 1
            fi
            
            # 重新获取SCAP内容路径
            SCAP_CONTENT=$(get_scap_content_path)
            if [ -z "$SCAP_CONTENT" ] || [ ! -f "$SCAP_CONTENT" ]; then
                echo "错误: 下载后仍然找不到SCAP内容文件"
                exit 1
            fi
            
            echo "SCAP内容文件下载成功！"
        else
            echo "请确保scap-security-guide包已正确安装"
            exit 1
        fi
    fi
    
    echo "SCAP内容文件: $SCAP_CONTENT"
    echo ""
    
    # 选择检查级别
    echo "请选择要检查的CIS级别:"
    echo "1) Level 1 Server (基础安全 - 服务器)"
    echo "2) Level 2 Server (高级安全 - 服务器)"
    echo "3) Level 1 Workstation (基础安全 - 工作站)"
    echo "4) Level 2 Workstation (高级安全 - 工作站)"
    echo ""
    read -p "请输入选项 (1-4): " CHECK_LEVEL
    
    case "$CHECK_LEVEL" in
        1)
            PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_server"
            ;;
        2)
            PROFILE="xccdf_org.ssgproject.content_profile_cis_level2_server"
            ;;
        3)
            PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_workstation"
            ;;
        4)
            PROFILE="xccdf_org.ssgproject.content_profile_cis_level2_workstation"
            ;;
        *)
            echo "错误: 无效选项"
            exit 1
            ;;
    esac
    
    echo ""
    echo "使用配置文件: $PROFILE"
    echo ""
    
    # 创建报告目录
    REPORT_DIR="/tmp/cis-compliance-report-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$REPORT_DIR"
    
    echo "报告将保存到: $REPORT_DIR"
    echo ""
    
    # 执行检查
    echo "开始执行合规性检查，这可能需要几分钟..."
    echo ""
    
    # 生成HTML报告
    oscap xccdf eval \
        --profile "$PROFILE" \
        --results "$REPORT_DIR/results.xml" \
        --report "$REPORT_DIR/report.html" \
        --oval-results \
        "$SCAP_CONTENT"
    
    CHECK_RESULT=$?
    
    echo ""
    echo "==================================="
    echo "检查完成"
    echo "==================================="
    echo ""
    echo "报告文件位置:"
    echo "  - XML结果: $REPORT_DIR/results.xml"
    echo "  - HTML报告: $REPORT_DIR/report.html"
    echo ""
    
    # 生成摘要
    generate_summary "$REPORT_DIR/results.xml"
    
    return $CHECK_RESULT
}

# 生成检查摘要
generate_summary() {
    local results_file="$1"
    
    if [ ! -f "$results_file" ]; then
        echo "警告: 找不到结果文件"
        return 1
    fi
    
    echo "==================================="
    echo "合规性检查摘要"
    echo "==================================="
    echo ""
    
    # 统计通过、失败、错误的规则数量
    pass_count=$(grep -c 'result="pass"' "$results_file" 2>/dev/null || echo "0")
    fail_count=$(grep -c 'result="fail"' "$results_file" 2>/dev/null || echo "0")
    error_count=$(grep -c 'result="error"' "$results_file" 2>/dev/null || echo "0")
    unknown_count=$(grep -c 'result="unknown"' "$results_file" 2>/dev/null || echo "0")
    notchecked_count=$(grep -c 'result="notchecked"' "$results_file" 2>/dev/null || echo "0")
    notapplicable_count=$(grep -c 'result="notapplicable"' "$results_file" 2>/dev/null || echo "0")
    
    echo "检查结果统计:"
    echo "  通过 (Pass):           $pass_count"
    echo "  失败 (Fail):           $fail_count"
    echo "  错误 (Error):          $error_count"
    echo "  未知 (Unknown):        $unknown_count"
    echo "  未检查 (Not Checked):  $notchecked_count"
    echo "  不适用 (Not Applicable): $notapplicable_count"
    echo ""
    
    # 计算合规率
    total_checked=$((pass_count + fail_count + error_count))
    if [ "$total_checked" -gt 0 ]; then
        compliance_rate=$((pass_count * 100 / total_checked))
        echo "合规率: $compliance_rate%"
        echo ""
        
        if [ "$compliance_rate" -ge 90 ]; then
            echo "✓ 系统合规性良好"
        elif [ "$compliance_rate" -ge 70 ]; then
            echo "⚠ 系统合规性一般，建议改进"
        else
            echo "✗ 系统合规性较差，需要加固"
        fi
    else
        echo "警告: 没有可检查的规则（所有规则都标记为'不适用'）"
        echo "这可能是因为："
        echo "  1. 选择了错误的服务器/工作站配置文件"
        echo "  2. 系统环境不符合CIS基准要求"
        echo "  3. SCAP内容文件版本与系统不匹配"
        echo ""
        echo "建议："
        echo "  - 检查是否选择了正确的配置文件（Server/Workstation）"
        echo "  - 查看详细报告了解具体原因: $REPORT_DIR/report.html"
    fi
    
    echo ""
    echo "详细报告请查看: $REPORT_DIR/report.html"
    echo ""
}

# 显示帮助信息
show_help() {
    cat << 'EOF'
CIS合规性检查脚本 - 使用帮助

用法: ./cis_compliance_check.sh [选项]

选项:
  -h, --help          显示此帮助信息
  -i, --install       仅安装OpenSCAP
  -l, --list          列出可用的检查配置文件
  -c, --check         执行合规性检查（默认）
  -p, --profile       指定配置文件（高级用法）

示例:
  # 执行完整的合规性检查
  sudo ./cis_compliance_check.sh

  # 仅安装OpenSCAP
  sudo ./cis_compliance_check.sh --install

  # 列出可用的配置文件
  sudo ./cis_compliance_check.sh --list

注意:
  - 此脚本需要root权限运行
  - 检查过程可能需要几分钟时间
  - 生成的报告保存在 /tmp/cis-compliance-report-*/ 目录

EOF
}

# 主函数
main() {
    # 检查是否以root运行
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 请使用root权限运行此脚本"
        echo "用法: sudo $0"
        exit 1
    fi
    
    # 解析命令行参数
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--install)
            detect_os || exit 1
            install_openscap
            echo ""
            echo "OpenSCAP安装完成"
            exit 0
            ;;
        -l|--list)
            detect_os || exit 1
            install_openscap
            show_available_profiles
            exit 0
            ;;
        -c|--check|"")
            # 默认执行检查
            ;;
        *)
            echo "错误: 未知选项 $1"
            echo "使用 -h 或 --help 查看帮助"
            exit 1
            ;;
    esac
    
    # 执行完整的检查流程
    detect_os || exit 1
    install_openscap
    show_available_profiles
    run_compliance_check
    
    exit $?
}

# 执行主函数
main "$@"
