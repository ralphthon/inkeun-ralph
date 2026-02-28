// Discord 메시지 전송 스크립트
// 사용: node send-discord.js "<메시지>"
const { Client, GatewayIntentBits } = require('discord.js');
const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
const env = {};
fs.readFileSync(envPath, 'utf8').split('\n').forEach(line => {
  const m = line.match(/^([^#=\s][^=]*)=(.*)$/);
  if (m) env[m[1].trim()] = m[2].trim();
});

const token = env['Watcher_Claw'];
const channelName = env['DISCORD_CHANNEL'] || 'claw-dev-chat';
const message = process.argv[2];

if (!message) {
  console.log('사용법: node send-discord.js "<메시지>"');
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

    await channel.send(message);
    console.log('메시지 전송 완료: ' + message.substring(0, 80) + '...');
    client.destroy();
  } catch(e) {
    console.log('ERROR: ' + e.message);
    client.destroy();
    process.exit(1);
  }
});

client.login(token).catch(e => { console.log('LOGIN_ERROR: ' + e.message); process.exit(1); });
setTimeout(() => { try { client.destroy(); } catch(e){} process.exit(0); }, 15000);
