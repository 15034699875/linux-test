#!/bin/bash

# 检测操作系统类型
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(lsb_release -si)
    fi
    echo -e "\e[34m检测到操作系统: $OS\e[0m"
}

# 新增国家检测函数
detect_country() {
    country=$(curl -s --connect-timeout 5 ipinfo.io/country 2>/dev/null)
    if [[ $? -eq 0 && $country == "CN" ]]; then
        return 0 # 中国
    else
        return 1 # 境外
    fi
}

# 新增系统信息展示函数
system_info() {
    echo -e "\e[34m系统信息概览:\e[0m"
    echo "---------------------------------------------"
    
    # 系统版本
    echo "操作系统版本："
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "  系统名称: $NAME ($VERSION)"
    else
        echo "  系统名称: $(lsb_release -d -s)"
    fi
    
    # 地理位置信息
    echo "地理位置："
    if detect_country; then
        echo "  位于中国境内"
    else
        echo "  位于境外"
    fi
    
    # 网络信息
    public_ip=$(curl -s --connect-timeout 5 ifconfig.me/ip 2>/dev/null)
    echo "网络信息："
    echo "  公网IP: ${public_ip:-未检测到}"
    echo "  私网IP:"
    ip -o -4 addr show scope global up primary | awk '{print "    " $4}' | cut -d/ -f1 | while read ip; do
        echo "    $ip"
    done
    
    # 硬件资源
    echo "硬件资源："
    echo "  CPU核心: $(nproc)"
    echo -n "  内存使用: "
    free -m | awk '/Mem/{printf "%.1fGB/%.1fGB (%.0f%%)\n", $3/1024, $2/1024, $3/$2*100}'
    echo -n "  磁盘使用: "
    df -h / | awk 'NR==2{printf "%s已用, 总容量%s (%s)\n",$3,$2,$5}'
    
    echo "---------------------------------------------"
}

# 新增卸载函数
uninstall_docker() {
    echo -e "\e[34m正在卸载Docker...\e[0m"
    if [[ $OS == "centos" || $OS == "rhel" ]]; then
        sudo systemctl stop docker
        sudo yum remove -y docker docker-ce docker-ce-cli containerd.io
    elif [[ $OS == "ubuntu" ]]; then
        sudo systemctl stop docker
        sudo apt-get purge -y docker.io docker-ce docker-ce-cli containerd.io
    fi
    sudo rm -rf /etc/docker /var/lib/docker
    sudo systemctl disable docker
    echo -e "\e[32mDocker已成功卸载\e[0m"
}

uninstall_kubernetes() {
    echo -e "\e[34m正在卸载Kubernetes组件...\e[0m"
    if [[ $OS == "centos" || $OS == "rhel" ]]; then
        sudo yum remove -y kubelet kubeadm kubectl
    elif [[ $OS == "ubuntu" ]]; then
        sudo apt-get purge -y kubelet kubeadm kubectl
    fi
    sudo rm -rf /etc/kubernetes
    echo -e "\e[32mKubernetes组件已成功卸载\e[0m"
}

uninstall_containerd() {
    echo -e "\e[34m正在卸载containerd...\e[0m"
    if [[ $OS == "centos" || $OS == "rhel" ]]; then
        sudo systemctl stop containerd
        sudo yum remove -y containerd.io
    elif [[ $OS == "ubuntu" ]]; then
        sudo systemctl stop containerd
        sudo apt-get purge -y containerd.io
    fi
    sudo rm -rf /etc/containerd /var/lib/containerd
    echo -e "\e[32mcontainerd已成功卸载\e[0m"
}

# 修改主菜单结构，使用二级菜单
main_menu() {
    while true; do
        system_info
        PS3="请选择管理组件（输入数字选择）: "
        options=("管理Docker" "管理Kubernetes" "管理containerd" "退出")
        select opt in "${options[@]}"; do
            case $opt in
                "管理Docker") docker_menu ;;
                "管理Kubernetes") kubernetes_menu ;;
                "管理containerd") containerd_menu ;;
                "退出") exit ;;
                *) echo "无效选项，请重新选择";;
            esac
            break
        done
    done
}

# 新增组件专用二级菜单
docker_menu() {
    while true; do
        echo -e "\e[34mDocker管理菜单\e[0m"
        PS3="请选择操作（输入数字选择）: "
        options=("安装Docker" "卸载Docker" "返回上级菜单")
        select opt in "${options[@]}"; do
            case $opt in
                "安装Docker") install_docker ;;
                "卸载Docker") uninstall_docker ;;
                "返回上级菜单") return ;;
                *) echo "无效选项，请重新选择";;
            esac
            break
        done
    done
}

kubernetes_menu() {
    while true; do
        echo -e "\e[34mKubernetes管理菜单\e[0m"
        PS3="请选择操作（输入数字选择）: "
        options=("安装Kubernetes" "卸载Kubernetes" "返回上级菜单")
        select opt in "${options[@]}"; do
            case $opt in
                "安装Kubernetes") install_kubernetes ;;
                "卸载Kubernetes") uninstall_kubernetes ;;
                "返回上级菜单") return ;;
                *) echo "无效选项，请重新选择";;
            esac
            break
        done
    done
}

containerd_menu() {
    while true; do
        echo -e "\e[34mcontainerd管理菜单\e[0m"
        PS3="请选择操作（输入数字选择）: "
        options=("安装containerd" "卸载containerd" "返回上级菜单")
        select opt in "${options[@]}"; do
            case $opt in
                "安装containerd") install_containerd ;;
                "卸载containerd") uninstall_containerd ;;
                "返回上级菜单") return ;;
                *) echo "无效选项，请重新选择";;
            esac
            break
        done
    done
}

# 修改安装函数检测已安装状态
install_docker() {
    # 新增检测逻辑
    if command -v docker &> /dev/null; then
        echo -e "\e[33m检测到已安装Docker，版本：$(docker --version)\e[0m"
        read -p "是否要替换现有安装？(Y/n): " choice
        if [[ ! $choice =~ ^[Yy]$ ]]; then
            echo "跳过Docker安装"
            return
        fi
    fi

    if [[ $OS == "centos" || $OS == "rhel" ]]; then
        echo -e "\e[34m正在CentOS系统上安装Docker...\e[0m"
        # 替换为阿里云源
        sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo

        # 获取可用版本列表
        versions=$(yum list available docker-ce --quiet | grep docker-ce | awk '{print $2}' | sort -rV)
        echo "可用的Docker版本："
        echo "$versions"

        read -p "是否安装指定版本？(Y/n): " choice
        if [[ $choice =~ [Yy] ]]; then
            echo "可用的Docker版本："
            versions=$(yum list available docker-ce --quiet | grep docker-ce | awk '{print $2}' | sort -rV)
            select ver in $versions; do
                if [ -n "$ver" ]; then
                    version=$ver
                    break
                else
                    echo "无效选择，请重新选择"
                fi
            done
            sudo yum install -y docker-ce-$version docker-ce-cli-$version containerd.io
        else
            sudo yum install -y docker-ce docker-ce-cli containerd.io
        fi
    elif [[ $OS == "ubuntu" ]]; then
        echo -e "\e[34m正在Ubuntu系统上安装Docker...\e[0m"
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        read -p "是否安装指定版本？(Y/n): " choice
        if [[ $choice =~ [Yy] ]]; then
            echo "可用的Docker版本："
            versions=$(apt list --installed 2>/dev/null | grep docker-ce | awk '{print $2}' | sort -rV)
            select ver in $versions; do
                if [ -n "$ver" ]; then
                    version=${ver%%/*}
                    break
                else
                    echo "无效选择，请重新选择"
                fi
            done
            sudo apt-get install -y docker-ce=$version docker-ce-cli=$version containerd.io
        else
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        fi
    else
        echo -e "\e[31m不支持的系统类型\e[0m"
        return 1
    fi
    sudo systemctl enable --now docker && echo -e "\e[32mDocker安装完成\e[0m" || echo -e "\e[31m安装失败，请检查网络或版本号\e[0m"

    # 安装完成后替换镜像源
    if detect_country; then
        sudo mkdir -p /etc/docker
        cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "registry-mirrors": ["https://registry.docker-cn.com"]
}
EOF
        sudo systemctl restart docker
        echo -e "\e[32m已替换Docker镜像源为国内源\e[0m"
    else
        echo -e "\e[33m检测到服务器不在中国，不替换Docker镜像源\e[0m"
    fi
}

install_kubernetes() {
    # 新增检测逻辑
    if command -v kubelet &> /dev/null || command -v kubeadm &> /dev/null; then
        echo -e "\e[33m检测到已安装Kubernetes组件\e[0m"
        read -p "是否继续安装？(Y/n): " choice
        if [[ ! $choice =~ ^[Yy]$ ]]; then
            echo "跳过Kubernetes安装"
            return
        fi
    fi

    if [[ $OS == "centos" || $OS == "rhel" ]]; then
        echo -e "\e[34m正在CentOS系统上安装Kubernetes...\e[0m"
        cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
        sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    elif [[ $OS == "ubuntu" ]]; then
        echo -e "\e[34m正在Ubuntu系统上安装Kubernetes...\e[0m"
        sudo apt-get update && sudo apt-get install -y apt-transport-https
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo tee /etc/apt/keyrings/kubernetes.gpg > /dev/null
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://apt.kubernetes.io/ kubernetes-jammy main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

        # 在添加仓库后增加验证步骤
        if ! sudo apt-get update 2>&1 | grep -q 'Hit:1 https://apt.kubernetes.io'; then
            echo -e "\e[31mKubernetes仓库配置失败，请检查网络\e[0m"
            return 1
        fi
        sudo apt-get install -y kubelet kubeadm kubectl
    else
        echo -e "\e[31m不支持的系统类型\e[0m"
        return 1
    fi
    sudo systemctl enable --now kubelet && echo -e "\e[32mKubernetes组件安装完成\e[0m" || echo -e "\e[31m安装失败，请检查网络\e[0m"
}

# 修改containerd安装函数，增加仓库配置
install_containerd() {
    # 新增检测逻辑
    if command -v containerd &> /dev/null; then
        echo -e "\e[33m检测到已安装containerd，版本：$(containerd --version)\e[0m"
        read -p "是否要替换现有安装？(Y/n): " choice
        if [[ ! $choice =~ ^[Yy]$ ]]; then
            echo "跳过containerd安装"
            return
        fi
    fi

    if [[ $OS == "centos" || $OS == "rhel" ]]; then
        echo -e "\e[34m正在CentOS系统上安装containerd...\e[0m"
        sudo yum install -y containerd.io
    elif [[ $OS == "ubuntu" ]]; then
        echo -e "\e[34m正在Ubuntu系统上安装containerd...\e[0m"
        sudo apt-get update && sudo apt-get install -y curl gnupg
        # 添加containerd官方仓库
        sudo mkdir -m 0755 -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/containerd.gpg
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/containerd.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/containerd.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y containerd.io
    else
        echo -e "\e[31m不支持的系统类型\e[0m"
        return 1
    fi
    sudo systemctl enable --now containerd && echo -e "\e[32mcontainerd安装完成\e[0m" || echo -e "\e[31m安装失败，请检查网络\e[0m"

    # 安装完成后替换镜像源
    if detect_country; then
        sudo mkdir -p /etc/containerd
        # 生成默认配置
        sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
        # 添加镜像源配置
        sudo sed -i 's#\[plugins\."io.containerd.grpc.v1.cri".registry.mirrors\]#&\n\n[plugins\."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]\n  endpoint = ["https://registry.docker-cn.com"]#' /etc/containerd/config.toml
        sudo systemctl restart containerd
        echo -e "\e[32m已替换containerd镜像源为国内源\e[0m"
    else
        echo -e "\e[33m检测到服务器不在中国，不替换containerd镜像源\e[0m"
    fi
}

# 主程序入口
detect_os
main_menu