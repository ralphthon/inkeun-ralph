const { createBot } = require('./claw-bot');

async function main() {
  const bot = await createBot({
    name: 'DomainExpert-Claw',
    token: process.env.DomainExpert_Claw,
    onMessage(message) {
      // OpenClaw 연동 시 여기서 AI에 전달
    },
  });

  await bot.send('[DomainExpert-Claw] 온라인. 시나리오 생성 대기 중.');
}

main().catch(console.error);
