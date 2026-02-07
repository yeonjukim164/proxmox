#!/usr/bin/env bash

# 스크립트 실행 중 에러 발생 시 계속 진행하도록 설정 (필요시 set -e 로 변경)
set +e

echo ">>>> Initial Config Start (Ubuntu) <<<<"
# PATH 설정 (exportfs 등이 /usr/sbin에 있으므로 경로 명시적으로 추가)
export PATH=$PATH:/usr/sbin:/usr/bin:/sbin:/bin

echo "[TASK 1] Change Timezone and Enable NTP"
# Ubuntu는 systemd-timesyncd가 기본적으로 활성화되어 있음
timedatectl set-local-rtc 0
timedatectl set-timezone Asia/Seoul

echo "[TASK 2] Disable UFW (Firewall) and AppArmor (Optional)"
# Ubuntu는 firewalld 대신 ufw 사용
systemctl disable --now ufw >/dev/null 2>&1
# SELinux 대신 AppArmor 사용 (보통 끄지 않아도 되지만 필요하다면 systemctl stop apparmor)
# Ubuntu에는 기본적으로 /etc/selinux/config 파일이 없으므로 주석 처리
# setenforce 0 
# sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

echo "[TASK 3] Setting Local DNS Using Hosts file"
# Ubuntu의 127.0.1.1 설정을 제거하여 호스트명 충돌 방지
sed -i '/^127\.0\.\(1\|2\)\.1/d' /etc/hosts
echo "192.168.0.20 k8s-api-srv.admin-lb.com admin-lb" >> /etc/hosts
# 인자($1)로 받은 노드 수만큼 hosts 파일에 추가
for (( i=1; i<=$1; i++  )); do echo "192.168.0.2$i k8s-node$i" >> /etc/hosts; done


echo "[TASK 5] Install kubectl"
apt-get update -y -q >/dev/null 2>&1
apt-get install -y -q apt-transport-https ca-certificates curl gnupg >/dev/null 2>&1

# Kubernetes GPG 키 및 저장소 추가 (v1.32 기준)
mkdir -p -m 755 /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

apt-get update -y -q >/dev/null 2>&1
apt-get install -y -q kubectl >/dev/null 2>&1

echo "[TASK 6] Install HAProxy"
# 설치 전 업데이트 및 설치 확인
apt-get update -y -q >/dev/null 2>&1
apt-get install -y haproxy >/dev/null 2>&1

# 디렉토리가 없을 경우를 대비해 생성
mkdir -p /etc/haproxy

# 리다이렉션 에러 방지를 위해 tee 사용
cat << EOF | tee /etc/haproxy/haproxy.cfg > /dev/null
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats
    ssl-default-bind-ciphers PROFILE=SYSTEM
    ssl-default-server-ciphers PROFILE=SYSTEM

defaults
    mode                    http
    log                     global
    option                  httplog
    option                  tcplog
    option                  dontlognull
    option http-server-close
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

# ---------------------------------------------------------------------
# Kubernetes API Server Load Balancer Configuration
# ---------------------------------------------------------------------
frontend k8s-api
    bind *:6443
    mode tcp
    option tcplog
    default_backend k8s-api-backend

backend k8s-api-backend
    mode tcp
    option tcp-check
    option log-health-checks
    timeout client 3h
    timeout server 3h
    balance roundrobin
    server k8s-node1 192.168.0.21:6443 check check-ssl verify none inter 10000
    server k8s-node2 192.168.0.22:6443 check check-ssl verify none inter 10000
    server k8s-node3 192.168.0.23:6443 check check-ssl verify none inter 10000

# ---------------------------------------------------------------------
# HAProxy Stats Dashboard
# ---------------------------------------------------------------------
listen stats
    bind *:9000
    mode http
    stats enable
    stats uri /haproxy_stats
    stats realm HAProxy\ Statistic
    stats admin if TRUE

# ---------------------------------------------------------------------
# Prometheus exporter
# ---------------------------------------------------------------------
frontend prometheus
    bind *:8405
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
    no log
EOF

systemctl restart haproxy >/dev/null 2>&1
systemctl enable haproxy >/dev/null 2>&1

# ------------------------------------------------------------------
# [TASK 7] Install NFS Server (수정됨)
# ------------------------------------------------------------------
echo "[TASK 7] Install NFS Server"
# 패키지명 확실히 지정 및 재설치 시도
apt-get install -y nfs-kernel-server >/dev/null 2>&1

# 서비스 시작 (설치 직후 안 떠있을 수 있음)
systemctl start nfs-kernel-server >/dev/null 2>&1
systemctl enable nfs-kernel-server >/dev/null 2>&1

mkdir -p /srv/nfs/share
chown nobody:nogroup /srv/nfs/share
chmod 755 /srv/nfs/share

# tee 사용으로 쓰기 권한 문제 방지
echo '/srv/nfs/share *(rw,async,no_root_squash,no_subtree_check)' | tee /etc/exports > /dev/null

# exportfs 명령어가 PATH에 없을 경우 절대 경로 사용 (/usr/sbin/exportfs)
if command -v exportfs >/dev/null 2>&1; then
    exportfs -rav
elif [ -f "/usr/sbin/exportfs" ]; then
    /usr/sbin/exportfs -rav
else
    echo "Error: exportfs command not found. NFS install failed?"
fi


echo "[TASK 8] Install packages"
# python3-pip 설치 (최신 Ubuntu는 python3-pip 패키지명이 그대로 유지되나 pip 사용 시 주의 필요)
apt-get install -y python3-pip git sshpass >/dev/null 2>&1

echo "[TASK 9] Setting SSHD"
# root 비밀번호 설정 (보안상 주의)
echo "root:qwe123" | chpasswd

# sshd_config 수정
cat << EOF >> /etc/ssh/sshd_config
PermitRootLogin yes
PasswordAuthentication yes
EOF
systemctl restart sshd >/dev/null 2>&1

echo "[TASK 10] Setting SSH Key"
# 키가 없을 때만 생성
if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa >/dev/null 2>&1
fi

# SSH Key 복사 (192.168.0.x 대역 사용 가정)
sshpass -p 'qwe123' ssh-copy-id -o StrictHostKeyChecking=no root@192.168.0.20 >/dev/null 2>&1

for (( i=1; i<=$1; i++  )); do 
    sshpass -p 'qwe123' ssh-copy-id -o StrictHostKeyChecking=no root@192.168.0.2$i >/dev/null 2>&1
done

ssh -o StrictHostKeyChecking=no root@admin-lb hostname >/dev/null 2>&1
for (( i=1; i<=$1; i++  )); do 
    sshpass -p 'qwe123' ssh -o StrictHostKeyChecking=no root@k8s-node$i hostname >/dev/null 2>&1
done

echo "[TASK 11] Clone Kubespray Repository"
# 기존 폴더 제거 후 클론 (멱등성 보장)
rm -rf /root/kubespray
git clone -b v2.29.1 https://github.com/kubernetes-sigs/kubespray.git /root/kubespray >/dev/null 2>&1

cp -rfp /root/kubespray/inventory/sample /root/kubespray/inventory/mycluster
cat << EOF > /root/kubespray/inventory/mycluster/inventory.ini
[kube_control_plane]
k8s-node1 ansible_host=192.168.0.21 ip=192.168.0.21 etcd_member_name=etcd1
k8s-node2 ansible_host=192.168.0.22 ip=192.168.0.22 etcd_member_name=etcd2
k8s-node3 ansible_host=192.168.0.23 ip=192.168.0.23 etcd_member_name=etcd3

[etcd:children]
kube_control_plane

[kube_node]
k8s-node4 ansible_host=192.168.0.24 ip=192.168.0.24
#k8s-node5 ansible_host=192.168.0.25 ip=192.168.0.25
EOF

echo "[TASK 12] Install Python Dependencies"
# 최신 Ubuntu(23.04+)에서는 시스템 pip 사용 제한됨. --break-system-packages 옵션 추가 시도.
# 또는 가상환경 사용 권장되나, 편의상 플래그 사용.
pip3 install -r /root/kubespray/requirements.txt --break-system-packages >/dev/null 2>&1 || pip3 install -r /root/kubespray/requirements.txt >/dev/null 2>&1

echo "[TASK 13] Install K9s"
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
wget -P /tmp https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${CLI_ARCH}.tar.gz >/dev/null 2>&1
tar -xzf /tmp/k9s_linux_${CLI_ARCH}.tar.gz -C /tmp
chown root:root /tmp/k9s
mv /tmp/k9s /usr/local/bin/
chmod +x /usr/local/bin/k9s

echo "[TASK 14] Install kubecolor"
# Ubuntu용 kubecolor 설치 (GitHub Release에서 바이너리 다운로드)
KUBECOLOR_VERSION="0.0.25"
curl -fsSL https://github.com/hidetatz/kubecolor/releases/download/v${KUBECOLOR_VERSION}/kubecolor_${KUBECOLOR_VERSION}_Linux_x86_64.tar.gz -o /tmp/kubecolor.tar.gz
tar -xzf /tmp/kubecolor.tar.gz -C /tmp
mv /tmp/kubecolor /usr/local/bin/
chmod +x /usr/local/bin/kubecolor

echo "[TASK 15] Install Helm"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION=v3.18.6 bash >/dev/null 2>&1

echo "[TASK 16] ETC"
# 사용자 홈 디렉토리 존재 확인 후 .bashrc 수정
if [ -d "/home/kubeadm" ]; then
    echo "sudo su -" >> /home/kubeadm/.bashrc
fi

echo ">>>> Initial Config End (Ubuntu) <<<<"
