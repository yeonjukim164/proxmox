# Admin LB 

# Control Plane Nodes
resource "proxmox_vm_qemu" "k8s_control_plane" {
  count       = 3
  name        = "k8s-node${count.index + 1}" 
  target_node = var.proxmox_node_name
  vmid        = 101 + count.index
  clone       = var.vm_template_name
  os_type     = "cloud-init"

  cores   = 4
  sockets = 1
  memory  = 2048

  onboot     = true
  full_clone = true
  scsihw     = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          size    = "80G" 
          storage = var.vm_storage_pool
        }
      }
    }
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

  # IP: 192.168.0.21 ~ 23
  ipconfig0 = "ip=192.168.0.${21 + count.index}/24,gw=192.168.0.1"

  ciuser     = var.default_user
  ciupgrade  = true
  sshkeys    = var.ssh_public_key

  provisioner "file" {
    source      = "${path.module}/init-cfg.sh"
    destination = "/tmp/init-cfg.sh"    
    connection {
      type        = "ssh"
      user        = var.default_user
      private_key = file(var.ssh_private_key_path)
      host        = "192.168.0.${21 + count.index}"
      timeout     = "10m"
    }
  }   
provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = var.default_user
      private_key = file(var.ssh_private_key_path)
      host        = "192.168.0.${21 + count.index}"
      timeout     = "10m"
    }
    inline = [
      "chmod +x /tmp/init-cfg.sh",
      # init-cfg.sh도 전체 노드 수(5)를 인자로 받아 hosts 파일을 구성함
      "sudo bash /tmp/init-cfg.sh 5"
    ]
  }

}

#  Worker Nodes
resource "proxmox_vm_qemu" "k8s_worker" {
  count       = 2
  name        = "k8s-node${count.index + 4}"
  target_node = var.proxmox_node_name
  vmid        = 104 + count.index
  clone       = var.vm_template_name
  os_type     = "cloud-init"

  cores   = 4
  sockets = 1
  memory  = 4096

  onboot     = true
  full_clone = true
  scsihw     = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          size    = "80G"
          storage = var.vm_storage_pool
        }
      }
    }
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

  # IP: 192.168.0.24 ~ 25
  ipconfig0 = "ip=192.168.0.${24 + count.index}/24,gw=192.168.0.1"

  ciuser     = var.default_user
  ciupgrade  = true
  sshkeys    = var.ssh_public_key

  provisioner "file" {
    source      = "${path.module}/init-cfg.sh"
    destination = "/tmp/init-cfg.sh"    
    connection {
      type        = "ssh"
      user        = var.default_user
      private_key = file(var.ssh_private_key_path)
      host        = "192.168.0.${24+ count.index}"
      timeout     = "10m"
    }
  }  

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = var.default_user
      private_key = file(var.ssh_private_key_path)
      host        = "192.168.0.${24 + count.index}"
      timeout     = "10m"
    }
    inline = [
      "chmod +x /tmp/init-cfg.sh",
      # $1 인자로 '5' (총 노드 수) 전달
      "sudo bash /tmp/init-cfg.sh 5"
    ]  
  }    
}


resource "proxmox_vm_qemu" "admin_lb" {
  name        = "admin-lb"
  target_node = var.proxmox_node_name
  vmid        = 100
  clone       = var.vm_template_name
  os_type     = "cloud-init"
  
  cores   = 4
  sockets = 1
  memory  = 4048
  
  onboot     = true
  full_clone = true
  scsihw     = "virtio-scsi-pci"

  disks {
    scsi {
      scsi0 {
        disk {
          size    = "30G"
          storage = var.vm_storage_pool
        }
      }
    }
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

  ipconfig0 = "ip=192.168.0.20/24,gw=192.168.0.1"
  
  ciuser     = var.default_user
  ciupgrade  = true
  sshkeys    = var.ssh_public_key

  provisioner "file" {
    source      = "${path.module}/admin-lb.sh"
    destination = "/tmp/admin-lb.sh"    
    # SSH 접속 정보
    connection {
      type        = "ssh"
      user        = var.default_user
      private_key = file(var.ssh_private_key_path)
      host        = "192.168.0.20" # VM의 IP
      timeout     = "10m"
    }
  }  

  provisioner "remote-exec" {
    # SSH 접속 정보
    connection {
      type        = "ssh"
      user        = var.default_user
      private_key = file(var.ssh_private_key_path)
      host        = "192.168.0.20" # VM의 IP
      timeout     = "10m"
    }

    # 실행할 스크립트 내용
    inline = [
      "chmod +x /tmp/admin-lb.sh",
      # sudo -E: 환경변수 유지 (필요시)
      # bash -c: 스크립트 실행
      "sudo bash /tmp/admin-lb.sh 5" 
    ]
  }  
}

