# ---------------------------------------------------------------------------
# 접속 정보
#  - 기본값은 내부망(로컬 실행) 기준
#  - CI 에서는 Secrets → TF_VAR_* 환경변수로 외부 주소(DDNS + 포트포워딩 포트)를 주입
# ---------------------------------------------------------------------------
variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (e.g., https://<ddns-host>:<port>/)"
  type        = string
  default     = "https://192.168.0.13:8006/"
}

variable "proxmox_insecure" {
  description = "자체 서명 인증서 허용 여부 (ACME 등 정식 인증서 적용 후 false 권장)"
  type        = bool
  default     = true
}

variable "proxmox_api_token" {
  description = "Proxmox API Token: '<user>@<realm>!<token-name>=<secret>' (e.g., tofu@pve!tofu-token=xxxxxxxx-...)"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@!=]+@[^@!=]+![^@!=]+=.+$", var.proxmox_api_token))
    error_message = "proxmox_api_token 은 '<user>@<realm>!<token-name>=<secret>' 형식이어야 합니다."
  }
}

variable "proxmox_ssh_private_key" {
  description = "Proxmox 노드 root SSH 개인키 (snippet 업로드용)"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_address" {
  description = "Proxmox 노드 SSH 주소 (CI: DDNS 호스트명)"
  type        = string
  default     = "192.168.0.13"
}

variable "proxmox_ssh_port" {
  description = "Proxmox 노드 SSH 포트 (CI: 포트포워딩된 외부 포트)"
  type        = number
  default     = 22
}

variable "state_passphrase" {
  description = "state/plan 암호화 비밀번호 (16자 이상). 분실 시 state 복구 불가"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase 는 16자 이상이어야 합니다."
  }
}

# ---------------------------------------------------------------------------
# 템플릿 설정
# ---------------------------------------------------------------------------
variable "node_name" {
  description = "Proxmox 노드 이름"
  type        = string
  default     = "pve"
}

variable "datastore_id" {
  description = "이미지/디스크/snippet 을 저장할 스토리지 (import, images, snippets 콘텐츠가 허용되어 있어야 함)"
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "네트워크 브리지"
  type        = string
  default     = "vmbr0"
}

variable "template_vm_id" {
  description = "템플릿 VM ID"
  type        = number
  default     = 5000
}

variable "template_name" {
  description = "템플릿 이름 (VM 스택에서 clone 대상으로 사용)"
  type        = string
  default     = "ubuntu-26.04"
}

variable "ubuntu_image" {
  description = "Ubuntu 클라우드 이미지 (재현성을 위해 날짜가 고정된 release 경로 + SHA256 사용)"
  type = object({
    url       = string
    sha256    = string
    file_name = string
  })
  default = {
    url       = "https://cloud-images.ubuntu.com/releases/resolute/release-20261016/ubuntu-26.04-server-cloudimg-amd64.img"
    sha256    = "5645d0318ad21f643ebb1ac4567514620e9893380b07b0201fda163baa5b7eb5"
    file_name = "ubuntu-26.04-server-cloudimg-amd64-20261016.qcow2"
  }

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.ubuntu_image.sha256))
    error_message = "ubuntu_image.sha256 은 64자리 소문자 hex 여야 합니다."
  }

  validation {
    condition     = endswith(var.ubuntu_image.file_name, ".qcow2")
    error_message = "ubuntu_image.file_name 은 .qcow2 로 끝나야 합니다 (Ubuntu .img 의 실제 포맷이 qcow2)."
  }
}
