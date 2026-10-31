# 인증: Proxmox API Token
# SSH: snippet(cloud-init vendor-data) 업로드에만 사용 (Proxmox API 가 snippet 업로드를 지원하지 않음)
# CI 에서는 공유기 포트포워딩된 외부 주소(DDNS)/포트를 Secrets 로 주입합니다.
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure

  ssh {
    username    = "root"
    private_key = var.proxmox_ssh_private_key

    node {
      name    = var.node_name
      address = var.proxmox_ssh_address
      port    = var.proxmox_ssh_port
    }
  }
}
