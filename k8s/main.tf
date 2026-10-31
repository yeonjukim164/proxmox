# Kubernetes 노드: template 스택의 템플릿(VMID 5000)을 full clone
#
# 크기 기준: 호스트 28 스레드 / RAM 31.2 GiB / 디스크 여유 ~860 GiB (2026-10-31 확인)
#  - master: 2 vCPU, 3 GiB. 2 GiB 는 flannel 에서도 여유 445 MiB 뿐이라, Cilium(노드마다 agent/envoy)과
#    KFP(Argo CRD 로 apiserver 메모리 증가)를 올리면 OOM 위험 → Cilium 기준 최소로 3 GiB. 나머지는 worker 3대에 몰아줌
#  - RAM 합계 27.75 GiB: k8s 는 swap/balloon 을 쓰지 않아 초과 할당하면 OOM → 호스트용 ~3.45 GiB 만 남김
#  - vCPU 합계 26 / 28 스레드, 디스크 합계 760G (호스트·이미지·백업용 ~100G 남김)
locals {
  node_name      = "pve"
  datastore_id   = "local"
  template_vm_id = 5000
  gateway        = "192.168.0.1"
  username       = "kubeadm"
  # 공개키라 저장소에 둬도 됨 (주석의 이메일은 제거)
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHLPvzdqa08aNVIcXJCp3Y5JWr0pfyGiKMoc9pp+cqRS"]

  nodes = {
    "k8s-master"   = { vm_id = 100, ip = "192.168.0.31", cores = 2, memory = 3072, disk = 40 }
    "k8s-worker-1" = { vm_id = 101, ip = "192.168.0.32", cores = 8, memory = 8448, disk = 240 }
    "k8s-worker-2" = { vm_id = 102, ip = "192.168.0.33", cores = 8, memory = 8448, disk = 240 }
    "k8s-worker-3" = { vm_id = 103, ip = "192.168.0.34", cores = 8, memory = 8448, disk = 240 }
  }
}

# plan 단계에서 API 접속과 템플릿 존재를 확인 (template 스택이 먼저 apply 되어 있어야 함)
data "proxmox_vm" "template" {
  node_name = local.node_name
  id        = local.template_vm_id
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  node_name = local.node_name
  vm_id     = each.value.vm_id
  name      = each.key
  tags      = ["k8s", "tofu"]
  on_boot   = true

  clone {
    vm_id = data.proxmox_vm.template.id
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "scsi0"
    size         = each.value.disk
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id        = local.datastore_id
    vendor_data_file_id = "${local.datastore_id}:snippets/ubuntu-vendor-data.yaml"

    dns {
      servers = [local.gateway]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = local.gateway
      }
    }

    user_account {
      username = local.username
      keys     = local.ssh_public_keys
    }
  }
}
