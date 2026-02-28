#!/bin/bash
# =============================================================================
# Ralphton Watchdog 크론잡 설치 스크립트
# =============================================================================
# 사용법: bash scripts/install-watchdog.sh
# 제거:   bash scripts/install-watchdog.sh --remove
# =============================================================================

WATCHDOG_SCRIPT="/Users/inkeun/projects/ralphton/scripts/watchdog.sh"
LOG_DIR="/Users/inkeun/projects/ralphton/logs"
CRON_LOG="${LOG_DIR}/watchdog-cron.log"

# 크론 표현식: 3분마다, 2/28 20:00 ~ 3/1 08:00 (KST)
# macOS cron은 TZ 지원이 제한적이므로 watchdog.sh 내부에서 시간 체크
CRON_EXPR="*/3 * * * *"
CRON_COMMENT="# Ralphton Watchdog - 3분마다 VM 감시 및 자동 복구"
CRON_JOB="${CRON_EXPR} /bin/bash ${WATCHDOG_SCRIPT} >> ${CRON_LOG} 2>&1"

# 제거 모드
if [ "${1:-}" = "--remove" ]; then
  echo "Watchdog 크론잡 제거 중..."
  crontab -l 2>/dev/null | grep -v "Ralphton Watchdog" | grep -v "watchdog.sh" | crontab -
  echo "✅ 제거 완료."
  echo "현재 크론잡:"
  crontab -l 2>/dev/null || echo "(없음)"
  exit 0
fi

# 설치
echo "=== Ralphton Watchdog 크론잡 설치 ==="
echo ""

# 디렉토리 생성
mkdir -p "$LOG_DIR"

# 실행 권한 부여
chmod +x "$WATCHDOG_SCRIPT"

# 기존 watchdog 크론 제거 후 새로 추가
(crontab -l 2>/dev/null | grep -v "Ralphton Watchdog" | grep -v "watchdog.sh"; echo "$CRON_COMMENT"; echo "$CRON_JOB") | crontab -

echo "✅ 크론잡 설치 완료."
echo ""
echo "설정 요약:"
echo "  스크립트: ${WATCHDOG_SCRIPT}"
echo "  주기: 3분마다"
echo "  로그: ${CRON_LOG}"
echo "  VM 감시: 5대 (watcher, developer, domain-expert, a100, evaluator)"
echo ""
echo "현재 크론잡:"
crontab -l 2>/dev/null
echo ""
echo "즉시 테스트: bash ${WATCHDOG_SCRIPT}"
echo "제거: bash scripts/install-watchdog.sh --remove"
