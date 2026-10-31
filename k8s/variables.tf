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

variable "state_passphrase" {
  description = "state/plan 암호화 비밀번호 (16자 이상). 분실 시 state 복구 불가"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 16
    error_message = "state_passphrase 는 16자 이상이어야 합니다."
  }
}
