const { Client, GatewayIntentBits } = require('discord.js');
require('dotenv').config();

const CHANNEL_NAME = process.env.DISCORD_CHANNEL || 'claw-dev-chat';

// 봇 User ID 맵 (토큰 base64 디코딩으로 추출)
const BOT_IDS = {
  Watcher: '1477205631927717900',
  Developer: '1477168971718332516',
  DomainExpert: '1477242490640928848',
  Training: '1477243247956066414',
  Evaluation: '1477244275803689020',
};

function mention(agentName) {
  const id = BOT_IDS[agentName];
  if (!id) throw new Error(`Unknown agent: ${agentName}`);
  return `<@${id}>`;
}

function mentionAll() {
  return Object.values(BOT_IDS).map(id => `<@${id}>`).join(' ');
}

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

      // --- 멘션 안전장치 ---
      // 상태 메시지([REPORT], [DONE] 등)인데 <@ 멘션이 없으면 경고 로그
      const STATUS_PATTERN = /\[(REPORT|REQUEST|DONE|BLOCKED|HANDOFF)]/;
      const MENTION_PATTERN = /<@\d+>/;

      const send = (text) => {
        if (STATUS_PATTERN.test(text) && !MENTION_PATTERN.test(text)) {
          console.warn(`[${name}] ⚠️ 멘션 누락 감지! 상태 메시지에 <@ID> 멘션이 없습니다.`);
          console.warn(`[${name}] 원본: ${text.substring(0, 100)}`);
          console.warn(`[${name}] 힌트: mention('Watcher') 등을 사용하세요.`);
        }
        return channel.send(text);
      };

      // 대상 에이전트를 지정하면 자동으로 멘션을 붙여주는 안전한 전송 함수
      const sendTo = (targets, text) => {
        const targetList = Array.isArray(targets) ? targets : [targets];
        const mentions = targetList.map(t => mention(t)).join(' ');
        return channel.send(`${mentions} ${text}`);
      };

      resolve({ send, sendTo, client, channel });
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

// 최근 N개 메시지에서 멘션 누락을 검사하는 유틸
async function auditMentions(channel, count = 20) {
  const messages = await channel.messages.fetch({ limit: count });
  const violations = [];
  const STATUS_PATTERN = /\[(REPORT|REQUEST|DONE|BLOCKED|HANDOFF)]/;
  const MENTION_PATTERN = /<@\d+>/;

  messages.forEach(msg => {
    if (msg.author.bot && STATUS_PATTERN.test(msg.content) && !MENTION_PATTERN.test(msg.content)) {
      violations.push({
        author: msg.author.username,
        content: msg.content.substring(0, 100),
        timestamp: msg.createdAt.toISOString(),
      });
    }
  });
  return violations;
}

module.exports = { createBot, BOT_IDS, mention, mentionAll, auditMentions };
