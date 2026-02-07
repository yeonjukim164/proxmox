variable "proxmox_api_url" {
  description = "https://proxmox.example.com:8006/api2/json"
  type        = string
  default     = "https://192.168.0.13:8006/api2/json"  
}

variable "proxmox_user" {
  description = "Proxmox API username (e.g., root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox API password"
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

variable "ssh_private_key_path" {
  description = "Path to the private SSH key for VM connection"
  type        = string
  default     = "~/.ssh/id_rsa" # 본인의 로컬 개인키 경로
}
