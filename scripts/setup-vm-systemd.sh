#!/bin/bash
# =============================================================================
# VM 내부 systemd 서비스 설치 스크립트
# =============================================================================
# 각 VM에 SSH로 접속 후 실행. openclaw 프로세스를 systemd로 관리하여
# 프로세스가 죽으면 자동으로 5초 내 재시작.
#
# 사용법: bash scripts/setup-vm-systemd.sh <vm-name> <zone>
# 예: bash scripts/setup-vm-systemd.sh ralphton-watcher asia-northeast3-a
#
# 전체 VM 일괄 설치: bash scripts/setup-vm-systemd.sh --all
# =============================================================================

PROJECT="ralphton"

setup_single_vm() {
  local vm_name="$1"
  local zone="$2"

  echo "=== ${vm_name} systemd 서비스 설치 중... ==="

  gcloud compute ssh "$vm_name" \
    --project="$PROJECT" \
    --zone="$zone" \
    --command="
set -e

# 로그 디렉토리 생성
mkdir -p ~/logs

# systemd 서비스 파일 생성
sudo tee /etc/systemd/system/openclaw-agent.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=Ralphton OpenClaw Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=inkeun
WorkingDirectory=/home/inkeun
ExecStart=/usr/local/bin/openclaw start
Restart=always
RestartSec=5
StartLimitIntervalSec=300
StartLimitBurst=20
Environment=HOME=/home/inkeun
StandardOutput=append:/home/inkeun/logs/openclaw-agent.log
StandardError=append:/home/inkeun/logs/openclaw-agent-error.log

# 프로세스가 죽으면 5초 후 재시작
# 5분 내 20번까지 재시작 허용
# 그 이후에도 계속 재시작 (watchdog가 서비스 리셋)

[Install]
WantedBy=multi-user.target
SERVICEEOF

# watchdog 타이머 생성 (서비스 상태 감시 + 자동 복구)
sudo tee /etc/systemd/system/openclaw-watchdog.service > /dev/null << 'WDSERVEOF'
[Unit]
Description=Ralphton OpenClaw Watchdog
After=openclaw-agent.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'systemctl is-active openclaw-agent.service || (systemctl reset-failed openclaw-agent.service 2>/dev/null; systemctl start openclaw-agent.service)'
WDSERVEOF

sudo tee /etc/systemd/system/openclaw-watchdog.timer > /dev/null << 'WDTIMEREOF'
[Unit]
Description=Ralphton OpenClaw Watchdog Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
WDTIMEREOF

# systemd 리로드 및 활성화
sudo systemctl daemon-reload
sudo systemctl enable openclaw-agent.service
sudo systemctl enable openclaw-watchdog.timer

# 기존 openclaw 프로세스 정리 후 서비스 시작
pkill -f openclaw 2>/dev/null || true
sleep 2
sudo systemctl start openclaw-agent.service
sudo systemctl start openclaw-watchdog.timer

# 상태 확인
echo ''
echo '=== 서비스 상태 ==='
systemctl status openclaw-agent.service --no-pager || true
echo ''
echo '=== Watchdog 타이머 상태 ==='
systemctl status openclaw-watchdog.timer --no-pager || true
echo ''
echo '✅ systemd 서비스 설치 완료'
" 2>&1

  echo "✅ ${vm_name} 완료"
  echo ""
}

# 전체 VM 일괄 설치
if [ "${1:-}" = "--all" ]; then
  echo "=== 전체 VM systemd 서비스 일괄 설치 ==="
  echo ""
  setup_single_vm "ralphton-watcher" "asia-northeast3-a"
  setup_single_vm "ralphton-developer" "asia-northeast3-a"
  setup_single_vm "ralphton-domain-expert" "asia-northeast3-a"
  setup_single_vm "ralphton-a100" "us-central1-a"
  setup_single_vm "ralphton-evaluator" "asia-northeast3-a"
  echo "=== 전체 완료 ==="
  exit 0
fi

# 단일 VM 설치
if [ $# -lt 2 ]; then
  echo "사용법:"
  echo "  단일 VM: bash $0 <vm-name> <zone>"
  echo "  전체 VM: bash $0 --all"
  echo ""
  echo "예:"
  echo "  bash $0 ralphton-watcher asia-northeast3-a"
  echo "  bash $0 --all"
  exit 1
fi

setup_single_vm "$1" "$2"
