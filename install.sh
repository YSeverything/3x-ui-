#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误：${plain} 请使用root权限运行此脚本！\n" && exit 1

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
echo "操作系统版本：$release"

# 识别CPU架构
arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}不支持的CPU架构! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "系统架构：$(arch)"

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

# 安装基础依赖
install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    centos | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar tzdata
        ;;
    esac
}

# 生成随机字符串
gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

# 安装后配置
config_after_install() {
    local existing_username=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'username: .+' | awk '{print $2}')
    local existing_password=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'password: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local server_ip=$(curl -s https://api.ipify.org)

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_username" == "admin" && "$existing_password" == "admin" ]]; then
            local config_webBasePath=$(gen_random_string 15)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -p "是否自定义面板端口？(否则将使用随机端口) [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -p "请输入面板端口号：" config_port
                echo -e "${yellow}您设置的面板端口：${config_port}${plain}"
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
                echo -e "${yellow}生成随机端口：${config_port}${plain}"
            fi

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "检测到全新安装，已生成随机登录信息："
            echo -e "###############################################"
            echo -e "${green}用户名：${config_username}${plain}"
            echo -e "${green}密码：${config_password}${plain}"
            echo -e "${green}端口：${config_port}${plain}"
            echo -e "${green}访问路径：${config_webBasePath}${plain}"
            echo -e "${green}面板地址：http://${server_ip}:${config_port}/${config_webBasePath}${plain}"
            echo -e "###############################################"
            echo -e "${yellow}如需查看登录信息，可输入命令：x-ui settings${plain}"
        else
            local config_webBasePath=$(gen_random_string 15)
            echo -e "${yellow}检测到访问路径过短，正在生成新的访问路径...${plain}"
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
            echo -e "${green}新访问路径：${config_webBasePath}${plain}"
            echo -e "${green}面板地址：http://${server_ip}:${existing_port}/${config_webBasePath}${plain}"
        fi
    else
        if [[ "$existing_username" == "admin" && "$existing_password" == "admin" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            echo -e "${yellow}检测到默认凭证，正在进行安全加固...${plain}"
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "已生成新的随机登录凭证："
            echo -e "###############################################"
            echo -e "${green}用户名：${config_username}${plain}"
            echo -e "${green}密码：${config_password}${plain}"
            echo -e "###############################################"
            echo -e "${yellow}如需查看登录信息，可输入命令：x-ui settings${plain}"
        else
            echo -e "${green}用户名、密码和访问路径设置正确，无需修改${plain}"
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

# 安装x-ui核心
install_x-ui() {
    cd /usr/local/

    if [ $# == 0 ]; then
        tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            echo -e "${red}获取最新版本失败，可能是由于GitHub API限制，请稍后重试${plain}"
            exit 1
        fi
        echo -e "正在安装x-ui最新版本：${tag_version}..."
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载x-ui失败，请检查服务器网络连接${plain}"
            exit 1
        fi
    else
        tag_version=$1
        tag_version_numeric=${tag_version#v}
        min_version="2.3.5"

        if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
            echo -e "${red}请使用更新版本的x-ui (最低v2.3.5)，安装中止${plain}"
            exit 1
        fi

        url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
        echo -e "正在安装指定版本x-ui $1"
        wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载x-ui $1 失败，请检查版本是否存在 ${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    cd x-ui
    chmod +x x-ui

    # 处理ARM架构重命名
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi

    chmod +x x-ui bin/xray-linux-$(arch)
    cp -f x-ui.service /etc/systemd/system/
    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui ${tag_version}${plain} 安装完成，服务已启动"
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui 控制命令使用说明：${plain}                          │
│                                                       │
│  ${blue}x-ui${plain}              - 显示管理菜单                  │
│  ${blue}x-ui start${plain}        - 启动服务                      │
│  ${blue}x-ui stop${plain}         - 停止服务                      │
│  ${blue}x-ui restart${plain}      - 重启服务                      │
│  ${blue}x-ui status${plain}       - 查看状态                      │
│  ${blue}x-ui settings${plain}     - 查看配置信息                  │
│  ${blue}x-ui enable${plain}       - 设置开机启动                  │
│  ${blue}x-ui disable${plain}      - 取消开机启动                  │
│  ${blue}x-ui log${plain}          - 查看日志                      │
│  ${blue}x-ui banlog${plain}       - 查看封禁记录                  │
│  ${blue}x-ui update${plain}       - 更新面板                      │
│  ${blue}x-ui legacy${plain}       - 安装旧版                      │
│  ${blue}x-ui install${plain}      - 全新安装                      │
│  ${blue}x-ui uninstall${plain}    - 完全卸载                      │
└───────────────────────────────────────────────────────┘"
}

echo -e "${green}安装程序启动...${plain}"
install_base
install_x-ui $1
