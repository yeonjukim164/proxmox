#!/usr/bin/env bash

# 실행 중 에러 발생 시 계속 진행 (디버깅 용이성 위함)
set +e

echo ">>>> Initial Config Start (Ubuntu) <<<<"

echo "[TASK 1] Change Timezone and Enable NTP"
# Ubuntu는 systemd-timesyncd 기본 활성화
timedatectl set-local-rtc 0
timedatectl set-timezone Asia/Seoul

echo "[TASK 2] Disable UFW (Firewall) and AppArmor"
systemctl disable --now ufw >/dev/null 2>&1
# AppArmor 정지 (필요 시)
systemctl stop apparmor >/dev/null 2>&1
systemctl disable apparmor >/dev/null 2>&1
# SELinux는 Ubuntu에 기본적으로 없으나 호환성 위해 남겨둘 경우:
# setenforce 0 2>/dev/null || true

echo "[TASK 3] Disable and turn off SWAP & Delete swap partitions"
swapoff -a
# fstab에서 swap 라인 주석 처리 (sed 문법 동일)
sed -i '/swap/d' /etc/fstab

# Swap 파티션 삭제는 신중해야 함. Ubuntu 설치 방식(LVM vs 일반 파티션)에 따라 다름.
# 일반적으로 swapoff와 fstab 제거만으로 K8s 동작엔 충분함.
# 만약 물리 파티션을 꼭 지워야 한다면 아래 코드 유지 (에러 무시 처리 추가)
sfdisk --delete /dev/sda 2 >/dev/null 2>&1 || true
# 파티션 테이블 변경 사항 커널에 알림
partprobe /dev/sda >/dev/null 2>&1 || true

echo "[TASK 4] Config kernel & module"
cat << EOF | tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF

modprobe overlay >/dev/null 2>&1
modprobe br_netfilter >/dev/null 2>&1

cat << EOF | tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system >/dev/null 2>&1

echo "[TASK 5] Setting Local DNS Using Hosts file"
# Ubuntu의 127.0.1.1 설정을 제거하여 호스트명 충돌 방지
sed -i '/^127\.0\.\(1\|2\)\.1/d' /etc/hosts
echo "192.168.10.10 k8s-api-srv.admin-lb.com admin-lb" >> /etc/hosts
for (( i=1; i<=$1; i++  )); do echo "192.168.10.1$i k8s-node$i" >> /etc/hosts; done

echo "[TASK 7] Setting SSHD"
# root 비밀번호 설정
echo "root:qwe123" | chpasswd

# sshd_config 수정 (tee 사용 권장)
cat << EOF | tee -a /etc/ssh/sshd_config >/dev/null
PermitRootLogin yes
PasswordAuthentication yes
EOF

systemctl restart sshd >/dev/null 2>&1

echo "[TASK 8] Install packages"
apt-get update -y -q >/dev/null 2>&1
# nfs-utils -> nfs-common (클라이언트 기능)
apt-get install -y git nfs-common >/dev/null 2>&1

echo "[TASK 9] ETC"
# 사용자 홈 디렉토리 체크 후 적용
if [ -d "/home/kubeadm" ]; then
    echo "sudo su -" >> /home/kubeadm/.bashrc
fi

echo ">>>> Initial Config End (Ubuntu) <<<<"
