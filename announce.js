const { createBot, mention, mentionAll } = require('./claw-bot');

async function main() {
  // Watcher 봇으로 공지 발송
  const bot = await createBot({
    name: 'Announce',
    token: process.env.Watcher_Claw,
  });

  // --- SSOT 업데이트 공지 + 멘션 규칙 ---
  await bot.send(
    `${mentionAll()}\n\n` +
    `⚠️ **[긴급] SSOT 업데이트 + Discord 멘션 규칙 변경**\n\n` +
    `각 VM의 ~/ssot/ 가 방금 업데이트되었다. **즉시 다시 읽어라.**\n\n` +
    `**핵심 변경: Discord 멘션 형식**\n` +
    `메시지를 보낼 때 반드시 \`<@USER_ID>\` 형식을 사용해야 한다.\n` +
    `텍스트로 \`@Developer\` 라고 쓰면 알림이 전달되지 않는다.\n\n` +
    `**봇 User ID:**\n` +
    `- Watcher: ${mention('Watcher')}\n` +
    `- Developer: ${mention('Developer')}\n` +
    `- DomainExpert: ${mention('DomainExpert')}\n` +
    `- Training: ${mention('Training')}\n` +
    `- Evaluation: ${mention('Evaluation')}\n\n` +
    `자세한 내용은 각자 ~/ssot/ 의 INSTRUCTIONS.md 상단을 확인하라.\n` +
    `지금부터 모든 메시지에 이 형식을 사용하라.`
  );

  // --- Watcher 지시 ---
  await bot.send(
    `${mention('Watcher')} 너는 이 프로젝트의 지휘자다.\n\n` +
    `~/ssot/PLAN.md 와 ~/ssot/watcher/INSTRUCTIONS.md 를 **다시** 읽어라. 멘션 규칙이 추가되었다.\n` +
    `20:00 KST에 Phase 1을 시작하라.\n` +
    `첫 번째 지시: ${mention('Developer')} 에게 Phase 1 시뮬레이터 구축 시작을 HANDOFF하라.\n` +
    `동시에 ${mention('DomainExpert')} 에게 시나리오 v1 생성을 지시하라.\n` +
    `이후 INSTRUCTIONS.md의 모든 규칙을 따라 자율적으로 운영하라.\n\n` +
    `목표: 10+ 사이클 파이프라인 완주 + 시연 영상 확보.\n` +
    `사람의 개입 없이 08:00까지 완주하라.\n\n` +
    `⚠️ **메시지 보낼 때 반드시 <@USER_ID> 형식 사용. 텍스트 @이름은 알림이 안 간다.**`
  );

  // --- 전체 에이전트 작업 지시 ---
  await bot.send(
    `${mentionAll()}\n\n` +
    `=== 전체 에이전트 작업 지시 ===\n\n` +
    `각 에이전트는 자신의 ~/ssot/{에이전트명}/INSTRUCTIONS.md를 **지금 즉시** 다시 읽고 지시에 따라 행동하라.\n` +
    `${mention('Watcher')}의 지시를 기다려라. Watcher가 Phase를 시작하면 즉시 작업에 착수하라.\n\n` +
    `현재 시각: ${new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' })} KST\n` +
    `데드라인: 2026-03-01 08:00 KST\n\n` +
    `로컬 watchdog 크론잡이 3분마다 전체 VM을 감시 중. 에이전트가 죽으면 자동 복구된다.`
  );

  console.log('[Announce] 전체 공지 발송 완료 (SSOT 업데이트 + 멘션 규칙 + 작업 지시)');

  // 3초 후 종료 (메시지 전송 대기)
  setTimeout(() => process.exit(0), 3000);
}

main().catch(console.error);
