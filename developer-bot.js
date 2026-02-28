const { createBot } = require('./claw-bot');

async function main() {
  const bot = await createBot({
    name: 'Developer-Claw',
    token: process.env.Developer_Claw,
    onMessage(message) {
      // OpenClaw/Claude 연동 시 여기서 AI에 전달
      // 예: openclaw.handleMessage(message.content)
      //      .then(reply => bot.send(reply));
    },
  });

  await bot.send('[Developer-Claw] 온라인. 개발 작업 대기 중.');
}

main().catch(console.error);
