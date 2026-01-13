#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}System version not detected, please contact the script author!${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="amd64"
    echo -e "${red}Architecture detection failed, using default: ${arch}${plain}"
fi

echo "Architecture: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "This software does not support 32-bit systems (x86). Please use a 64-bit system (x86_64). If this is an error, please contact the author."
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or a higher version!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or a higher version!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or a higher version!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

# This function will be called when user installed x-ui out of security
config_after_install() {
    echo -e "${yellow}For security reasons, you must modify the port, username, and password after installation/update.${plain}"
    read -p "Confirm to continue? [y/n]: " config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "Please set your username: " config_account
        echo -e "${yellow}Your username will be set to: ${config_account}${plain}"
        read -p "Please set your password: " config_password
        echo -e "${yellow}Your password will be set to: ${config_password}${plain}"
        read -p "Please set the panel access port: " config_port
        echo -e "${yellow}Your panel access port will be set to: ${config_port}${plain}"
        echo -e "${yellow}Confirming settings, applying...${plain}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${yellow}Username and password configuration completed.${plain}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${yellow}Panel port configuration completed.${plain}"
    else
        echo -e "${red}Cancelled. All settings remain at default values. Please modify them promptly.${plain}"
    fi
}

install_x-ui() {
    # 0. 從原始碼編譯
    echo -e "${yellow}正在從原始碼編譯 x-ui...${plain}"
    if ! command -v go &> /dev/null; then
        echo -e "${red}錯誤: 未偵測到 Go 環境，請先安裝 Go 1.21 或以上版本。${plain}"
        exit 1
    fi

    # 執行編譯
    go mod tidy
    go build -o x-ui main.go

    if [ ! -f "x-ui" ]; then
        echo -e "${red}編譯失敗！請檢查程式碼。${plain}"
        exit 1
    fi
    echo -e "${green}編譯成功！${plain}"

    # 1. 停止舊服務並清理目錄
    systemctl stop x-ui 2>/dev/null 
    mkdir -p /usr/local/x-ui

    # 2. 直接從目前的 git 目錄複製檔案到安裝目錄
    cp -r ./* /usr/local/x-ui/

    # 3. 進入安裝目錄設定權限
    cd /usr/local/x-ui
    chmod +x x-ui bin/xray-linux-amd64 

    # 4. 複製服務設定檔與管理腳本
    cp -f x-ui.service /etc/systemd/system/
    cp -f x-ui.sh /usr/bin/x-ui
    chmod +x /usr/bin/x-ui
    chmod +x /usr/local/x-ui/x-ui.sh

    # 5. 執行安裝後的帳密設定
    config_after_install
    
    # 注意：在 Docker 中以下 systemctl 指令會失敗，稍後需手動啟動
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui v${last_version}${plain} installation complete. The panel has started."
    echo -e ""
    echo -e "x-ui Management Script Usage: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - Show management menu (more features)"
    echo -e "x-ui start        - Start x-ui panel"
    echo -e "x-ui stop         - Stop x-ui panel"
    echo -e "x-ui restart      - Restart x-ui panel"
    echo -e "x-ui status       - Check x-ui status"
    echo -e "x-ui enable       - Set x-ui to start on boot"
    echo -e "x-ui disable      - Disable x-ui from starting on boot"
    echo -e "x-ui log          - Check x-ui logs"
    echo -e "x-ui v2-ui        - Migrate v2-ui data from this machine to x-ui"
    echo -e "x-ui update       - Update x-ui panel"
    echo -e "x-ui install      - Install x-ui panel"
    echo -e "x-ui uninstall    - Uninstall x-ui panel"
    echo -e "----------------------------------------------"
}

echo -e "${green}Starting installation...${plain}"
install_base
install_x-ui $1