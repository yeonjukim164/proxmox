# HomeLab 구축 시 사용했던 Terraform 스크립트
Proxmox 환경 IaC 코드 (OpenTofu + `telmate/proxmox` provider)

Proxmox API 인증은 **API Token** 방식을 사용합니다. (root 비밀번호 로그인 사용 안 함)

## 1. API Token 생성

Proxmox 노드의 root 쉘에서 진행합니다. 먼저 버전을 확인하세요.

```bash
pveversion
```

### 1-1. Role 생성 (최소 권한)

PVE 9에서는 `VM.Monitor` 권한이 없어지고 `VM.GuestAgent.*`로 나뉘었기 때문에, 버전에 맞는 명령을 실행합니다.

```bash
# PVE 9.x
pveum role add TofuProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use VM.GuestAgent.Audit"

# PVE 8.x
pveum role add TofuProv -privs "Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
```

### 1-2. 전용 사용자 + 토큰 생성

```bash
pveum user add tofu@pve --comment "OpenTofu automation"
pveum aclmod / -user tofu@pve -role TofuProv

# --privsep 0 : 토큰이 사용자(tofu@pve)의 권한을 그대로 상속
pveum user token add tofu@pve tofu-token --privsep 0
```

출력되는 `full-tokenid`(`tofu@pve!tofu-token`)와 `value`(secret)를 저장합니다.
**secret은 생성 시 한 번만 표시됩니다.**

> 토큰 권한을 사용자보다 좁히려면 `--privsep 1`로 생성한 뒤 토큰에 별도 ACL을 부여합니다.
> `pveum aclmod / -token 'tofu@pve!tofu-token' -role TofuProv`

### 1-3. 토큰 교체 / 폐기

```bash
pveum user token list tofu@pve
pveum user token remove tofu@pve tofu-token     # 폐기
pveum user token add tofu@pve tofu-token-2 --privsep 0   # 새로 발급 → tfvars 갱신
```

## 2. Cloud Template 생성

Template은 Proxmox 노드에서 진행합니다.

```bash
qm create 5000 --memory 2048 --core 2 --name ubuntu-24.04 --net0 virtio,bridge=vmbr0
cd /var/lib/vz/template/iso/
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
qm importdisk 5000 noble-server-cloudimg-amd64.img local
qm set 5000 --scsihw virtio-scsi-pci --scsi0 local:5000/vm-5000-disk-0.raw
qm set 5000 --ide2 local:cloudinit
qm set 5000 --boot c --bootdisk scsi0
qm template 5000
```

## 3. Variables

예시 파일을 복사해서 값을 채웁니다. `terraform.tfvars`는 `.gitignore` 대상이라 커밋되지 않습니다.

```bash
cp terraform.tfvars.example terraform.tfvars
```

```hcl
proxmox_api_url          = "https://192.168.0.13:8006/api2/json"
proxmox_api_token_id     = "tofu@pve!tofu-token"
proxmox_api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
default_user             = "kubeadm"   # k8s용이라 kubeadm 계정 추가
vm_password              = "..."       # VM(Cloud-Init) 계정 비밀번호, Proxmox 비밀번호와 분리
ssh_public_key           = "ssh-ed25519 AAAA..."
```

secret을 파일에 두지 않으려면 환경변수를 사용할 수 있습니다.

```bash
export TF_VAR_proxmox_api_token_secret='xxxxxxxx-...'
export TF_VAR_vm_password='...'
```

## 4. 실행 방법

```bash
git clone https://github.com/yeonjukim164/proxmox.git
cd proxmox
tofu init
tofu plan
tofu apply
```
