# Kubernetes 노드: template 스택의 템플릿(VMID 5000)을 full clone
#
# 크기 기준: 호스트 14 코어 / 28 스레드 / RAM 62 GiB (2026-11-21 `free -h` 확인, 처음 크기를 정할 때는 31.2 GiB) / 디스크 여유 ~860 GiB
# 원칙: 호스트 자원을 최대한 worker 에 배정 (master 는 필요한 최소)
#  - CPU: worker 마다 12 vCPU, master 4 vCPU (합계 40, 호스트 28 스레드의 1.4배).
#    2026-11-28 까지는 worker 마다 28 스레드(합계 92, 3.3배)를 줬으나, 여러 VM 이 함께 바쁠 때 VM 안의 steal 이 17~20% 였다.
#    CPU 추론은 물리 코어(14)를 넘겨도 빨라지지 않고, 답을 쓰는 속도는 메모리 대역폭에 묶인다
#  - RAM: 초과 할당하면 VM 들이 메모리를 다 쓸 때 호스트가 VM(=노드)을 강제 종료 → 호스트 RAM 한도까지만.
#    호스트 자체(~1.9 GiB 실측) + QEMU 오버헤드용 ~2.3 GiB 를 남긴다. 합계 60 GiB (master 6 + worker 18 × 3), 호스트 몫 ~2.7 GiB
#    worker 는 2026-11-28 에 7.625 GiB → 18 GiB. 7.625 GiB 로는 Ollama 에 답하는 모델(llama3.2)과 심판 모델(llama3.1:8b)을 함께 올리지 못했다
#  - master: 4 vCPU, 6 GiB. 컨트롤 플레인만 돌리고 작업은 모두 worker 에서 돌린다(control-plane NoSchedule 테인트).
#    2026-11-28 실측: 사용 3.4 GiB, CPU 0.46 코어(Argo CD 와 Kubeflow 대부분을 내린 상태).
#    2026-11-21 에 4 vCPU / 6 GiB 로 버티지 못해 8 vCPU / 12 GiB 로 키웠으나, 그때는 호스트 메모리가 ECC 오류로 느렸던 때다:
#    kube-apiserver RSS 2.8 GiB, CPU 평균 93%, kubelet 프로브 실패 20분에 115회, scheduler·controller-manager 재시작 23회.
#    (이전 기록: 3 GiB 에서 여유 296 MiB, CPU 136% → 6 GiB)
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
    "k8s-master" = {
      vm_id  = 100
      ip     = "192.168.0.31"
      cores  = 4
      memory = 6144 # MiB, 6 GiB
      disk   = 40   # GB
    }
    "k8s-worker-1" = {
      vm_id  = 101
      ip     = "192.168.0.32"
      cores  = 12
      memory = 18432 # MiB, 18 GiB
      disk   = 240   # GB
    }
    "k8s-worker-2" = {
      vm_id  = 102
      ip     = "192.168.0.33"
      cores  = 12
      memory = 18432 # MiB, 18 GiB
      disk   = 240   # GB
    }
    "k8s-worker-3" = {
      vm_id  = 103
      ip     = "192.168.0.34"
      cores  = 12
      memory = 18432 # MiB, 18 GiB
      disk   = 240   # GB
    }
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
