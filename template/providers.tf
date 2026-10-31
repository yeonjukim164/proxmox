# 인증: Proxmox API Token (SSH 는 사용하지 않음)
#  - 이미지 다운로드(download-url), 디스크 import(import_from), VM 생성은 모두 API 로 처리
#  - cloud-init snippet 은 API 로 업로드할 수 없어서 저장소의 snippets/ 를 노드에 수동 업로드 (README 참고)
# CI 에서는 공유기 포트포워딩된 외부 주소(DDNS:18006)를 Secret 으로 주입합니다.
provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}
