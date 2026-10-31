output "template_vm_id" {
  description = "VM 스택에서 clone 할 템플릿 VM ID"
  value       = proxmox_virtual_environment_vm.ubuntu_template.vm_id
}

output "template_name" {
  description = "템플릿 이름"
  value       = proxmox_virtual_environment_vm.ubuntu_template.name
}

output "vendor_data_file_id" {
  description = "qemu-guest-agent 설치용 vendor-data snippet ID (VM 스택의 initialization.vendor_data_file_id 에 사용)"
  value       = data.proxmox_file.vendor_data.id
}

output "image_file_id" {
  description = "다운로드된 클라우드 이미지 파일 ID"
  value       = proxmox_download_file.ubuntu_cloud_image.id
}
