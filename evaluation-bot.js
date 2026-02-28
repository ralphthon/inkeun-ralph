const { createBot } = require('./claw-bot');

async function main() {
  const bot = await createBot({
    name: 'Evaluation-Claw',
    token: process.env.Evaluation_Claw,
    onMessage(message) {
      // OpenClaw 연동 시 여기서 AI에 전달
    },
  });

  await bot.send('[Evaluation-Claw] 온라인. 평가 대기 중.');
}

main().catch(console.error);
