variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://proxmox.example.com:8006/api2/json)"
  type        = string
  default     = "https://192.168.0.13:8006/api2/json"
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID, '<user>@<realm>!<token-name>' 형식 (e.g., tofu@pve!tofu-token)"
  type        = string

  validation {
    condition     = can(regex("^[^@!]+@[^@!]+![^@!]+$", var.proxmox_api_token_id))
    error_message = "proxmox_api_token_id는 '<user>@<realm>!<token-name>' 형식이어야 합니다. (e.g., tofu@pve!tofu-token)"
  }
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token secret (토큰 생성 시 한 번만 표시되는 UUID)"
  type        = string
  sensitive   = true
}

variable "proxmox_node_name" {
  description = "The Proxmox node to deploy VMs on"
  type        = string
  default     = "pve"
}

variable "vm_template_name" {
  description = "The name of the VM template in Proxmox"
  type        = string
  default     = "ubuntu-24.04"
}

variable "vm_bridge" {
  description = "The network bridge for the VMs"
  type        = string
  default     = "vmbr0"
}

variable "vm_storage_pool" {
  description = "The storage pool for VM disks"
  type        = string
  default     = "local"
}

variable "ssh_public_key" {
  description = "SSH public key to inject into VMs via Cloud-Init"
  type        = string
}

variable "default_user" {
  description = "Default user for Cloud-Init"
  type        = string
  default     = "kubeadm"
}

variable "vm_password" {
  description = "Cloud-Init password for default_user (Proxmox 계정 비밀번호와 분리)"
  type        = string
  sensitive   = true
}
