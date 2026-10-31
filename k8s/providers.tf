# 인증: Proxmox API Token (SSH 는 사용하지 않음)
# CI 에서는 공유기 포트포워딩된 외부 주소(DDNS:18006)를 Secret 으로 주입합니다.
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}
