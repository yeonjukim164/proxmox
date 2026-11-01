# Kubernetes 노드: template 스택의 템플릿(VMID 5000)을 full clone
#
# 크기 기준: 호스트 14 코어 / 28 스레드 / RAM 31.2 GiB / 디스크 여유 ~860 GiB (2026-10-31 확인)
# 원칙: 호스트 자원을 최대한 worker 에 배정 (master 는 필요한 최소)
#  - CPU: 시간을 나눠 쓰므로 초과 할당해도 느려질 뿐 죽지 않음 → worker 마다 호스트 전체 28 스레드
#  - RAM: 초과 할당하면 VM 들이 메모리를 다 쓸 때 호스트가 VM(=노드)을 강제 종료 → 호스트 RAM 한도까지만.
#    호스트 자체(~1.9 GiB 실측) + QEMU 오버헤드용 ~2.3 GiB 만 남기고 전부 배정 (합계 28.9 GiB)
#  - master: 4 vCPU, 6 GiB. Kubeflow 26.03 + Argo CD 를 올리면 CRD 가 많아져 kube-apiserver 만 1.2 GiB+
#    (3 GiB 에서 여유 296 MiB, CPU 136% 실측) → Kubeflow 컨트롤 플레인 기준 최소로 6 GiB. vCPU 는 초과 할당이라 worker 몫이 줄지 않음
#  - 디스크 합계 760G (호스트·이미지·백업용 ~100G 남김)
locals {
  node_name      = "pve"
  datastore_id   = "local"
  template_vm_id = 5000
  gateway        = "192.168.0.1"
  username       = "kubeadm"
  # 공개키라 저장소에 둬도 됨 (주석의 이메일은 제거)
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHLPvzdqa08aNVIcXJCp3Y5JWr0pfyGiKMoc9pp+cqRS"]

  nodes = {
    "k8s-master"   = { vm_id = 100, ip = "192.168.0.31", cores = 4, memory = 6144, disk = 40 }
    "k8s-worker-1" = { vm_id = 101, ip = "192.168.0.32", cores = 28, memory = 7808, disk = 240 }
    "k8s-worker-2" = { vm_id = 102, ip = "192.168.0.33", cores = 28, memory = 7808, disk = 240 }
    "k8s-worker-3" = { vm_id = 103, ip = "192.168.0.34", cores = 28, memory = 7808, disk = 240 }
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

    # domain 을 비우면 Proxmox 호스트의 검색 도메인(silvervillage.com, 와일드카드 DNS)이 상속되어
    # 파드(ndots:5)의 외부 이름 조회가 엉뚱한 IP 로 풀림 → 홈 네트워크 예약 도메인(RFC 8375)으로 고정
    dns {
      domain  = "home.arpa"
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
