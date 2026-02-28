const { createBot } = require('./claw-bot');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROGRESS_DIR = path.join(__dirname, 'progress');
const CHAT_LOG = path.join(PROGRESS_DIR, 'chat-log.jsonl');
const STATUS_FILE = path.join(PROGRESS_DIR, 'STATUS.md');

// 진행상황 상태
const state = {
  currentPhase: 'Phase 0',
  currentCycle: 0,
  agents: {
    Watcher: { lastSeen: null, status: 'unknown' },
    Developer: { lastSeen: null, status: 'unknown' },
    DomainExpert: { lastSeen: null, status: 'unknown' },
    Training: { lastSeen: null, status: 'unknown' },
    Evaluation: { lastSeen: null, status: 'unknown' },
  },
  events: [],       // 주요 이벤트 (DONE, BLOCKED, HANDOFF)
  messageCount: 0,
};

// --- 유틸 ---

function kstNow() {
  return new Date().toLocaleString('ko-KR', { timeZone: 'Asia/Seoul' });
}

function kstISO() {
  const d = new Date();
  const offset = 9 * 60 * 60 * 1000;
  return new Date(d.getTime() + offset).toISOString().replace('Z', '+09:00');
}

function ensureDir() {
  if (!fs.existsSync(PROGRESS_DIR)) fs.mkdirSync(PROGRESS_DIR, { recursive: true });
}

// --- 채팅 로그 ---

function appendChatLog(message) {
  ensureDir();
  const entry = {
    ts: kstISO(),
    author: message.author.username,
    content: message.content,
    id: message.id,
  };
  fs.appendFileSync(CHAT_LOG, JSON.stringify(entry) + '\n');
}

// --- 메시지 파싱 ---

function parseStatus(content) {
  const match = content.match(/\[(REPORT|REQUEST|DONE|BLOCKED|HANDOFF)]/);
  return match ? match[1] : null;
}

function detectAgent(username) {
  const lower = username.toLowerCase();
  if (lower.includes('watcher')) return 'Watcher';
  if (lower.includes('developer')) return 'Developer';
  if (lower.includes('domain')) return 'DomainExpert';
  if (lower.includes('training')) return 'Training';
  if (lower.includes('evaluat')) return 'Evaluation';
  return null;
}

function detectCycle(content) {
  const match = content.match(/[Cc]ycle\s*(\d+)/);
  return match ? parseInt(match[1], 10) : null;
}

function detectPhase(content) {
  const match = content.match(/[Pp]hase\s*(\d+)/);
  return match ? `Phase ${match[1]}` : null;
}

// --- 상태 업데이트 ---

function updateState(message) {
  state.messageCount++;

  const agent = detectAgent(message.author.username);
  if (agent && state.agents[agent]) {
    state.agents[agent].lastSeen = kstNow();
  }

  const status = parseStatus(message.content);
  const cycle = detectCycle(message.content);
  const phase = detectPhase(message.content);

  if (cycle && cycle > state.currentCycle) {
    state.currentCycle = cycle;
  }
  if (phase) {
    state.currentPhase = phase;
  }

  // 주요 이벤트 기록
  if (status && ['DONE', 'BLOCKED', 'HANDOFF'].includes(status)) {
    const event = {
      ts: kstNow(),
      agent: agent || message.author.username,
      status,
      summary: message.content.substring(0, 200),
    };
    state.events.push(event);

    if (agent && state.agents[agent]) {
      state.agents[agent].status = status;
    }
  } else if (status === 'REPORT' && agent) {
    state.agents[agent].status = 'ACTIVE';
  }
}

// --- STATUS.md 생성 ---

function writeStatusFile() {
  ensureDir();

  const lines = [
    `# Ralphton 진행상황`,
    ``,
    `> 마지막 업데이트: ${kstNow()}`,
    ``,
    `## 현재 상태`,
    ``,
    `- **Phase**: ${state.currentPhase}`,
    `- **Cycle**: ${state.currentCycle || '시작 전'}`,
    `- **총 메시지**: ${state.messageCount}건`,
    ``,
    `## 에이전트 현황`,
    ``,
  ];

  for (const [name, info] of Object.entries(state.agents)) {
    const seen = info.lastSeen || '미확인';
    const st = info.status || 'unknown';
    lines.push(`- **${name}**: ${st} (마지막: ${seen})`);
  }

  lines.push(``, `## 주요 이벤트 (최근 50건)`, ``);

  const recent = state.events.slice(-50);
  if (recent.length === 0) {
    lines.push(`_아직 주요 이벤트 없음_`);
  } else {
    for (const ev of recent.reverse()) {
      lines.push(`- **[${ev.status}]** ${ev.ts} — ${ev.agent}: ${ev.summary}`);
    }
  }

  fs.writeFileSync(STATUS_FILE, lines.join('\n') + '\n');
}

// --- Git 자동 커밋 ---

function gitAutoCommit() {
  try {
    const repoRoot = __dirname;
    execSync('git add progress/', { cwd: repoRoot, stdio: 'pipe' });

    // 변경사항 있는지 확인
    const diff = execSync('git diff --cached --stat', { cwd: repoRoot, encoding: 'utf8' });
    if (!diff.trim()) return;

    const msg = `progress: ${state.currentPhase} Cycle ${state.currentCycle} (${state.messageCount} msgs) [auto]`;
    execSync(`git commit -m "${msg}"`, { cwd: repoRoot, stdio: 'pipe' });
    console.log(`[Watcher] Git commit: ${msg}`);
  } catch (e) {
    // 커밋할 변경 없으면 무시
    if (!e.message.includes('nothing to commit')) {
      console.error(`[Watcher] Git commit error:`, e.message);
    }
  }
}

// --- 메인 ---

async function main() {
  ensureDir();

  const bot = await createBot({
    name: 'Watcher-Claw',
    token: process.env.Watcher_Claw,
    onMessage(message) {
      // 1. 채팅 로그에 원본 저장
      appendChatLog(message);

      // 2. 상태 업데이트
      updateState(message);

      // 3. STATUS.md 갱신 (매 메시지마다)
      writeStatusFile();

      // OpenClaw/Codex 연동 시 여기서 AI에 전달
      // 예: openclaw.handleMessage(message.content)
      //      .then(reply => bot.send(reply));
    },
  });

  // 시작 메시지
  await bot.send('[Watcher-Claw] 온라인. 감시 모드 시작. 진행상황 로깅 활성화.');

  // 5분마다 git auto-commit
  setInterval(() => {
    writeStatusFile();
    gitAutoCommit();
  }, 5 * 60 * 1000);

  // 첫 STATUS.md 생성
  writeStatusFile();
  console.log(`[Watcher] 진행상황 로깅 시작: ${PROGRESS_DIR}`);
}

main().catch(console.error);
