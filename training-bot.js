const { createBot } = require('./claw-bot');

async function main() {
  const bot = await createBot({
    name: 'Training-Claw',
    token: process.env.Training_Claw,
    onMessage(message) {
      // OpenClaw 연동 시 여기서 AI에 전달
    },
  });

  await bot.send('[Training-Claw] 온라인. ACT 학습 대기 중.');
}

main().catch(console.error);
