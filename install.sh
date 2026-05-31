#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

SCRIPT_OWNER="zcw666806"
SCRIPT_REPO="XrayR-release"
SCRIPT_BRANCH="master"
SCRIPT_RAW_BASE="https://raw.githubusercontent.com/${SCRIPT_OWNER}/${SCRIPT_REPO}/${SCRIPT_BRANCH}"
RELEASE_API="https://api.github.com/repos/${SCRIPT_OWNER}/${SCRIPT_REPO}/releases/latest"
RELEASE_BASE="https://github.com/${SCRIPT_OWNER}/${SCRIPT_REPO}/releases/download"
CONFIG_FILES=(config.yml dns.json route.json custom_outbound.json custom_inbound.json rulelist geoip.dat geosite.dat)

cur_dir=$(pwd)
temp_dir=""

cleanup() {
    if [[ -n "${temp_dir}" && -d "${temp_dir}" ]]; then
        rm -rf "${temp_dir}"
    fi
}
trap cleanup EXIT

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif grep -Eqi "debian" /etc/issue; then
    release="debian"
elif grep -Eqi "ubuntu" /etc/issue; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /etc/issue; then
    release="centos"
elif grep -Eqi "debian" /proc/version; then
    release="debian"
elif grep -Eqi "ubuntu" /proc/version; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat" /proc/version; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${yellow}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ]; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
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
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

download_file() {
    local url=$1
    local output=$2
    local description=$3

    if ! wget -q --no-check-certificate -O "${output}" "${url}"; then
        echo -e "${red}下载${description}失败：${url}${plain}"
        exit 1
    fi
}

download_config_templates() {
    local config_file

    mkdir -p "${temp_dir}/config"
    for config_file in "${CONFIG_FILES[@]}"; do
        download_file "${SCRIPT_RAW_BASE}/config/${config_file}" "${temp_dir}/config/${config_file}" "配置文件 ${config_file}"
    done
}

install_config_templates() {
    local config_file

    mkdir -p /etc/XrayR

    # 数据库文件随仓库版本更新；可编辑配置只在不存在时安装，避免更新时覆盖本机配置。
    cp -f "${temp_dir}/config/geoip.dat" /etc/XrayR/geoip.dat
    cp -f "${temp_dir}/config/geosite.dat" /etc/XrayR/geosite.dat

    for config_file in config.yml dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
        if [[ ! -f "/etc/XrayR/${config_file}" ]]; then
            cp "${temp_dir}/config/${config_file}" "/etc/XrayR/${config_file}"
        fi
    done
}

install_XrayR() {
    local last_version
    local url
    local had_config=0

    temp_dir=$(mktemp -d)

    if [[ $# == 0 || -z "$1" ]]; then
        last_version=$(curl -fLs "${RELEASE_API}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | head -n 1)
        if [[ -z "${last_version}" ]]; then
            echo -e "${red}检测 XrayR 版本失败。请确认仓库 ${SCRIPT_OWNER}/${SCRIPT_REPO} 已发布 GitHub Release，或手动指定版本安装。${plain}"
            exit 1
        fi
        echo -e "检测到 XrayR 最新版本：${last_version}，开始安装"
    else
        # 指定版本时按输入的 Release tag 原样下载，兼容 0.9.5、v0.9.5 和自定义 tag。
        last_version=$1
        echo -e "开始安装 XrayR ${last_version}"
    fi

    url="${RELEASE_BASE}/${last_version}/XrayR-linux-${arch}.zip"
    download_file "${url}" "${temp_dir}/XrayR-linux.zip" " XrayR ${last_version}"
    if ! unzip -q "${temp_dir}/XrayR-linux.zip" -d "${temp_dir}/XrayR"; then
        echo -e "${red}解压 XrayR ${last_version} 失败，请检查 Release ZIP 文件是否完整。${plain}"
        exit 1
    fi
    if [[ ! -f "${temp_dir}/XrayR/XrayR" ]]; then
        echo -e "${red}Release ZIP 根目录中缺少 XrayR 可执行文件。${plain}"
        exit 1
    fi

    download_file "${SCRIPT_RAW_BASE}/XrayR.service" "${temp_dir}/XrayR.service" " XrayR.service"
    download_file "${SCRIPT_RAW_BASE}/XrayR.sh" "${temp_dir}/XrayR.sh" " XrayR 管理脚本"
    download_config_templates

    if [[ -f /etc/XrayR/config.yml ]]; then
        had_config=1
    fi

    systemctl stop XrayR 2>/dev/null || true
    rm -rf /usr/local/XrayR
    mv "${temp_dir}/XrayR" /usr/local/XrayR
    chmod +x /usr/local/XrayR/XrayR

    install_config_templates
    install -m 644 "${temp_dir}/XrayR.service" /etc/systemd/system/XrayR.service
    install -m 755 "${temp_dir}/XrayR.sh" /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr

    systemctl daemon-reload
    systemctl enable XrayR
    echo -e "${green}XrayR ${last_version}${plain} 安装完成，已设置开机自启"

    if [[ ${had_config} == 0 ]]; then
        echo -e ""
        echo -e "全新安装：已从 ${SCRIPT_RAW_BASE}/config/ 安装配置模板。请先修改 /etc/XrayR/config.yml 等配置文件，再执行 XrayR start。"
    else
        systemctl start XrayR
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 重启成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请稍后使用 XrayR log 查看日志信息，并检查 /etc/XrayR/ 下的配置文件。${plain}"
        fi
    fi

    cd "${cur_dir}"
    echo -e ""
    echo "XrayR 管理脚本使用方法 (兼容使用xrayr执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "XrayR                    - 显示管理菜单 (功能更多)"
    echo "XrayR start              - 启动 XrayR"
    echo "XrayR stop               - 停止 XrayR"
    echo "XrayR restart            - 重启 XrayR"
    echo "XrayR status             - 查看 XrayR 状态"
    echo "XrayR enable             - 设置 XrayR 开机自启"
    echo "XrayR disable            - 取消 XrayR 开机自启"
    echo "XrayR log                - 查看 XrayR 日志"
    echo "XrayR update             - 更新 XrayR"
    echo "XrayR update x.x.x       - 更新 XrayR 指定版本"
    echo "XrayR config             - 显示配置文件内容"
    echo "XrayR install            - 安装 XrayR"
    echo "XrayR uninstall          - 卸载 XrayR"
    echo "XrayR version            - 查看 XrayR 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_XrayR "$1"
