#!/bin/bash
# =============================================================================
# Ralphton Watchdog — 절대 중단 불가 감시 시스템
# =============================================================================
# 3분마다 크론으로 실행. 모든 VM과 에이전트 프로세스를 감시하고 자동 복구한다.
# 오전 8시(KST)까지 중단 없이 파이프라인이 돌아가도록 보장.
# =============================================================================

set -euo pipefail

# --- 설정 ---
PROJECT="ralphton"
LOG_DIR="/Users/inkeun/projects/ralphton/logs"
LOG_FILE="${LOG_DIR}/watchdog.log"
DISCORD_LOG="${LOG_DIR}/watchdog-discord.log"
MAX_LOG_LINES=5000

# VM 정의: "이름:존:프로세스패턴:재시작명령"
declare -a VMS=(
  "ralphton-watcher:asia-northeast3-a:openclaw:cd /home/inkeun && openclaw start --daemon"
  "ralphton-developer:asia-northeast3-a:openclaw:cd /home/inkeun && openclaw start --daemon"
  "ralphton-domain-expert:asia-northeast3-a:openclaw:cd /home/inkeun && openclaw start --daemon"
  "ralphton-a100:us-central1-a:openclaw:cd /home/inkeun && openclaw start --daemon"
  "ralphton-evaluator:asia-northeast3-a:openclaw:cd /home/inkeun && openclaw start --daemon"
)

# 종료 시간 (KST 08:00 = UTC 23:00 전날)
# 크론잡 자체를 08:00에 종료시키므로 여기서도 체크
DEADLINE_HOUR=8

# --- 유틸 함수 ---
timestamp() {
  date "+%Y-%m-%d %H:%M:%S KST"
}

log() {
  echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

log_alert() {
  echo "[$(timestamp)] ⚠️  $1" | tee -a "$LOG_FILE"
  echo "[$(timestamp)] $1" >> "$DISCORD_LOG"
}

log_revive() {
  echo "[$(timestamp)] 🔄 $1" | tee -a "$LOG_FILE"
  echo "[$(timestamp)] $1" >> "$DISCORD_LOG"
}

log_ok() {
  echo "[$(timestamp)] ✅ $1" | tee -a "$LOG_FILE"
}

# 로그 파일 로테이션
rotate_log() {
  if [ -f "$LOG_FILE" ]; then
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$MAX_LOG_LINES" ]; then
      tail -n 2000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
      log "로그 로테이션 완료 (${line_count} → 2000줄)"
    fi
  fi
}

# 시간 체크: 08:00 KST 이후면 종료
check_deadline() {
  local current_hour
  current_hour=$(TZ="Asia/Seoul" date "+%H" | sed 's/^0//')
  local current_date
  current_date=$(TZ="Asia/Seoul" date "+%Y-%m-%d")

  # 3/1 08:00 이후면 종료
  if [ "$current_date" = "2026-03-01" ] && [ "$current_hour" -ge "$DEADLINE_HOUR" ]; then
    log "⏰ 데드라인 도달 (08:00 KST). Watchdog 종료."
    exit 0
  fi
}

# Discord 채널에 알림 전송 (로컬 봇 사용)
send_discord_alert() {
  local message="$1"
  # node 스크립트로 Discord 알림 전송
  node -e "
    const { Client, GatewayIntentBits } = require('/Users/inkeun/projects/ralphton/node_modules/discord.js');
    require('dotenv').config({ path: '/Users/inkeun/projects/ralphton/.env' });
    const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages] });
    client.once('ready', async () => {
      const ch = client.channels.cache.find(c => c.name === 'claw-dev-chat' && c.isTextBased());
      if (ch) await ch.send('${message}');
      client.destroy();
      process.exit(0);
    });
    client.login(process.env.Watcher_Claw).catch(() => process.exit(1));
  " 2>/dev/null &
  # 타임아웃 10초 (백그라운드 실행이므로 블록하지 않음)
}

# --- VM 상태 체크 및 복구 ---

check_vm_status() {
  local vm_name="$1"
  local zone="$2"

  local status
  status=$(gcloud compute instances describe "$vm_name" \
    --project="$PROJECT" \
    --zone="$zone" \
    --format="value(status)" 2>/dev/null || echo "ERROR")

  echo "$status"
}

start_vm() {
  local vm_name="$1"
  local zone="$2"

  log_revive "VM 시작 중: ${vm_name} (${zone})"

  if gcloud compute instances start "$vm_name" \
    --project="$PROJECT" \
    --zone="$zone" 2>>"$LOG_FILE"; then
    log_ok "VM 시작 성공: ${vm_name}"
    send_discord_alert "[WATCHDOG 🔄] ${vm_name} VM이 중단되어 자동 재시작했습니다."
    # VM 부팅 후 에이전트 프로세스 시작을 위해 대기
    sleep 30
    return 0
  else
    log_alert "VM 시작 실패: ${vm_name}"
    send_discord_alert "[WATCHDOG ❌] ${vm_name} VM 재시작 실패! 수동 개입 필요."
    return 1
  fi
}

check_agent_process() {
  local vm_name="$1"
  local zone="$2"
  local process_pattern="$3"

  local result
  result=$(gcloud compute ssh "$vm_name" \
    --project="$PROJECT" \
    --zone="$zone" \
    --command="pgrep -f '${process_pattern}' > /dev/null 2>&1 && echo 'ALIVE' || echo 'DEAD'" \
    --ssh-flag="-o ConnectTimeout=10" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    2>/dev/null || echo "SSH_FAIL")

  # 결과에서 ALIVE/DEAD/SSH_FAIL 추출
  if echo "$result" | grep -q "ALIVE"; then
    echo "ALIVE"
  elif echo "$result" | grep -q "DEAD"; then
    echo "DEAD"
  else
    echo "SSH_FAIL"
  fi
}

restart_agent_process() {
  local vm_name="$1"
  local zone="$2"
  local restart_cmd="$3"

  log_revive "에이전트 프로세스 재시작 중: ${vm_name}"

  # 기존 프로세스 정리 후 재시작
  gcloud compute ssh "$vm_name" \
    --project="$PROJECT" \
    --zone="$zone" \
    --command="pkill -f openclaw 2>/dev/null; sleep 2; nohup bash -c '${restart_cmd}' > ~/logs/agent-restart.log 2>&1 &" \
    --ssh-flag="-o ConnectTimeout=15" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    2>>"$LOG_FILE"

  if [ $? -eq 0 ]; then
    log_ok "에이전트 프로세스 재시작 성공: ${vm_name}"
    send_discord_alert "[WATCHDOG 🔄] ${vm_name}의 에이전트 프로세스가 죽어서 자동 재시작했습니다."
    return 0
  else
    log_alert "에이전트 프로세스 재시작 실패: ${vm_name}"
    send_discord_alert "[WATCHDOG ❌] ${vm_name} 에이전트 재시작 실패! 수동 개입 필요."
    return 1
  fi
}

# GPU 체크 (A100 전용)
check_gpu() {
  local vm_name="ralphton-a100"
  local zone="us-central1-a"

  local gpu_status
  gpu_status=$(gcloud compute ssh "$vm_name" \
    --project="$PROJECT" \
    --zone="$zone" \
    --command="nvidia-smi > /dev/null 2>&1 && echo 'GPU_OK' || echo 'GPU_FAIL'" \
    --ssh-flag="-o ConnectTimeout=10" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    2>/dev/null || echo "SSH_FAIL")

  if echo "$gpu_status" | grep -q "GPU_FAIL"; then
    log_alert "A100 GPU 이상 감지!"
    send_discord_alert "[WATCHDOG ⚠️] ralphton-a100 GPU 이상 감지! nvidia-smi 실패. VM 재시작 필요할 수 있음."
    return 1
  fi
  return 0
}

# 디스크 공간 체크
check_disk() {
  local vm_name="$1"
  local zone="$2"

  local disk_usage
  disk_usage=$(gcloud compute ssh "$vm_name" \
    --project="$PROJECT" \
    --zone="$zone" \
    --command="df / --output=pcent | tail -1 | tr -dc '0-9'" \
    --ssh-flag="-o ConnectTimeout=10" \
    --ssh-flag="-o StrictHostKeyChecking=no" \
    2>/dev/null || echo "0")

  if [ -n "$disk_usage" ] && [ "$disk_usage" -gt 90 ] 2>/dev/null; then
    log_alert "디스크 90%+ 사용: ${vm_name} (${disk_usage}%)"
    # 자동 정리: 로그, tmp 파일
    gcloud compute ssh "$vm_name" \
      --project="$PROJECT" \
      --zone="$zone" \
      --command="find /tmp -type f -mmin +60 -delete 2>/dev/null; find ~/logs -name '*.log' -mmin +120 -delete 2>/dev/null" \
      --ssh-flag="-o ConnectTimeout=10" \
      --ssh-flag="-o StrictHostKeyChecking=no" \
      2>/dev/null
    send_discord_alert "[WATCHDOG ⚠️] ${vm_name} 디스크 ${disk_usage}% 사용 중. 임시 파일 자동 정리 수행."
  fi
}

# --- 메인 실행 ---

main() {
  rotate_log
  check_deadline

  log "========== Watchdog 실행 시작 =========="

  local all_ok=true
  local revived_count=0

  for vm_entry in "${VMS[@]}"; do
    IFS=':' read -r vm_name zone process_pattern restart_cmd <<< "$vm_entry"

    # 1단계: VM 상태 확인
    local vm_status
    vm_status=$(check_vm_status "$vm_name" "$zone")

    if [ "$vm_status" = "RUNNING" ]; then
      # 2단계: 에이전트 프로세스 확인
      local agent_status
      agent_status=$(check_agent_process "$vm_name" "$zone" "$process_pattern")

      case "$agent_status" in
        "ALIVE")
          log_ok "${vm_name}: VM=RUNNING, Agent=ALIVE"
          ;;
        "DEAD")
          all_ok=false
          log_alert "${vm_name}: VM=RUNNING, Agent=DEAD → 프로세스 재시작"
          restart_agent_process "$vm_name" "$zone" "$restart_cmd"
          revived_count=$((revived_count + 1))
          ;;
        "SSH_FAIL")
          all_ok=false
          log_alert "${vm_name}: VM=RUNNING, SSH 접속 실패 → VM 재시작 시도"
          # SSH 실패 시 VM 자체 문제일 수 있으므로 재시작
          gcloud compute instances reset "$vm_name" \
            --project="$PROJECT" \
            --zone="$zone" 2>>"$LOG_FILE" || true
          send_discord_alert "[WATCHDOG 🔄] ${vm_name} SSH 접속 불가. VM 리셋 수행."
          revived_count=$((revived_count + 1))
          ;;
      esac

      # 3단계: 디스크 체크 (alive인 경우만)
      if [ "$agent_status" = "ALIVE" ]; then
        check_disk "$vm_name" "$zone"
      fi

    elif [ "$vm_status" = "TERMINATED" ] || [ "$vm_status" = "STOPPED" ]; then
      all_ok=false
      log_alert "${vm_name}: VM=${vm_status} → 자동 시작"
      start_vm "$vm_name" "$zone"
      # VM 시작 후 에이전트도 시작
      restart_agent_process "$vm_name" "$zone" "$restart_cmd"
      revived_count=$((revived_count + 1))

    elif [ "$vm_status" = "STAGING" ] || [ "$vm_status" = "PROVISIONING" ]; then
      log "${vm_name}: VM=${vm_status} (시작 중, 다음 체크에서 확인)"

    else
      all_ok=false
      log_alert "${vm_name}: VM 상태 비정상 (${vm_status})"
      send_discord_alert "[WATCHDOG ❌] ${vm_name} 상태: ${vm_status}. 수동 확인 필요."
    fi
  done

  # A100 GPU 전용 체크
  local a100_status
  a100_status=$(check_vm_status "ralphton-a100" "us-central1-a")
  if [ "$a100_status" = "RUNNING" ]; then
    check_gpu
  fi

  # 요약
  if $all_ok; then
    log "========== 전체 정상 (5/5 VM, 5/5 Agent) =========="
  else
    log "========== 이상 감지 — 복구 ${revived_count}건 수행 =========="
  fi
}

# 실행
main "$@"
