resource "proxmox_vm_qemu" "k8s_master" {
  name          = "k8s-master"
  target_node   = var.proxmox_node_name
  vmid          = 100
  clone         = var.vm_template_name
  os_type       = "cloud-init"
  memory        = 8192
  
  cores   = 4
  sockets = 1
  onboot = true
  full_clone = true
  scsihw        = "virtio-scsi-pci"

  disks {
    # 1. 기존 OS 디스크 설정 (scsi0)
    scsi {
      scsi0 {
        disk {
          size    = "80G"
          storage = var.vm_storage_pool
        }
      }
    }
    # 2. 누락된 Cloud-Init 드라이브 수동 추가 (ide2)
    ide {
      ide2 {
        cloudinit {
          storage = var.vm_storage_pool
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = var.vm_bridge
  }

  ipconfig0     = "ip=192.168.0.31/24,gw=192.168.0.1"
  ciuser        = var.default_user
  ciupgrade = true
  cipassword    = var.vm_password
  sshkeys       = var.ssh_public_key
}

resource "proxmox_vm_qemu" "k8s_workers" {
  count         = 3
  name          = "k8s-worker-${count.index + 1}"
  target_node   = var.proxmox_node_name
  vmid          = 101 + count.index
  clone         = var.vm_template_name
  os_type       = "cloud-init"
  memory        = 18432
  cores   = 8
  sockets = 1
  onboot = true
  full_clone = true
  scsihw        = "virtio-scsi-pci"

  # --- 올바르게 수정된 disks 블록 ---
  disks {
    # 1. 기존 OS 디스크 설정 (scsi0)
    scsi {
      scsi0 {
        disk {
          size    = "260G"
          storage = var.vm_storage_pool
        }
      }
    }
    # 2. 누락된 Cloud-Init 드라이브 수동 추가 (ide2)
    ide {
      ide2 {
        cloudinit {
          storage = var.vm_storage_pool
        }
      }
    }
  }

  network {
    model  = "virtio"
    bridge = var.vm_bridge
  }

  ipconfig0     = "ip=192.168.0.${32 + count.index}/24,gw=192.168.0.1"
  ciuser        = var.default_user
  ciupgrade = true
  cipassword    = var.vm_password
  sshkeys       = var.ssh_public_key
}