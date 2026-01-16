# HomeLab 구축 시 사용했던 Terraform 스크립트
promox환경 IaC코드


## Cloud Template 생성

Template은 Proxmox Node에서 진행

```bash
qm create 5000 --memory 2048 --core 2 --name ubuntu-24.04 --net0 virtio,bridge=vmbr0
cd /var/lib/vz/template/iso/
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
qm importdisk 5000 noble-server-cloudimg-amd64.img loca
qm set 5000 --scsihw virtio-scsi-pci --scsi0 local:5000/vm-5000-disk-0.raw
qm set 5000 --ide2 local:cloudinit
qm set 5000 --boot c --bootdisk scsi0
qm template 5000
```

## template 생성 후 실행 방법

```bash
git clone https://github.com/ymir0804/proxmox.git
cd proxmox
tofu init
tofu plan
tofu apply

```


## Variables 
terraform.tfvars 파일 생성 후 해당 파일에 다음과 같이 조건을 넣어야 해당 스크립트가 수행됩니다.
```
proxmox_api_url = ""
proxmox_user    = "" # root@pam
proxmox_password = ""
default_user = "" # k8s용이라 kubeadm 계정 추가
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2TgloDggP7rKakdH57I6BJTbU0fgzeljjN1WZD42pZGkMEwI..."
```


