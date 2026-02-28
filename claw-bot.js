const { Client, GatewayIntentBits } = require('discord.js');
require('dotenv').config();

const CHANNEL_NAME = process.env.DISCORD_CHANNEL || 'claw-dev-chat';

/**
 * Discord 봇 클라이언트를 생성하고 연결한다.
 * 자동 응답 없음 — 메시지 수신 시 onMessage 콜백만 호출.
 * OpenClaw 연동 시 onMessage에서 AI 처리 후 send()로 응답.
 *
 * @param {object} opts
 * @param {string} opts.name - 봇 이름 (로그용)
 * @param {string} opts.token - Discord 봇 토큰
 * @param {function} [opts.onMessage] - 메시지 수신 콜백 (message) => void
 * @returns {Promise<{send, client, channel}>}
 */
function createBot({ name, token, onMessage }) {
  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.MessageContent,
    ],
  });

  return new Promise((resolve, reject) => {
    let channel = null;

    client.once('ready', () => {
      console.log(`[${name}] 로그인 완료: ${client.user.tag}`);

      channel = client.channels.cache.find(
        (ch) => ch.name === CHANNEL_NAME && ch.isTextBased()
      );

      if (!channel) {
        reject(new Error(`[${name}] #${CHANNEL_NAME} 채널을 찾을 수 없음`));
        return;
      }

      console.log(`[${name}] #${CHANNEL_NAME} 채널 연결됨`);

      const send = (text) => channel.send(text);

      resolve({ send, client, channel });
    });

    client.on('messageCreate', (message) => {
      // 자기 자신의 메시지 무시
      if (message.author.id === client.user.id) return;
      // 지정 채널만 처리
      if (message.channel.name !== CHANNEL_NAME) return;

      console.log(`[${name}] 수신 <- ${message.author.username}: ${message.content}`);

      // 콜백이 있으면 호출 (자동 응답 없음)
      if (onMessage) onMessage(message);
    });

    client.login(token).catch(reject);
  });
}

module.exports = { createBot };
