#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# 基础日志函数
function LOGD() {
    echo -e "${yellow}[调试] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[错误] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[信息] $* ${plain}"
}

# 检查root权限
[[ $EUID -ne 0 ]] && LOGE "错误：必须使用root用户运行此脚本！\n" && exit 1

# 识别操作系统
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测操作系统，请联系作者！" >&2
    exit 1
fi
echo "检测到操作系统：$release"

# 检查GLIBC版本
check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC版本 $glibc_version 过低！需要2.32或更高版本${plain}"
        echo "请升级到更新的操作系统版本以获取更高GLIBC版本"
        exit 1
    fi
    echo "GLIBC版本：$glibc_version (符合2.32+要求)"
}
check_glibc_version

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

# 日志文件路径
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

# 确认函数
confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [默认$2]: " temp
        if [[ "${temp}" == "" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ "${temp}" == "y" || "${temp}" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

# 重启确认
confirm_restart() {
    confirm "是否重启面板？重启会同时重启xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

# 安装函数
install() {
    bash <(curl -Ls https://raw.githubusercontent.com/YSeverything/3x-ui-cn/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

# 更新函数
update() {
    confirm "将会强制重装最新版，数据不会丢失，是否继续？" "y"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/YSeverything/3x-ui-cn/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "更新完成，已自动重启面板 "
        before_show_menu
    fi
}

# 菜单更新
update_menu() {
    echo -e "${yellow}正在更新菜单${plain}"
    confirm "将会更新菜单到最新变更，是否继续？" "y"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi

    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/YSeverything/3x-ui-cn/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui

    if [[ $? == 0 ]]; then
        echo -e "${green}菜单更新成功，请重新运行脚本${plain}"
        before_show_menu
    else
        echo -e "${red}菜单更新失败${plain}"
        return 1
    fi
}

# 旧版安装
legacy_version() {
    echo "请输入要安装的面板版本（例如2.4.0）："
    read tag_version

    if [ -z "$tag_version" ]; then
        echo "版本号不能为空！"
        exit 1
    fi
    install_command="bash <(curl -Ls "https://raw.githubusercontent.com/YSeverything/3x-ui-cn/v$tag_version/install.sh") v$tag_version"
    echo "正在下载并安装版本 $tag_version..."
    eval $install_command
}

# 卸载函数
uninstall() {
    confirm "确定要卸载面板吗？xray也会被卸载！" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "卸载成功！\n"
    echo "如需重新安装，请使用以下命令："
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/YSeverything/3x-ui-cn/main/install.sh)${plain}"
    echo ""
    trap delete_script SIGTERM
    delete_script
}

# 重置账号信息
reset_user() {
    confirm "确定要重置面板用户名和密码吗？" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "请输入新的登录用户名（默认随机用户名）：" config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "请输入新的登录密码（默认随机密码）：" config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/x-ui/x-ui setting -remove_secret >/dev/null 2>&1
    echo -e "用户名已重置为：${green}${config_account}${plain}"
    echo -e "密码已重置为：${green}${config_password}${plain}"
    echo -e "${yellow}安全令牌已禁用${plain}"
    echo -e "${green}请使用新的用户名和密码访问面板，并妥善保管！${plain}"
    confirm_restart
}

# 生成随机字符串
gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

# 重置访问路径
reset_webbasepath() {
    echo -e "${yellow}正在重置访问路径${plain}"

    read -rp "确定要重置Web访问路径吗？(y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${yellow}操作已取消${plain}"
        return
    fi

    config_webBasePath=$(gen_random_string 10)
    /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1

    echo -e "访问路径已重置为：${green}${config_webBasePath}${plain}"
    echo -e "${green}请使用新路径访问面板${plain}"
    restart
}

# 重置面板配置
reset_config() {
    confirm "确定要重置所有面板设置吗？账号数据不会丢失" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "所有面板设置已恢复默认"
    restart
}

# 查看配置
check_config() {
    local info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? == 0 ]]; then
        LOGI "${info}"
        
        local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
        local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
        local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
        local server_ip=$(curl -s https://api.ipify.org)

        if [[ -n "$existing_cert" ]]; then
            local domain=$(basename "$(dirname "$existing_cert")")
            [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && \
            echo -e "${green}访问地址：https://${domain}:${existing_port}${existing_webBasePath}${plain}" || \
            echo -e "${green}访问地址：https://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
        else
            echo -e "${green}访问地址：http://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
        fi
    else
        LOGE "获取配置信息失败，请检查日志"
    fi
}

# 设置端口
set_port() {
    echo && read -p "请输入端口号[1-65535]：" port
    if [[ -z "${port}" ]]; then
        LOGD "操作已取消"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "端口已设置，请使用新端口 ${green}${port}${plain} 访问面板"
        confirm_restart
    fi
}

# 启动服务
start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "面板正在运行，无需重复启动"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui 启动成功"
        else
            LOGE "面板启动失败，请稍后查看日志"
        fi
    fi
    [[ $# == 0 ]] && before_show_menu
}

# 停止服务
stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "面板已停止，无需重复操作"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui 停止成功"
        else
            LOGE "面板停止失败，请稍后查看日志"
        fi
    fi
    [[ $# == 0 ]] && before_show_menu
}

# 重启服务
restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui 重启成功"
    else
        LOGE "面板重启失败，请稍后查看日志"
    fi
    [[ $# == 0 ]] && before_show_menu
}

# 查看状态
status() {
    systemctl status x-ui -l
    [[ $# == 0 ]] && before_show_menu
}

# 启用自启
enable() {
    systemctl enable x-ui
    [[ $? == 0 ]] && LOGI "开机自启设置成功" || LOGE "设置失败"
    [[ $# == 0 ]] && before_show_menu
}

# 禁用自启
disable() {
    systemctl disable x-ui
    [[ $? == 0 ]] && LOGI "开机自启已取消" || LOGE "取消失败"
    [[ $# == 0 ]] && before_show_menu
}

# 查看日志
show_log() {
    echo -e "${green}\t1.${plain} 调试日志"
    echo -e "${green}\t2.${plain} 清空所有日志"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" choice

    case "$choice" in
    0) show_menu ;;
    1) journalctl -u x-ui -e --no-pager -f -p debug ;;
    2) 
        sudo journalctl --rotate
        sudo journalctl --vacuum-time=1s
        echo "所有日志已清空"
        restart ;;
    *) 
        echo -e "${red}无效选项，请重新输入${plain}"
        show_log ;;
    esac
}

# 查看封禁日志
show_banlog() {
    local system_log="/var/log/fail2ban.log"

    echo -e "${green}正在检查封禁日志...${plain}"

    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${red}Fail2ban服务未运行！${plain}"
        return 1
    fi

    [[ -f "$system_log" ]] && \
    echo -e "${green}系统封禁记录：${plain}" && \
    grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10 || \
    echo -e "${yellow}未找到近期封禁记录${plain}"

    [[ -f "${iplimit_banned_log_path}" ]] && \
    echo -e "\n${green}3X-IPL封禁记录：${plain}" && \
    ([[ -s "${iplimit_banned_log_path}" ]] && \
    grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10 || \
    echo -e "${yellow}封禁日志为空${plain}") || \
    echo -e "${red}日志文件未找到：${iplimit_banned_log_path}${plain}"

    echo -e "\n${green}当前封禁状态：${plain}"
    fail2ban-client status 3x-ipl || echo -e "${yellow}无法获取状态${plain}"
}

# BBR管理菜单
bbr_menu() {
    echo -e "${green}\t1.${plain} 启用BBR"
    echo -e "${green}\t2.${plain} 禁用BBR"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" choice
    case "$choice" in
    0) show_menu ;;
    1) enable_bbr; bbr_menu ;;
    2) disable_bbr; bbr_menu ;;
    *) 
        echo -e "${red}无效选项，请重新输入${plain}"
        bbr_menu ;;
    esac
}

# 启用BBR
enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && \
       grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR已启用！${plain}"
        return
    fi

    case "${release}" in
    ubuntu|debian|armbian) apt update && apt install -yqq ca-certificates ;;
    centos|almalinux|rocky|ol) yum -y update && yum -y install ca-certificates ;;
    fedora|amzn|virtuozzo) dnf -y update && dnf -y install ca-certificates ;;
    arch|manjaro|parch) pacman -Sy --noconfirm ca-certificates ;;
    *) 
        echo -e "${red}不支持的操作系统${plain}"
        exit 1 ;;
    esac

    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p

    [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]] && \
    echo -e "${green}BBR启用成功${plain}" || \
    echo -e "${red}BBR启用失败${plain}"
}

# 禁用BBR
disable_bbr() {
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
    sysctl -p
    echo -e "${green}BBR已切换为CUBIC${plain}"
}

# 更新脚本
update_shell() {
    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    if [[ $? != 0 ]]; then
        LOGE "下载脚本失败，请检查网络连接"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "脚本更新成功，请重新运行"
        before_show_menu
    fi
}

# 检查服务状态
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    [[ "${temp}" == "running" ]] && return 0 || return 1
}

# 显示状态信息
show_status() {
    check_status
    case $? in
        0) echo -e "面板状态：${green}运行中${plain}" ;;
        1) echo -e "面板状态：${yellow}未运行${plain}" ;;
        2) echo -e "面板状态：${red}未安装${plain}" ;;
    esac
    show_enable_status
    show_xray_status
}

# 后续函数保持类似的结构进行汉化...

# 主菜单
show_menu() {
    echo -e "
╔────────────────────────────────────────────────╗
│   ${green}3X-UI 面板管理脚本${plain}                       │
│   ${green}0.${plain} 退出脚本                              │
│────────────────────────────────────────────────│
│   ${green}1.${plain} 安装面板                              │
│   ${green}2.${plain} 更新面板                              │
│   ${green}3.${plain} 更新菜单                              │
│   ${green}4.${plain} 安装旧版                              │
│   ${green}5.${plain} 卸载面板                              │
│────────────────────────────────────────────────│
│   ${green}6.${plain} 重置登录凭据                          │
│   ${green}7.${plain} 重置访问路径                          │
│   ${green}8.${plain} 恢复默认设置                          │
│   ${green}9.${plain} 修改面板端口                          │
│  ${green}10.${plain} 查看当前配置                          │
│────────────────────────────────────────────────│
│  ${green}11.${plain} 启动面板                              │
│  ${green}12.${plain} 停止面板                              │
│  ${green}13.${plain} 重启面板                              │
│  ${green}14.${plain} 查看服务状态                          │
│  ${green}15.${plain} 查看日志                              │
│────────────────────────────────────────────────│
│  ${green}16.${plain} 启用开机自启                          │
│  ${green}17.${plain} 禁用开机自启                          │
│────────────────────────────────────────────────│
│  ${green}18.${plain} SSL证书管理                           │
│  ${green}19.${plain} Cloudflare证书                        │
│  ${green}20.${plain} IP限制管理                            │
│  ${green}21.${plain} 防火墙管理                            │
│  ${green}22.${plain} SSH端口转发                           │
│────────────────────────────────────────────────│
│  ${green}23.${plain} 启用BBR加速                           │
│  ${green}24.${plain} 更新地理数据                          │
│  ${green}25.${plain} 网络速度测试                          │
╚────────────────────────────────────────────────╝
"
    show_status
    echo && read -p "请输入选择 [0-25]： " num

    case "${num}" in
        0) exit 0 ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && update_menu ;;
        4) check_install && legacy_version ;;
        5) check_install && uninstall ;;
        6) check_install && reset_user ;;
        7) check_install && reset_webbasepath ;;
        8) check_install && reset_config ;;
        9) check_install && set_port ;;
        10) check_install && check_config ;;
        11) check_install && start ;;
        12) check_install && stop ;;
        13) check_install && restart ;;
        14) check_install && status ;;
        15) check_install && show_log ;;
        16) check_install && enable ;;
        17) check_install && disable ;;
        18) ssl_cert_issue_main ;;
        19) ssl_cert_issue_CF ;;
        20) iplimit_main ;;
        21) firewall_menu ;;
        22) SSH_port_forwarding ;;
        23) bbr_menu ;;
        24) update_geo ;;
        25) run_speedtest ;;
        *) LOGE "请输入正确数字 [0-25]" ;;
    esac
}

# 脚本使用说明
show_usage() {
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui 脚本使用说明：${plain}                          │
│                                                       │
│  ${blue}x-ui${plain}              - 显示管理菜单              │
│  ${blue}x-ui start${plain}        - 启动服务                  │
│  ${blue}x-ui stop${plain}         - 停止服务                  │
│  ${blue}x-ui restart${plain}      - 重启服务                  │
│  ${blue}x-ui status${plain}       - 查看状态                  │
│  ${blue}x-ui settings${plain}     - 查看配置                  │
│  ${blue}x-ui enable${plain}       - 设置开机启动              │
│  ${blue}x-ui disable${plain}      - 取消开机启动              │
│  ${blue}x-ui log${plain}          - 查看日志                  │
│  ${blue}x-ui banlog${plain}       - 查看封禁记录              │
│  ${blue}x-ui update${plain}       - 更新面板                  │
│  ${blue}x-ui legacy${plain}       - 安装旧版                  │
│  ${blue}x-ui install${plain}      - 全新安装                  │
│  ${blue}x-ui uninstall${plain}    - 完全卸载                  │
└───────────────────────────────────────────────────────┘"
}

# 根据参数执行对应操作
if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "settings") check_install 0 && check_config 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "banlog") check_install 0 && show_banlog 0 ;;
        "update") check_install 0 && update 0 ;;
        "legacy") check_install 0 && legacy_version 0 ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        *) show_usage ;;
    esac
else
    show_menu
fi
