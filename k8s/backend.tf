# state 는 OpenTofu 기본 기능으로 암호화(AES-GCM)해서 저장소의 state/ 디렉터리에 커밋합니다.
#  - CI(GitHub Actions) 가 apply 후 state 파일을 main 브랜치에 커밋
#  - 비밀번호(state_passphrase)가 없거나 틀리면 state 를 읽을 수 없음 → 분실 시 복구 불가, 별도 보관 필수
terraform {
  backend "local" {
    path = "../state/k8s.state.json"
  }

  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }

    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }

    state {
      method   = method.aes_gcm.main
      enforced = true
    }

    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}
