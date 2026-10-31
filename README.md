# Proxmox HomeLab IaC

OpenTofu + [`bpg/proxmox`](https://github.com/bpg/terraform-provider-proxmox) provider로 Proxmox VE 9 홈랩을 관리합니다.
변경 사항은 GitHub Actions(GitHub 제공 무료 runner)에서 `plan` / `apply` 되고, state 는 암호화되어 이 저장소에 커밋됩니다.

```
.
├── .github/workflows/tofu.yml   # PR: plan  /  main merge: apply + state 커밋  /  수동 실행
├── template/                    # Ubuntu 26.04 LTS 클라우드 이미지 템플릿 (VMID 5000)
└── state/                       # 암호화된 tofu state (CI 가 관리, 직접 수정 금지)
```

```
브랜치 작업 → PR ──▶ [GitHub runner] fmt / validate / plan ──▶ Job Summary 에서 plan 확인
                                                                │
                main merge ──▶ [GitHub runner] plan → apply → state/ 암호화 커밋 (github-actions[bot])

GitHub runner ──(인터넷)──▶ 공유기 포트포워딩 ──▶ Proxmox (API 8006 / SSH 22)
```

| 항목 | 값 |
|---|---|
| Proxmox VE | 9.2 (`pve`, 내부 192.168.0.13) |
| 인증 | API Token (`tofu@pve!tofu-token`) + SSH 키 (snippet 업로드 전용) |
| state | `state/<stack>.state.json` (OpenTofu state 암호화, AES-GCM + PBKDF2) |

---

## 1. Proxmox 준비 (최초 1회, 노드 root 쉘)

### 1-1. API Token 생성

```bash
# (1) Role: OpenTofu 가 사용하는 최소 권한 (PVE 9 기준)
pveum role add TofuProv -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit SDN.Audit SDN.Use Sys.Audit Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.GuestAgent.Audit VM.PowerMgmt"

# (2) 전용 사용자 + 권한 부여
pveum user add tofu@pve --comment "OpenTofu automation"
pveum aclmod / -user tofu@pve -role TofuProv

# (3) 토큰 발급 (--privsep 0: 사용자 권한을 그대로 상속)
pveum user token add tofu@pve tofu-token --privsep 0
```

출력되는 `full-tokenid` 와 `value` 를 `=` 로 이어 붙인 값이 provider 에 넣을 토큰입니다.
**`value`(secret)는 이때 한 번만 표시됩니다.**

```
tofu@pve!tofu-token=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

| 권한 | 용도 |
|---|---|
| `Sys.Audit`, `Sys.Modify`, `Datastore.AllocateTemplate` | 클라우드 이미지 URL 다운로드 |
| `Datastore.Allocate*`, `Datastore.Audit` | 디스크 생성/import, 이미지 삭제 |
| `VM.*` | VM/템플릿 생성·설정·전원 관리, guest agent 조회 |
| `SDN.Audit`, `SDN.Use` | 브리지(vmbr0) 조회/사용 |

토큰 교체 / 폐기:

```bash
pveum user token list tofu@pve
pveum user token remove tofu@pve tofu-token
pveum user token add tofu@pve tofu-token --privsep 0     # 재발급 → GitHub Secret 갱신
```

### 1-2. SSH 키 등록 (snippet 업로드 전용)

Proxmox API 는 snippet(cloud-init 설정 파일) 업로드를 지원하지 않아서, 이 작업에만 SSH 를 사용합니다.

```bash
# 작업 PC: CI 전용 키 생성 (이미 있으면 생략)
ssh-keygen -t ed25519 -N "" -C "tofu-ci@proxmox" -f ~/.ssh/proxmox_tofu_ed25519
cat ~/.ssh/proxmox_tofu_ed25519.pub
```

```bash
# Proxmox 노드: 위 공개키를 root 의 authorized_keys 에 추가
echo 'ssh-ed25519 AAAA... tofu-ci@proxmox' >> /root/.ssh/authorized_keys
```

```bash
# 작업 PC: 접속 확인
ssh -i ~/.ssh/proxmox_tofu_ed25519 root@192.168.0.13 pveversion
```

### 1-3. 스토리지 콘텐츠 허용

`local` 스토리지에 `import`(이미지 가져오기)와 `snippets` 가 허용되어 있어야 합니다.

```bash
pvesm set local --content images,rootdir,vztmpl,backup,iso,snippets,import
```

---

## 2. 외부 접속 (공유기 포트포워딩)

GitHub 제공 runner 는 인터넷에서 실행되므로, 공유기에서 Proxmox 로 포트포워딩합니다.
가정용 회선은 IP 가 바뀔 수 있으니 공유기의 **DDNS** 호스트명(예: `myhome.iptime.org`)을 사용하세요.

| 외부 포트 (예시) | 내부 대상 | 용도 |
|---|---|---|
| `58006/TCP` | `192.168.0.13:8006` | Proxmox API |
| `58022/TCP` | `192.168.0.13:22` | SSH (snippet 업로드) |

> GitHub runner 의 IP 는 매번 바뀌는 대규모 대역이라 IP 허용 목록으로 막기 어렵습니다.
> **Proxmox API 와 root SSH 가 인터넷에 열리므로 아래 보안 설정을 반드시 적용하세요.**

### 보안 체크리스트

1. **외부 포트는 기본값(8006/22)이 아닌 번호 사용** (위 표 예시)
2. **SSH 는 키 로그인만 허용** (비밀번호 로그인 차단)
   ```bash
   printf '%s\n' 'PermitRootLogin prohibit-password' 'PasswordAuthentication no' 'KbdInteractiveAuthentication no' > /etc/ssh/sshd_config.d/10-hardening.conf
   sshd -t && systemctl reload ssh
   ```
   적용 전에 본인 PC 의 키도 `authorized_keys` 에 있는지 확인하세요. (웹 UI 콘솔은 계속 사용 가능)
3. **웹 UI 로그인(root@pam)에 2단계 인증(TOTP) 적용**: Datacenter → Permissions → Two Factor → Add → TOTP
   (API Token 은 2단계 인증의 영향을 받지 않습니다)
4. **정식 TLS 인증서 적용 (권장)**: 현재는 자체 서명 인증서라 `proxmox_insecure = true` 입니다.
   인터넷 구간에서는 중간자 공격으로 토큰이 노출될 수 있으므로, Datacenter → ACME 로 DDNS 도메인에
   Let's Encrypt 인증서를 발급한 뒤 `template/variables.tf` 의 `proxmox_insecure` 기본값을 `false` 로 바꾸세요.

---

## 3. GitHub Secrets

| Secret | 예시 | 설명 |
|---|---|---|
| `PROXMOX_ENDPOINT` | `https://myhome.iptime.org:58006/` | 외부에서 접근하는 API 주소 |
| `PROXMOX_SSH_HOST` | `myhome.iptime.org` | SSH 호스트 (DDNS) |
| `PROXMOX_SSH_PORT` | `58022` | 포트포워딩된 SSH 포트 |
| `PROXMOX_API_TOKEN` | `tofu@pve!tofu-token=xxxxxxxx-...` | 1-1 에서 만든 토큰 |
| `PROXMOX_SSH_PRIVATE_KEY` | (개인키 파일 내용) | 1-2 에서 만든 `~/.ssh/proxmox_tofu_ed25519` |
| `TF_STATE_PASSPHRASE` | (임의의 긴 문자열) | state 암호화 비밀번호 (16자 이상) |

```bash
R=yeonjukim164/proxmox
gh secret set PROXMOX_ENDPOINT -R $R --body 'https://<DDNS>:58006/'
gh secret set PROXMOX_SSH_HOST -R $R --body '<DDNS>'
gh secret set PROXMOX_SSH_PORT -R $R --body '58022'
gh secret set PROXMOX_API_TOKEN -R $R                 # 프롬프트에 토큰 붙여넣기
gh secret set PROXMOX_SSH_PRIVATE_KEY -R $R < ~/.ssh/proxmox_tofu_ed25519

# state 암호화 비밀번호: 생성 후 비밀번호 관리자 등에 반드시 따로 보관
PASS="$(openssl rand -base64 32)"; echo "$PASS"
gh secret set TF_STATE_PASSPHRASE -R $R --body "$PASS"; unset PASS
```

> ⚠️ **`TF_STATE_PASSPHRASE` 를 잃어버리면 state 를 복구할 수 없습니다.**
> GitHub Secret 은 다시 읽을 수 없으므로, 생성할 때 출력된 값을 별도로 보관하세요.

---

## 4. 사용 방법

| 동작 | 방법 |
|---|---|
| 변경 계획 확인 | 브랜치에서 수정 → `main` 으로 PR → Actions 실행 결과의 **Summary** 에서 plan 확인 |
| 적용 | PR 을 `main` 에 merge → 자동 `apply` → `state/` 가 `github-actions[bot]` 커밋으로 갱신 |
| 수동 실행 | Actions → `tofu` → **Run workflow** (`main` 선택) → `apply` 체크 |

- 실행은 하나씩 순서대로 처리됩니다 (`concurrency: tofu-state`).
- 항상 main 의 최신 state 를 받아서 plan 합니다.
- `main` 에 "PR 필수" 같은 브랜치 보호 규칙을 걸면 bot 의 state 커밋이 막히니, 걸 경우 GitHub Actions 를 예외로 허용하세요.

### 템플릿 이미지 갱신

`template/variables.tf` 의 `ubuntu_image` 를 새 릴리스로 바꿔 PR 을 올리면, merge 시 이미지 다운로드와 템플릿 교체가 진행됩니다.

```bash
# 최신 릴리스 디렉터리와 SHA256 확인
curl -s https://cloud-images.ubuntu.com/releases/resolute/ | grep -oE 'release-[0-9]{8}' | sort -u | tail -1
curl -s https://cloud-images.ubuntu.com/releases/resolute/release-YYYYMMDD/SHA256SUMS | grep 'server-cloudimg-amd64.img$'
```

### 템플릿 구성

- 디스크: Ubuntu 26.04 클라우드 이미지 (10GB, clone 시 확장), `virtio-scsi-single` + iothread
- cloud-init: vendor-data snippet 으로 첫 부팅 시 `qemu-guest-agent` 설치
- 계정 / SSH 키 / IP 는 템플릿에 넣지 않고, clone 하는 VM 스택에서 VM 마다 지정

---

## 5. 로컬 실행 (내부망, 확인용)

```bash
git pull                     # 최신 state 받기
cd template
export TF_VAR_proxmox_api_token='tofu@pve!tofu-token=...'
export TF_VAR_proxmox_ssh_private_key="$(cat ~/.ssh/proxmox_tofu_ed25519)"
export TF_VAR_state_passphrase='...'
tofu init
tofu plan
```

> **`apply` 는 CI 에서만 하세요.** 로컬에서 apply 하면 state 가 로컬 파일에만 바뀌어 저장소와 어긋납니다.
