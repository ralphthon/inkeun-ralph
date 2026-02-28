// Discord 최근 메시지 조회 스크립트
const { Client, GatewayIntentBits } = require('discord.js');
const fs = require('fs');
const path = require('path');

// .env 수동 파싱
const envPath = path.join(__dirname, '..', '.env');
const env = {};
fs.readFileSync(envPath, 'utf8').split('\n').forEach(line => {
  const m = line.match(/^([^#=\s][^=]*)=(.*)$/);
  if (m) env[m[1].trim()] = m[2].trim();
});

const token = env['Watcher_Claw'];
const channelName = env['DISCORD_CHANNEL'] || 'claw-dev-chat';
const MINUTES = parseInt(process.argv[2] || '30');

if (!token) {
  console.log('ERROR: Watcher_Claw 토큰 없음');
  process.exit(1);
}

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent
  ]
});

client.once('ready', async () => {
  try {
    const guild = client.guilds.cache.first();
    if (!guild) { console.log('NO_GUILD'); client.destroy(); return; }

    const channel = guild.channels.cache.find(c => c.name === channelName);
    if (!channel) { console.log('NO_CHANNEL: ' + channelName); client.destroy(); return; }

    const messages = await channel.messages.fetch({ limit: 50 });
    const cutoff = Date.now() - MINUTES * 60 * 1000;

    const recent = messages.filter(m => m.createdTimestamp > cutoff);
    console.log(`=== 최근 ${MINUTES}분 메시지: ${recent.size}개 ===`);

    const sorted = [...recent.values()].sort((a,b) => a.createdTimestamp - b.createdTimestamp);
    sorted.forEach(m => {
      const t = new Date(m.createdTimestamp);
      // KST = UTC+9
      const kstMs = m.createdTimestamp + 9 * 3600 * 1000;
      const kstDate = new Date(kstMs);
      const hh = String(kstDate.getUTCHours()).padStart(2,'0');
      const mm = String(kstDate.getUTCMinutes()).padStart(2,'0');
      const content = m.content.substring(0, 300).replace(/\n/g, ' | ');
      console.log(`[${hh}:${mm}] ${m.author.username}: ${content}`);
    });

    client.destroy();
  } catch(e) {
    console.log('ERROR: ' + e.message);
    client.destroy();
    process.exit(1);
  }
});

client.login(token).catch(e => { console.log('LOGIN_ERROR: ' + e.message); process.exit(1); });
setTimeout(() => { try { client.destroy(); } catch(e){} process.exit(0); }, 20000);
