const { createBot } = require('./claw-bot');

async function main() {
  const bot = await createBot({
    name: 'Watcher-Claw',
    token: process.env.Watcher_Claw,
    onMessage(message) {
      // OpenClaw/Codex 연동 시 여기서 AI에 전달
      // 예: openclaw.handleMessage(message.content)
      //      .then(reply => bot.send(reply));
    },
  });

  await bot.send('[Watcher-Claw] 온라인. 감시 모드 시작.');
}

main().catch(console.error);
