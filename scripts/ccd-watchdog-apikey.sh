#!/bin/bash
# =============================================================================
# Ralphton CCD Watchdog (API Key 백업) — Anthropic API 직접 사용
# =============================================================================
# 메인 launchd watchdog가 인증 실패 시 백업으로 5분마다 cron 실행.
# CLAUDE_API_KEY를 사용하여 claude.ai 로그인 없이 작동.
# 3/1 09:00 KST까지 운영.
# =============================================================================

set -euo pipefail

# --- 설정 ---
PROJECT_DIR="/Users/inkeun/projects/ralphton"
LOG_DIR="${PROJECT_DIR}/logs"
LOG_FILE="${LOG_DIR}/ccd-watchdog.log"
LOCK_FILE="/tmp/ccd-watchdog.lock"
CLAUDE_BIN="/Users/inkeun/.local/bin/claude"
MAX_LOG_LINES=3000

# --- PATH (cron 환경용) ---
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:/opt/homebrew/bin:/usr/local/bin:/Users/inkeun/.local/bin:$PATH"
export HOME="/Users/inkeun"

# 중첩 세션 방지 환경변수 해제
unset CLAUDECODE 2>/dev/null || true

# .env에서 CLAUDE_API_KEY 로드
if [ -f "${PROJECT_DIR}/.env" ]; then
  CLAUDE_API_KEY=$(grep '^CLAUDE_API_KEY' "${PROJECT_DIR}/.env" | sed 's/^CLAUDE_API_KEY *= *//' | tr -d '"' | tr -d "'")
  export ANTHROPIC_API_KEY="$CLAUDE_API_KEY"
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "[$(TZ='Asia/Seoul' date '+%Y-%m-%d %H:%M:%S KST')] ANTHROPIC_API_KEY 없음. 종료." >> "$LOG_FILE"
  exit 1
fi

# gcloud SDK 환경 로드
if [ -f "/opt/homebrew/share/google-cloud-sdk/path.bash.inc" ]; then
  source "/opt/homebrew/share/google-cloud-sdk/path.bash.inc"
fi

# --- 유틸 ---
timestamp() {
  TZ="Asia/Seoul" date "+%Y-%m-%d %H:%M:%S KST"
}

log() {
  echo "[$(timestamp)] [BACKUP] $1" >> "$LOG_FILE"
}

# 로그 로테이션
rotate_log() {
  if [ -f "$LOG_FILE" ]; then
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$MAX_LOG_LINES" ]; then
      tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
      log "로그 로테이션 완료 (${line_count} → 1000줄)"
    fi
  fi
}

# 데드라인 체크: 3/1 09:00 KST 이후면 종료
check_deadline() {
  local current_date current_hour
  current_date=$(TZ="Asia/Seoul" date "+%Y-%m-%d")
  current_hour=$(TZ="Asia/Seoul" date "+%H" | sed 's/^0//')

  if [ "$current_date" = "2026-03-01" ] && [ "$current_hour" -ge 9 ]; then
    log "데드라인 도달 (3/1 09:00 KST). Backup Watchdog 종료."
    crontab -l 2>/dev/null | grep -v "ccd-watchdog-apikey" | crontab - 2>/dev/null || true
    log "크론잡 자동 제거 완료."
    exit 0
  fi
}

# 메인 watchdog가 최근 실행되었는지 확인
check_main_watchdog() {
  # 메인 watchdog 로그에서 최근 7분 내 성공 기록이 있으면 백업 불필요
  if [ -f "$LOG_FILE" ]; then
    local last_success
    last_success=$(grep -v "\[BACKUP\]" "$LOG_FILE" | grep "CCD Watchdog 실행 완료" | tail -1 | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}' || echo "")
    if [ -n "$last_success" ]; then
      local last_epoch now_epoch diff
      last_epoch=$(TZ="Asia/Seoul" date -j -f "%Y-%m-%d %H:%M:%S" "$last_success" "+%s" 2>/dev/null || echo 0)
      now_epoch=$(TZ="Asia/Seoul" date "+%s")
      diff=$(( now_epoch - last_epoch ))
      if [ "$diff" -lt 420 ]; then
        log "메인 watchdog가 ${diff}초 전 성공. 백업 실행 건너뜀."
        return 0
      fi
    fi
  fi
  return 1
}

# 중복 실행 방지 (lock file) — 메인 watchdog과 동일 lock 사용
acquire_lock() {
  if [ -f "$LOCK_FILE" ]; then
    local lock_pid
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      log "CCD Watchdog 실행 중 (PID: ${lock_pid}). 건너뜀."
      exit 0
    else
      rm -f "$LOCK_FILE"
    fi
  fi
  echo $$ > "$LOCK_FILE"
}

release_lock() {
  rm -f "$LOCK_FILE"
}

trap release_lock EXIT

# --- 메인 ---
main() {
  mkdir -p "$LOG_DIR"
  rotate_log
  check_deadline

  # 메인 watchdog가 최근 성공했으면 백업 불필요
  if check_main_watchdog; then
    return 0
  fi

  acquire_lock

  log "========== Backup CCD Watchdog 실행 시작 (API Key) =========="

  # 현재 시간 정보 수집
  local current_time
  current_time=$(TZ="Asia/Seoul" date "+%Y-%m-%d %H:%M KST")

  # VM 상태 사전 수집
  local vm_status=""
  for vm in ralphton-watcher:asia-northeast3-a ralphton-developer:asia-northeast3-a ralphton-domain-expert:asia-northeast3-a ralphton-a100:us-central1-a ralphton-evaluator:asia-northeast3-a; do
    local name="${vm%%:*}"
    local zone="${vm##*:}"
    local status
    status=$(gcloud compute instances describe "$name" --project=ralphton --zone="$zone" --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    vm_status="${vm_status}${name} (${zone}): ${status}\n"
  done

  log "VM 상태 수집 완료"

  # Claude Code 실행 (API Key 모드)
  local prompt
  prompt=$(cat <<'PROMPT_EOF'
너는 Ralphton 해커톤 프로젝트의 자동화 감시자(Watchdog)다.
현재 시간: __CURRENT_TIME__

## 네 역할
1. 모든 GCP VM이 정상 작동하는지 확인하고, 문제가 있으면 즉시 해결
2. Discord #claw-dev-chat에서 최근 대화를 확인하여 진행 상황 파악
3. 진행이 멈춰있다면 적절한 에이전트에게 Discord로 트리거 메시지 전송
4. 진행상황을 progress/STATUS.md에 업데이트

## 현재 VM 상태 (사전 수집)
__VM_STATUS__

## 수행할 작업 (순서대로)

### Step 1: VM 상태 확인 및 복구
- TERMINATED/STOPPED VM이 있으면 `gcloud compute instances start`로 시작
- RUNNING인데 SSH 안 되면 리셋 고려
- A100(ralphton-a100)은 Spot 인스턴스라 선점될 수 있음 → 재시작 필요

### Step 2: 에이전트 프로세스 확인
RUNNING VM에 SSH 접속하여 `pgrep -f openclaw` 실행.
죽어있으면: `pkill -f openclaw; sleep 2; nohup bash -c 'cd /home/inkeun && openclaw start --daemon' > ~/logs/agent-restart.log 2>&1 &`

### Step 3: Discord 최근 활동 확인
node -e 스크립트로 최근 20분간 #claw-dev-chat 메시지를 확인.
`.env` 파일에서 Discord 토큰을 읽어라 (Watcher_Claw 토큰 사용).

### Step 4: 진행 트리거
- 20분 이상 메시지가 없는 에이전트가 있으면 해당 에이전트에게 Discord 멘션으로 상태 보고 요청
- Phase 전환 조건이 충족되었는데 전환이 안 되어 있으면 Watcher에게 알림
- BLOCKED 상태의 에이전트가 있으면 원인 파악 후 해결 시도

### Step 5: 상태 기록
- progress/STATUS.md 업데이트
- 주요 이벤트는 logs/ccd-watchdog.log에 echo로 기록

## 봇 멘션 ID (Discord 메시지에 필수)
- Watcher: <@1477205631927717900>
- Developer: <@1477168971718332516>
- DomainExpert: <@1477242490640928848>
- Training: <@1477243247956066414>
- Evaluation: <@1477244275803689020>

## 주의사항
- Discord 메시지 전송 시 반드시 `<@USER_ID>` 형식 멘션 포함
- gcloud 명령 실패 시 재시도 1회
- 최대 실행시간 5분 이내로 마무리
- 불필요한 VM 재시작은 하지 않음 (확실한 장애만 복구)
- A100은 us-central1-a 존에 있음 (다른 VM은 asia-northeast3-a)

작업을 시작해라. 각 단계를 실행하고 결과를 간단히 보고해라.
PROMPT_EOF
)

  # 동적 값 치환
  prompt="${prompt//__CURRENT_TIME__/$current_time}"
  prompt="${prompt//__VM_STATUS__/$(echo -e "$vm_status")}"

  log "Claude Code 실행 시작 (API Key, model: sonnet)"

  # Claude Code 실행 (API Key 인증)
  local output
  output=$("$CLAUDE_BIN" \
    -p \
    --dangerously-skip-permissions \
    --model sonnet \
    --max-budget-usd 2.00 \
    --no-session-persistence \
    "$prompt" \
    2>&1) || true

  # 결과 로깅 (마지막 50줄만)
  log "Claude Code 실행 완료"
  echo "$output" | tail -50 >> "$LOG_FILE"

  log "========== Backup CCD Watchdog 실행 완료 =========="
}

# 실행
cd "$PROJECT_DIR"
main "$@"
