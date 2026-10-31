# 1) Ubuntu 클라우드 이미지: Proxmox 노드가 URL 에서 직접 다운로드하고 SHA256 검증
#    (content_type = "import" → import_from 으로 디스크에 가져올 수 있는 형태)
resource "proxmox_download_file" "ubuntu_cloud_image" {
  node_name          = var.node_name
  datastore_id       = var.datastore_id
  content_type       = "import"
  url                = var.ubuntu_image.url
  file_name          = var.ubuntu_image.file_name
  checksum           = var.ubuntu_image.sha256
  checksum_algorithm = "sha256"
}

# 2) 템플릿 VM
#    cloud-init vendor-data(snippets/ubuntu-vendor-data.yaml)로 clone 된 VM 의 첫 부팅 시 qemu-guest-agent 설치.
#    vendor-data 는 Proxmox 가 생성하는 user-data(계정, SSH 키, 비밀번호)와 함께 적용됩니다.
#    계정/SSH 키/IP 는 템플릿에 넣지 않고, clone 하는 VM 스택에서 VM 마다 지정합니다.
resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  node_name   = var.node_name
  vm_id       = var.template_vm_id
  name        = var.template_name
  description = "Ubuntu 26.04 LTS cloud image template - managed by OpenTofu (template/)"
  tags        = ["template", "tofu", "ubuntu"]

  template = true
  started  = false

  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  # vendor-data 로 guest agent 가 설치되므로 활성화
  agent {
    enabled = true
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    import_from  = proxmox_download_file.ubuntu_cloud_image.id
    iothread     = true
    discard      = "on"
    size         = 10
  }

  initialization {
    datastore_id        = var.datastore_id
    vendor_data_file_id = var.vendor_data_file_id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_device {
    bridge = var.bridge
  }

  operating_system {
    type = "l26"
  }

  # Ubuntu 클라우드 이미지 권장: 시리얼 콘솔
  serial_device {}

  vga {
    type = "serial0"
  }
}
