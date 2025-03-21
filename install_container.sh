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

# 主菜单函数
main_menu() {
    while true; do
        system_info
        PS3="请选择要安装的容器软件（输入数字选择）: "
        options=("Docker" "Kubernetes" "containerd" "退出")
        select opt in "${options[@]}"; do
            case $opt in
                "Docker") install_docker ;;
                "Kubernetes") install_kubernetes ;;
                "containerd") install_containerd ;;
                "退出") exit ;;
                *) echo "无效选项，请重新选择";;
            esac
            break
        done
    done
}

# Docker安装函数
install_docker() {
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
            read -p "请输入Docker版本号（从上面列表选择）: " version
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
            read -p "请输入Docker版本号: " version
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

# Kubernetes安装函数
install_kubernetes() {
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
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
        sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
    else
        echo -e "\e[31m不支持的系统类型\e[0m"
        return 1
    fi
    sudo systemctl enable --now kubelet && echo -e "\e[32mKubernetes组件安装完成\e[0m" || echo -e "\e[31m安装失败，请检查网络\e[0m"
}

# containerd安装函数
install_containerd() {
    if [[ $OS == "centos" || $OS == "rhel" ]]; then
        echo -e "\e[34m正在CentOS系统上安装containerd...\e[0m"
        sudo yum install -y containerd.io
    elif [[ $OS == "ubuntu" ]]; then
        echo -e "\e[34m正在Ubuntu系统上安装containerd...\e[0m"
        sudo apt-get update && sudo apt-get install -y containerd.io
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