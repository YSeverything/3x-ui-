#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# 基础功能函数
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
[[ $EUID -ne 0 ]] && LOGE "错误：必须使用root权限运行此脚本！\n" && exit 1

# 检测操作系统
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测系统类型，请联系作者！" >&2
    exit 1
fi
echo "操作系统：$release"

check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC版本 $glibc_version 过低！需要 2.32 或更高版本${plain}"
        echo "请升级到更新的操作系统版本以获取更高GLIBC版本"
        exit 1
    fi
    echo "GLIBC版本：$glibc_version (符合2.32+要求)"
}
check_glibc_version

os_version=""
os_version=$(grep "^VERSION_ID" /etc/os-release | cut -d '=' -f2 | tr -d '"' | tr -d '.')

# 全局变量声明
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

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

confirm_restart() {
    confirm "是否重启面板？注意：重启面板也会重启xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单：${plain}" && read temp
    show_menu
}

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

update() {
    confirm "本操作会强制安装最新版本，数据不会丢失，是否继续？" "y"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/YSeverything/3x-ui-cn/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "更新完成，面板已自动重启"
        before_show_menu
    fi
}

update_menu() {
    echo -e "${yellow}更新管理菜单${plain}"
    confirm "本操作会更新菜单到最新修改，是否继续？" "y"
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

legacy_version() {
    echo "请输入面板版本（例如 2.4.0）："
    read tag_version

    if [ -z "$tag_version" ]; then
        echo "面板版本不能为空，退出"
        exit 1
    fi
    install_command="bash <(curl -Ls \"https://raw.githubusercontent.com/YSeverything/3x-ui-cn/v$tag_version/install.sh\") v$tag_version"

    echo "正在下载并安装版本 $tag_version..."
    eval $install_command
}

# 删除脚本自身
delete_script() {
    rm "$0"
    exit 1
}

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
    echo -e "卸载成功\n"
    echo "如需重新安装，可以使用以下命令："
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/YSeverything/3x-ui-cn/master/install.sh)${plain}"
    echo ""
    trap delete_script SIGTERM
    delete_script
}

reset_user() {
    confirm "确定要重置面板的用户名和密码吗？" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "请输入登录用户名（默认随机生成）：" config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "请输入登录密码（默认随机生成）：" config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/x-ui/x-ui setting -remove_secret >/dev/null 2>&1
    echo -e "面板登录用户名已重置为：${green}${config_account}${plain}"
    echo -e "面板登录密码已重置为：${green}${config_password}${plain}"
    echo -e "${yellow}面板安全令牌已禁用${plain}"
    echo -e "${green}请使用新的用户名和密码访问X-UI面板，并妥善保存！${plain}"
    confirm_restart
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

reset_webbasepath() {
    echo -e "${yellow}重置Web基础路径${plain}"

    read -rp "确定要重置Web基础路径吗？(y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${yellow}操作已取消${plain}"
        return
    fi

    config_webBasePath=$(gen_random_string 10)

    /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1

    echo -e "Web基础路径已重置为：${green}${config_webBasePath}${plain}"
    echo -e "${green}请使用新的路径访问面板${plain}"
    restart
}

reset_config() {
    confirm "确定要重置所有面板设置吗？账户数据不会丢失，用户名密码不会改变" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "所有面板设置已恢复为默认值"
    restart
}

check_config() {
    local info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "获取当前设置失败，请检查日志"
        show_menu
        return
    fi
    LOGI "${info}"

    local existing_webBasePath=$(echo "$info" | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(echo "$info" | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local server_ip=$(curl -s https://api.ipify.org)

    if [[ -n "$existing_cert" ]]; then
        local domain=$(basename "$(dirname "$existing_cert")")

        if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo -e "${green}访问地址：https://${domain}:${existing_port}${existing_webBasePath}${plain}"
        else
            echo -e "${green}访问地址：https://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
        fi
    else
        echo -e "${green}访问地址：http://${server_ip}:${existing_port}${existing_webBasePath}${plain}"
    fi
}

set_port() {
    echo && echo -n -e "请输入端口号[1-65535]：" && read port
    if [[ -z "${port}" ]]; then
        LOGD "已取消"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "端口已设置，请立即重启面板，并使用新端口 ${green}${port}${plain} 访问"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "面板正在运行，无需重复启动，如需重启请选择重启选项"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "x-ui 启动成功"
        else
            LOGE "面板启动失败，可能启动时间超过2秒，请稍后查看日志"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "面板已停止，无需重复停止"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "x-ui 与 xray 停止成功"
        else
            LOGE "面板停止失败，可能停止时间超过2秒，请稍后查看日志"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "x-ui 与 xray 重启成功"
    else
        LOGE "面板重启失败，可能启动时间超过2秒，请稍后查看日志"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui 已设置开机自启"
    else
        LOGE "x-ui 开机自启设置失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui 已取消开机自启"
    else
        LOGE "x-ui 取消开机自启失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    echo -e "${green}\t1.${plain} 调试日志"
    echo -e "${green}\t2.${plain} 清除所有日志"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" choice

    case "$choice" in
    0)
        show_menu
        ;;
    1)
        journalctl -u x-ui -e --no-pager -f -p debug
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        ;;
    2)
        sudo journalctl --rotate
        sudo journalctl --vacuum-time=1s
        echo "所有日志已清除"
        restart
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        show_log
        ;;
    esac
}

show_banlog() {
    local system_log="/var/log/fail2ban.log"

    echo -e "${green}正在检查封禁日志...${plain}\n"

    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${red}Fail2ban服务未运行！${plain}\n"
        return 1
    fi

    if [[ -f "$system_log" ]]; then
        echo -e "${green}最近系统封禁记录（fail2ban.log）：${plain}"
        grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10 || echo -e "${yellow}无近期封禁记录${plain}"
        echo ""
    fi

    if [[ -f "${iplimit_banned_log_path}" ]]; then
        echo -e "${green}3X-IPL封禁记录：${plain}"
        if [[ -s "${iplimit_banned_log_path}" ]]; then
            grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10 || echo -e "${yellow}无封禁记录${plain}"
        else
            echo -e "${yellow}封禁日志为空${plain}"
        fi
    else
        echo -e "${red}未找到封禁日志文件：${iplimit_banned_log_path}${plain}"
    fi

    echo -e "\n${green}当前封禁状态：${plain}"
    fail2ban-client status 3x-ipl || echo -e "${yellow}无法获取封禁状态${plain}"
}

bbr_menu() {
    echo -e "${green}\t1.${plain} 启用BBR"
    echo -e "${green}\t2.${plain} 禁用BBR"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        bbr_menu
        ;;
    2)
        disable_bbr
        bbr_menu
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        bbr_menu
        ;;
    esac
}

disable_bbr() {

    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR当前未启用${plain}"
        before_show_menu
    fi

    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf

    sysctl -p

    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}BBR已成功替换为CUBIC${plain}"
    else
        echo -e "${red}替换BBR失败，请检查系统配置${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR已启用！${plain}"
        before_show_menu
    fi

    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
        ;;
    centos | almalinux | rocky | ol)
        yum -y update && yum -y install ca-certificates
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf -y install ca-certificates
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm ca-certificates
        ;;
    *)
        echo -e "${red}不支持的操作系统，请手动安装必要组件${plain}\n"
        exit 1
        ;;
    esac

    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    sysctl -p

    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR已成功启用${plain}"
    else
        echo -e "${red}启用BBR失败，请检查系统配置${plain}"
    fi
}

update_shell() {
    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/YSeverything/3x-ui-cn/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "下载脚本失败，请检查网络连接"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "脚本升级成功，请重新运行"
        before_show_menu
    fi
}

check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ "${temp}" == "running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ "${temp}" == "enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "面板已安装，请勿重复安装"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "请先安装面板"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "面板状态：${green}运行中${plain}"
        show_enable_status
        ;;
    1)
        echo -e "面板状态：${yellow}未运行${plain}"
        show_enable_status
        ;;
    2)
        echo -e "面板状态：${red}未安装${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "开机自启：${green}已启用${plain}"
    else
        echo -e "开机自启：${red}未启用${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "xray状态：${green}运行中${plain}"
    else
        echo -e "xray状态：${red}未运行${plain}"
    fi
}

firewall_menu() {
    echo -e "${green}\t1.${plain} 安装防火墙"
    echo -e "${green}\t2.${plain} 端口列表[编号]"
    echo -e "${green}\t3.${plain} 开放端口"
    echo -e "${green}\t4.${plain} 删除端口"
    echo -e "${green}\t5.${plain} 启用防火墙"
    echo -e "${green}\t6.${plain} 禁用防火墙"
    echo -e "${green}\t7.${plain} 防火墙状态"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        install_firewall
        firewall_menu
        ;;
    2)
        ufw status numbered
        firewall_menu
        ;;
    3)
        open_ports
        firewall_menu
        ;;
    4)
        delete_ports
        firewall_menu
        ;;
    5)
        ufw enable
        firewall_menu
        ;;
    6)
        ufw disable
        firewall_menu
        ;;
    7)
        ufw status verbose
        firewall_menu
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        firewall_menu
        ;;
    esac
}

install_firewall() {
    if ! command -v ufw &>/dev/null; then
        echo "检测到未安装ufw防火墙，正在安装..."
        apt-get update
        apt-get install -y ufw
    else
        echo "ufw防火墙已安装"
    fi

    if ufw status | grep -q "Status: active"; then
        echo "防火墙已激活"
    else
        echo "正在激活防火墙..."
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 2053/tcp
        ufw allow 2096/tcp

        ufw --force enable
    fi
}

open_ports() {
    read -p "请输入要开放的端口（如80,443,2053或范围400-500）：" ports

    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "错误：无效的输入格式，请使用逗号分隔的端口或端口范围" >&2
        exit 1
    fi

    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            ufw allow $start_port:$end_port/tcp
            ufw allow $start_port:$end_port/udp
        else
            ufw allow "$port"
        fi
    done

    echo "已开放以下端口："
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            (ufw status | grep -q "$start_port:$end_port") && echo "$start_port-$end_port"
        else
            (ufw status | grep -q "$port") && echo "$port"
        fi
    done
}

delete_ports() {
    echo "当前防火墙规则："
    ufw status numbered

    echo "请选择删除方式："
    echo "1) 按规则编号删除"
    echo "2) 按端口删除"
    read -p "请输入选项（1或2）：" choice

    if [[ $choice -eq 1 ]]; then
        read -p "请输入要删除的规则编号（如1,2等）：" rule_numbers

        if ! [[ $rule_numbers =~ ^([0-9]+)(,[0-9]+)*$ ]]; then
            echo "错误：请输入逗号分隔的规则编号" >&2
            exit 1
        fi

        IFS=',' read -ra RULE_NUMBERS <<<"$rule_numbers"
        for rule_number in "${RULE_NUMBERS[@]}"; do
            ufw delete "$rule_number" || echo "删除规则 $rule_number 失败"
        done

        echo "已删除选定的规则"

    elif [[ $choice -eq 2 ]]; then
        read -p "请输入要删除的端口（如80,443,2053或范围400-500）：" ports

        if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
            echo "错误：无效的输入格式" >&2
            exit 1
        fi

        IFS=',' read -ra PORT_LIST <<<"$ports"
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                ufw delete allow $start_port:$end_port/tcp
                ufw delete allow $start_port:$end_port/udp
            else
                ufw delete allow "$port"
            fi
        done

        echo "已删除以下端口："
        for port in "${PORT_LIST[@]}"; do
            if [[ $port == *-* ]]; then
                start_port=$(echo $port | cut -d'-' -f1)
                end_port=$(echo $port | cut -d'-' -f2)
                (ufw status | grep -q "$start_port:$end_port") || echo "$start_port-$end_port"
            else
                (ufw status | grep -q "$port") || echo "$port"
            fi
        done
    else
        echo "${red}错误：无效选项${plain}" >&2
        exit 1
    fi
}

update_geo() {
    echo -e "${green}\t1.${plain} Loyalsoldier (geoip.dat, geosite.dat)"
    echo -e "${green}\t2.${plain} chocolate4u (geoip_IR.dat, geosite_IR.dat)"
    echo -e "${green}\t3.${plain} runetfreedom (geoip_RU.dat, geosite_RU.dat)"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" choice

    cd /usr/local/x-ui/bin

    case "$choice" in
    0)
        show_menu
        ;;
    1)
        systemctl stop x-ui
        rm -f geoip.dat geosite.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${green}Loyalsoldier数据集更新成功！${plain}"
        restart
        ;;
    2)
        systemctl stop x-ui
        rm -f geoip_IR.dat geosite_IR.dat
        wget -O geoip_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
        wget -O geosite_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
        echo -e "${green}chocolate4u数据集更新成功！${plain}"
        restart
        ;;
    3)
        systemctl stop x-ui
        rm -f geoip_RU.dat geosite_RU.dat
        wget -O geoip_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geoip.dat
        wget -O geosite_RU.dat -N https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/geosite.dat
        echo -e "${green}runetfreedom数据集更新成功！${plain}"
        restart
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        update_geo
        ;;
    esac

    before_show_menu
}

install_acme() {
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then
        LOGI "acme.sh 已安装"
        return 0
    fi

    LOGI "正在安装acme.sh..."
    cd ~ || return 1

    curl -s https://get.acme.sh | sh
    if [ $? -ne 0 ]; then
        LOGE "acme.sh安装失败"
        return 1
    else
        LOGI "acme.sh安装成功"
    fi

    return 0
}

ssl_cert_issue_main() {
    echo -e "${green}\t1.${plain} 获取SSL证书"
    echo -e "${green}\t2.${plain} 吊销证书"
    echo -e "${green}\t3.${plain} 强制续签"
    echo -e "${green}\t4.${plain} 查看已有域名"
    echo -e "${green}\t5.${plain} 设置面板证书路径"
    echo -e "${green}\t0.${plain} 返回主菜单"

    read -p "请选择操作：" choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        ssl_cert_issue
        ssl_cert_issue_main
        ;;
    2)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "没有找到可吊销的证书"
        else
            echo "已有域名："
            echo "$domains"
            read -p "请输入要吊销的域名：" domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --revoke -d ${domain}
                LOGI "证书吊销成功：$domain"
            else
                echo "无效的域名"
            fi
        fi
        ssl_cert_issue_main
        ;;
    3)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "没有找到可续签的证书"
        else
            echo "已有域名："
            echo "$domains"
            read -p "请输入要续签的域名：" domain
            if echo "$domains" | grep -qw "$domain"; then
                ~/.acme.sh/acme.sh --renew -d ${domain} --force
                LOGI "证书强制续签成功：$domain"
            else
                echo "无效的域名"
            fi
        fi
        ssl_cert_issue_main
        ;;
    4)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "没有找到证书"
        else
            echo "已有域名及其路径："
            for domain in $domains; do
                local cert_path="/root/cert/${domain}/fullchain.pem"
                local key_path="/root/cert/${domain}/privkey.pem"
                if [[ -f "${cert_path}" && -f "${key_path}" ]]; then
                    echo -e "域名：${domain}"
                    echo -e "\t证书路径：${cert_path}"
                    echo -e "\t私钥路径：${key_path}"
                else
                    echo -e "域名：${domain} - 证书或密钥缺失"
                fi
            done
        fi
        ssl_cert_issue_main
        ;;
    5)
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
        if [ -z "$domains" ]; then
            echo "没有找到证书"
        else
            echo "可用域名："
            echo "$domains"
            read -p "请选择要设置的域名：" domain

            if echo "$domains" | grep -qw "$domain"; then
                local webCertFile="/root/cert/${domain}/fullchain.pem"
                local webKeyFile="/root/cert/${domain}/privkey.pem"

                if [[ -f "${webCertFile}" && -f "${webKeyFile}" ]]; then
                    /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                    echo "面板证书路径设置成功：$domain"
                    echo "  - 证书文件：$webCertFile"
                    echo "  - 私钥文件：$webKeyFile"
                    restart
                else
                    echo "未找到证书或私钥文件：$domain"
                fi
            else
                echo "无效的域名"
            fi
        fi
        ssl_cert_issue_main
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        ssl_cert_issue_main
        ;;
    esac
}

ssl_cert_issue() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "未找到acme.sh，正在安装"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "安装acme失败，请检查日志"
            exit 1
        fi
    fi

    case "${release}" in
    ubuntu | debian | armbian)
        apt update && apt install socat -y
        ;;
    centos | almalinux | rocky | ol)
        yum -y update && yum -y install socat
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf -y install socat
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm socat
        ;;
    *)
        echo -e "${red}不支持的操作系统，请手动安装必要组件${plain}\n"
        exit 1
        ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "安装socat失败"
        exit 1
    else
        LOGI "socat安装成功"
    fi

    local domain=""
    read -p "请输入您的域名：" domain
    LOGD "正在验证域名：${domain}"

    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "该域名已有证书，无法重复申请。当前证书详情："
        LOGI "$certInfo"
        exit 1
    else
        LOGI "域名验证通过，开始签发证书..."
    fi

    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    local WebPort=80
    read -p "请输入验证端口（默认80）：" WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "端口输入错误，将使用默认端口80"
        WebPort=80
    fi
    LOGI "将使用端口：${WebPort} 进行验证，请确保该端口已开放"

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force
    if [ $? -ne 0 ]; then
        LOGE "证书签发失败"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "证书签发成功，正在安装..."
    fi

    reloadCmd="x-ui restart"

    LOGI "默认--reloadcmd为：${yellow}x-ui restart"
    LOGI "此命令将在每次证书签发/续期时执行"
    read -p "是否修改--reloadcmd？(y/n)：" setReloadcmd
    if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
        echo -e "\n${green}\t1.${plain} 预设：systemctl reload nginx ; x-ui restart"
        echo -e "${green}\t2.${plain} 自定义命令"
        echo -e "${green}\t0.${plain} 保持默认"
        read -p "请选择：" choice
        case "$choice" in
        1)
            LOGI "Reloadcmd设置为：systemctl reload nginx ; x-ui restart"
            reloadCmd="systemctl reload nginx ; x-ui restart"
            ;;
        2)  
            LOGD "建议在命令末尾包含x-ui restart，以避免其他服务失败导致错误"
            read -p "请输入自定义命令（例如：systemctl reload nginx ; x-ui restart）：" reloadCmd
            LOGI "自定义命令已设置为：${reloadCmd}"
            ;;
        *)
            LOGI "保持默认设置"
            ;;
        esac
    fi
    
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}"

    if [ $? -ne 0 ]; then
        LOGE "证书安装失败"
        exit 1
    else
        LOGI "证书安装成功，已启用自动续期"
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "自动续期设置失败"
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "证书安装及自动续期设置成功，详细信息："
        ls -lah cert/*
        chmod 755 $certPath/*
    fi

    read -p "是否将此证书设置为面板证书？(y/n)：" setPanel
    if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
        local webCertFile="/root/cert/${domain}/fullchain.pem"
        local webKeyFile="/root/cert/${domain}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            LOGI "面板证书设置成功：$domain"
            LOGI "  - 证书文件：$webCertFile"
            LOGI "  - 私钥文件：$webKeyFile"
            echo -e "${green}访问地址：https://${domain}:${existing_port}${existing_webBasePath}${plain}"
            restart
        else
            LOGE "未找到证书或私钥文件：$domain"
        fi
    else
        LOGI "跳过面板证书设置"
    fi
}

ssl_cert_issue_CF() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    LOGI "****** 使用说明 ******"
    LOGI "请准备好以下信息："
    LOGI "1. Cloudflare注册邮箱"
    LOGI "2. Cloudflare Global API Key"
    LOGI "3. 域名"
    LOGI "4. 证书签发后可选设置面板证书"
    LOGI "5. 本脚本支持证书自动续期"

    confirm "是否确认继续？[y/n]" "y"

    if [ $? -eq 0 ]; then
        if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
            echo "未找到acme.sh，正在安装"
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "安装acme失败"
                exit 1
            fi
        fi

        CF_Domain=""

        LOGD "请输入域名："
        read -p "请输入域名：" CF_Domain
        LOGD "域名设置为：${CF_Domain}"

        CF_GlobalKey=""
        CF_AccountEmail=""
        LOGD "请输入API密钥："
        read -p "请输入API密钥：" CF_GlobalKey
        LOGD "API密钥：${CF_GlobalKey}"

        LOGD "请输入注册邮箱："
        read -p "请输入邮箱：" CF_AccountEmail
        LOGD "注册邮箱：${CF_AccountEmail}"

        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "设置CA失败，退出..."
            exit 1
        fi

        export CF_Key="${CF_GlobalKey}"
        export CF_Email="${CF_AccountEmail}"

        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log --force
        if [ $? -ne 0 ]; then
            LOGE "证书签发失败"
            exit 1
        else
            LOGI "证书签发成功，正在安装..."
        fi

        certPath="/root/cert/${CF_Domain}"
        if [ -d "$certPath" ]; then
            rm -rf ${certPath}
        fi

        mkdir -p ${certPath}
        if [ $? -ne 0 ]; then
            LOGE "创建目录失败：${certPath}"
            exit 1
        fi

        reloadCmd="x-ui restart"

        LOGI "默认--reloadcmd为：${yellow}x-ui restart"
        LOGI "此命令将在每次证书签发/续期时执行"
        read -p "是否修改--reloadcmd？(y/n)：" setReloadcmd
        if [[ "$setReloadcmd" == "y" || "$setReloadcmd" == "Y" ]]; then
            echo -e "\n${green}\t1.${plain} 预设：systemctl reload nginx ; x-ui restart"
            echo -e "${green}\t2.${plain} 自定义命令"
            echo -e "${green}\t0.${plain} 保持默认"
            read -p "请选择：" choice
            case "$choice" in
            1)
                LOGI "Reloadcmd设置为：systemctl reload nginx ; x-ui restart"
                reloadCmd="systemctl reload nginx ; x-ui restart"
                ;;
            2)  
                LOGD "建议在命令末尾包含x-ui restart"
                read -p "请输入自定义命令：" reloadCmd
                LOGI "自定义命令已设置为：${reloadCmd}"
                ;;
            *)
                LOGI "保持默认设置"
                ;;
            esac
        fi
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
            --key-file ${certPath}/privkey.pem \
            --fullchain-file ${certPath}/fullchain.pem --reloadcmd "${reloadCmd}"
        
        if [ $? -ne 0 ]; then
            LOGE "证书安装失败"
            exit 1
        else
            LOGI "证书安装成功，已启用自动续期"
        fi

        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "自动续期设置失败"
            exit 1
        else
            LOGI "证书详细信息："
            ls -lah ${certPath}/*
            chmod 755 ${certPath}/*
        fi

        read -p "是否将此证书设置为面板证书？(y/n)：" setPanel
        if [[ "$setPanel" == "y" || "$setPanel" == "Y" ]]; then
            local webCertFile="${certPath}/fullchain.pem"
            local webKeyFile="${certPath}/privkey.pem"

            if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
                /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                LOGI "面板证书设置成功：$CF_Domain"
                LOGI "  - 证书文件：$webCertFile"
                LOGI "  - 私钥文件：$webKeyFile"
                echo -e "${green}访问地址：https://${CF_Domain}:${existing_port}${existing_webBasePath}${plain}"
                restart
            else
                LOGE "未找到证书或私钥文件：$CF_Domain"
            fi
        else
            LOGI "跳过面板证书设置"
        fi
    else
        show_menu
    fi
}

run_speedtest() {
    if ! command -v speedtest &>/dev/null; then
        if command -v snap &>/dev/null; then
            echo "正在使用snap安装Speedtest..."
            snap install speedtest
        else
            local pkg_manager=""
            local speedtest_install_script=""

            if command -v dnf &>/dev/null; then
                pkg_manager="dnf"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v yum &>/dev/null; then
                pkg_manager="yum"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
            elif command -v apt-get &>/dev/null; then
                pkg_manager="apt-get"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            elif command -v apt &>/dev/null; then
                pkg_manager="apt"
                speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
            fi

            if [[ -z $pkg_manager ]]; then
                echo "错误：未找到包管理器，请手动安装Speedtest"
                return 1
            else
                echo "正在使用$pkg_manager安装Speedtest..."
                curl -s $speedtest_install_script | bash
                $pkg_manager install -y speedtest
            fi
        fi
    fi

    speedtest
}

create_iplimit_jails() {
    local bantime="${1:-30}"

    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf

    if [[  "${release}" == "debian" && ${os_version} -ge 12 ]]; then
        sed -i '0,/action =/s/backend = auto/backend = systemd/' /etc/fail2ban/jail.conf
    fi

    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled=true
backend=auto
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=${bantime}m
EOF

    cat << EOF > /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF

    cat << EOF > /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> ${iplimit_banned_log_path}

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> ${iplimit_banned_log_path}

[Init]
name = default
protocol = tcp
chain = INPUT
EOF

    echo -e "${green}IP限制规则已创建，封禁时间：${bantime}分钟${plain}"
}

iplimit_remove_conflicts() {
    local jail_files=(
        /etc/fail2ban/jail.conf
        /etc/fail2ban/jail.local
    )

    for file in "${jail_files[@]}"; do
        if test -f "${file}" && grep -qw '3x-ipl' ${file}; then
            sed -i "/\[3x-ipl\]/,/^$/d" ${file}
            echo -e "${yellow}移除冲突配置：${file}${plain}\n"
        fi
    done
}

ip_validation() {
    ipv6_regex="^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$"
    ipv4_regex="^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]?|0)$"
}

iplimit_main() {
    echo -e "\n${green}\t1.${plain} 安装Fail2ban并配置IP限制"
    echo -e "${green}\t2.${plain} 修改封禁时长"
    echo -e "${green}\t3.${plain} 解封所有IP"
    echo -e "${green}\t4.${plain} 查看封禁日志"
    echo -e "${green}\t5.${plain} 封禁指定IP"
    echo -e "${green}\t6.${plain} 解封指定IP"
    echo -e "${green}\t7.${plain} 实时日志监控"
    echo -e "${green}\t8.${plain} 服务状态"
    echo -e "${green}\t9.${plain} 重启服务"
    echo -e "${green}\t10.${plain} 卸载Fail2ban及IP限制"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        confirm "确定要安装Fail2ban及IP限制吗？" "y"
        if [[ $? == 0 ]]; then
            install_iplimit
        else
            iplimit_main
        fi
        ;;
    2)
        read -rp "请输入新的封禁时长（分钟，默认30）：" NUM
        if [[ $NUM =~ ^[0-9]+$ ]]; then
            create_iplimit_jails ${NUM}
            systemctl restart fail2ban
        else
            echo -e "${red}${NUM} 不是有效数字！请重新输入${plain}"
        fi
        iplimit_main
        ;;
    3)
        confirm "确定要解封所有IP吗？" "y"
        if [[ $? == 0 ]]; then
            fail2ban-client reload --restart --unban 3x-ipl
            truncate -s 0 "${iplimit_banned_log_path}"
            echo -e "${green}所有用户已解封${plain}"
            iplimit_main
        else
            echo -e "${yellow}操作已取消${plain}"
        fi
        iplimit_main
        ;;
    4)
        show_banlog
        iplimit_main
        ;;
    5)
        read -rp "请输入要封禁的IP地址：" ban_ip
        ip_validation
        if [[ $ban_ip =~ $ipv4_regex || $ban_ip =~ $ipv6_regex ]]; then
            fail2ban-client set 3x-ipl banip "$ban_ip"
            echo -e "${green}IP地址 ${ban_ip} 封禁成功${plain}"
        else
            echo -e "${red}无效的IP格式！请重新输入${plain}"
        fi
        iplimit_main
        ;;
    6)
        read -rp "请输入要解封的IP地址：" unban_ip
        ip_validation
        if [[ $unban_ip =~ $ipv4_regex || $unban_ip =~ $ipv6_regex ]]; then
            fail2ban-client set 3x-ipl unbanip "$unban_ip"
            echo -e "${green}IP地址 ${unban_ip} 解封成功${plain}"
        else
            echo -e "${red}无效的IP格式！请重新输入${plain}"
        fi
        iplimit_main
        ;;
    7)
        tail -f /var/log/fail2ban.log
        iplimit_main
        ;;
    8)
        service fail2ban status
        iplimit_main
        ;;
    9)
        systemctl restart fail2ban
        iplimit_main
        ;;
    10)
        remove_iplimit
        iplimit_main
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        iplimit_main
        ;;
    esac
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo -e "${green}Fail2ban未安装，正在安装...${plain}\n"

        case "${release}" in
        ubuntu)
            if [[ "${os_version}" -ge 24 ]]; then
                apt update && apt install python3-pip -y
                python3 -m pip install pyasynchat --break-system-packages
            fi
            apt update && apt install fail2ban -y
            ;;
        debian | armbian)
            apt update && apt install fail2ban -y
            ;;
        centos | almalinux | rocky | ol)
            yum update -y && yum install epel-release -y
            yum -y install fail2ban
            ;;
        fedora | amzn | virtuozzo)
            dnf -y update && dnf -y install fail2ban
            ;;
        arch | manjaro | parch)
            pacman -Syu --noconfirm fail2ban
            ;;
        *)
            echo -e "${red}不支持的操作系统，请手动安装${plain}\n"
            exit 1
            ;;
        esac

        if ! command -v fail2ban-client &>/dev/null; then
            echo -e "${red}Fail2ban安装失败${plain}\n"
            exit 1
        fi

        echo -e "${green}Fail2ban安装成功！${plain}\n"
    else
        echo -e "${yellow}Fail2ban已安装${plain}\n"
    fi

    echo -e "${green}正在配置IP限制...${plain}\n"

    iplimit_remove_conflicts

    if ! test -f "${iplimit_banned_log_path}"; then
        touch ${iplimit_banned_log_path}
    fi

    if ! test -f "${iplimit_log_path}"; then
        touch ${iplimit_log_path}
    fi

    create_iplimit_jails

    if ! systemctl is-active --quiet fail2ban; then
        systemctl start fail2ban
    else
        systemctl restart fail2ban
    fi
    systemctl enable fail2ban

    echo -e "${green}IP限制配置成功！${plain}\n"
    before_show_menu
}

remove_iplimit() {
    echo -e "${green}\t1.${plain} 仅移除IP限制配置"
    echo -e "${green}\t2.${plain} 完全卸载Fail2ban"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请选择操作：" num
    case "$num" in
    1)
        rm -f /etc/fail2ban/filter.d/3x-ipl.conf
        rm -f /etc/fail2ban/action.d/3x-ipl.conf
        rm -f /etc/fail2ban/jail.d/3x-ipl.conf
        systemctl restart fail2ban
        echo -e "${green}IP限制配置已移除！${plain}\n"
        before_show_menu
        ;;
    2)
        rm -rf /etc/fail2ban
        systemctl stop fail2ban
        case "${release}" in
        ubuntu | debian | armbian)
            apt-get remove -y fail2ban
            apt-get purge -y fail2ban -y
            apt-get autoremove -y
            ;;
        centos | almalinux | rocky | ol)
            yum remove fail2ban -y
            yum autoremove -y
            ;;
        fedora | amzn | virtuozzo)
            dnf remove fail2ban -y
            dnf autoremove -y
            ;;
        arch | manjaro | parch)
            pacman -Rns --noconfirm fail2ban
            ;;
        *)
            echo -e "${red}不支持的操作系统，请手动卸载${plain}\n"
            exit 1
            ;;
        esac
        echo -e "${green}Fail2ban及IP限制已完全卸载！${plain}\n"
        before_show_menu
        ;;
    0)
        show_menu
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        remove_iplimit
        ;;
    esac
}

SSH_port_forwarding() {
    local server_ip=$(curl -s https://api.ipify.org)
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_listenIP=$(/usr/local/x-ui/x-ui setting -getListen true | grep -Eo 'listenIP: .+' | awk '{print $2}')
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local existing_key=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'key: .+' | awk '{print $2}')

    local config_listenIP=""
    local listen_choice=""

    if [[ -n "$existing_cert" && -n "$existing_key" ]]; then
        echo -e "${green}面板已启用SSL加密${plain}"
        before_show_menu
    fi
    if [[ -z "$existing_cert" && -z "$existing_key" && (-z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0") ]]; then
        echo -e "\n${red}警告：未检测到证书！面板连接不安全${plain}"
        echo "请申请证书或设置SSH端口转发"
    fi

    if [[ -n "$existing_listenIP" && "$existing_listenIP" != "0.0.0.0" && (-z "$existing_cert" && -z "$existing_key") ]]; then
        echo -e "\n${green}当前SSH端口转发配置：${plain}"
        echo -e "标准SSH命令："
        echo -e "${yellow}ssh -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\n使用SSH密钥连接："
        echo -e "${yellow}ssh -i <密钥路径> -L 2222:${existing_listenIP}:${existing_port} root@${server_ip}${plain}"
        echo -e "\n连接后访问地址："
        echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
    fi

    echo -e "\n请选择操作："
    echo -e "${green}1.${plain} 设置监听IP"
    echo -e "${green}2.${plain} 清除监听IP"
    echo -e "${green}0.${plain} 返回主菜单"
    read -p "请选择操作：" num

    case "$num" in
    1)
        if [[ -z "$existing_listenIP" || "$existing_listenIP" == "0.0.0.0" ]]; then
            echo -e "\n当前未配置监听IP，请选择："
            echo -e "1. 使用默认IP（127.0.0.1）"
            echo -e "2. 自定义IP"
            read -p "请选择（1或2）：" listen_choice

            config_listenIP="127.0.0.1"
            [[ "$listen_choice" == "2" ]] && read -p "请输入监听IP：" config_listenIP

            /usr/local/x-ui/x-ui setting -listenIP "${config_listenIP}" >/dev/null 2>&1
            echo -e "${green}监听IP已设置为 ${config_listenIP}${plain}"
            echo -e "\n${green}SSH端口转发配置：${plain}"
            echo -e "标准SSH命令："
            echo -e "${yellow}ssh -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
            echo -e "\n使用SSH密钥连接："
            echo -e "${yellow}ssh -i <密钥路径> -L 2222:${config_listenIP}:${existing_port} root@${server_ip}${plain}"
            echo -e "\n连接后访问地址："
            echo -e "${yellow}http://localhost:2222${existing_webBasePath}${plain}"
            restart
        else
            config_listenIP="${existing_listenIP}"
            echo -e "${green}当前监听IP已设置为 ${config_listenIP}${plain}"
        fi
        ;;
    2)
        /usr/local/x-ui/x-ui setting -listenIP 0.0.0.0 >/dev/null 2>&1
        echo -e "${green}监听IP已清除${plain}"
        restart
        ;;
    0)
        show_menu
        ;;
    *)
        echo -e "${red}无效选项，请重新选择${plain}\n"
        SSH_port_forwarding
        ;;
    esac
}

show_usage() {
    echo -e "┌───────────────────────────────────────────────────────
│  ${blue}x-ui 控制菜单使用方法（子命令）：${plain}              
│                                                       
│  ${blue}x-ui${plain}               - 显示管理菜单               
│  ${blue}x-ui start${plain}         - 启动服务                  
│  ${blue}x-ui stop${plain}          - 停止服务                  
│  ${blue}x-ui restart${plain}       - 重启服务                  
│  ${blue}x-ui status${plain}        - 查看状态                  
│  ${blue}x-ui settings${plain}      - 查看当前设置              
│  ${blue}x-ui enable${plain}        - 启用开机自启              
│  ${blue}x-ui disable${plain}       - 禁用开机自启             
│  ${blue}x-ui log${plain}           - 查看日志                  
│  ${blue}x-ui banlog${plain}        - 查看封禁日志              
│  ${blue}x-ui update${plain}        - 更新面板                  
│  ${blue}x-ui legacy${plain}        - 安装旧版本                
│  ${blue}x-ui install${plain}       - 全新安装                  
│  ${blue}x-ui uninstall${plain}     - 完全卸载                  
└───────────────────────────────────────────────────────"
}

show_menu() {
    echo -e "
╔───────────────────────────────
│   ${green}3X-UI 面板管理脚本${plain}                    
│   ${green}0.${plain} 退出脚本                          
│───────────────────────────────
│   ${green}1.${plain} 安装面板                              
│   ${green}2.${plain} 更新面板                              
│   ${green}3.${plain} 更新菜单                             
│   ${green}4.${plain} 安装旧版                             
│   ${green}5.${plain} 卸载面板                           
│───────────────────────────────
│   ${green}6.${plain} 重置用户名/密码/安全令牌               
│   ${green}7.${plain} 重置Web路径                           
│   ${green}8.${plain} 恢复默认设置                       
│   ${green}9.${plain} 修改面板端口                             
│  ${green}10.${plain} 查看当前设置                              
│───────────────────────────────
│  ${green}11.${plain} 启动面板                                  
│  ${green}12.${plain} 停止面板                                  
│  ${green}13.${plain} 重启面板                                  
│  ${green}14.${plain} 查看状态                                  
│  ${green}15.${plain} 日志管理                                  
│───────────────────────────────
│  ${green}16.${plain} 启用自启                                  
│  ${green}17.${plain} 禁用自启                                  
│───────────────────────────────
│  ${green}18.${plain} SSL证书管理                               
│  ${green}19.${plain} Cloudflare证书                            
│  ${green}20.${plain} IP限制管理                                
│  ${green}21.${plain} 防火墙管理                                
│  ${green}22.${plain} SSH端口转发                               
│───────────────────────────────
│  ${green}23.${plain} 启用BBR                                   
│  ${green}24.${plain} 更新地理文件                              
│  ${green}25.${plain} 网络测速                                  
╚───────────────────────────────
"
    show_status
    echo && read -p "请输入数字选择 [0-25]：" num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && update_menu
        ;;
    4)
        check_install && legacy_version
        ;;
    5)
        check_install && uninstall
        ;;
    6)
        check_install && reset_user
        ;;
    7)
        check_install && reset_webbasepath
        ;;
    8)
        check_install && reset_config
        ;;
    9)
        check_install && set_port
        ;;
    10)
        check_install && check_config
        ;;
    11)
        check_install && start
        ;;
    12)
        check_install && stop
        ;;
    13)
        check_install && restart
        ;;
    14)
        check_install && status
        ;;
    15)
        check_install && show_log
        ;;
    16)
        check_install && enable
        ;;
    17)
        check_install && disable
        ;;
    18)
        ssl_cert_issue_main
        ;;
    19)
        ssl_cert_issue_CF
        ;;
    20)
        iplimit_main
        ;;
    21)
        firewall_menu
        ;;
    22)
        SSH_port_forwarding
        ;;
    23)
        bbr_menu
        ;;
    24)
        update_geo
        ;;
    25)
        run_speedtest
        ;;
    *)
        LOGE "请输入正确数字 [0-25]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "settings")
        check_install 0 && check_config 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "banlog")
        check_install 0 && show_banlog 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "legacy")
        check_install 0 && legacy_version 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
