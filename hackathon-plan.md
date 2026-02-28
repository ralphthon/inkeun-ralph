# Ralphton 해커톤 - Dual OpenClaw 시스템 구축

## Context

Ralphthon 해커톤(2/28 15:00 ~ 3/1 12:00)에서 "랄프를 계속 돌리기"위한 시스템을 구축한다.
핵심 아이디어: 2개의 OpenClaw 에이전트(개발자/감시자)가 Discord를 통해 지속적으로 대화하며, 서로를 감시하고 작업을 이어나가는 자율 코딩 시스템.

## 아키텍처

```
┌─────────────────────┐         Discord         ┌─────────────────────┐
│   VM 1 (개발자)      │ ◀════ 채팅방 ════▶    │   VM 2 (감시자)      │
│                     │                         │                     │
│  OpenClaw           │                         │  OpenClaw           │
│  + Claude (Anthropic)│                        │  + Codex (OpenAI)   │
│                     │                         │                     │
│  역할: 코드 작성     │                         │  역할: 코드 리뷰    │
│  + 개발 작업 수행    │                         │  + 감시 + 질문      │
│                     │                         │                     │
│  cron: 주기적 보고   │                         │  cron: 주기적 질문  │
└─────────────────────┘                         └─────────────────────┘
```

## 기존 인프라

- **기존 VM**: knowledge-hub-vm (seo-knowledge-hub, asia-northeast3-a)
  - n2-standard-8, Ubuntu 22.04, 100GB, OpenClaw v2026.1.30 운영 중
  - 이 설정을 참고하여 2대의 VM을 ralphton 프로젝트에 생성

## 실행 계획

### 1단계: VM 2대 생성 (ralphton 프로젝트)

**VM 1 - 개발자 (Developer Claw)**
```bash
gcloud compute instances create ralphton-developer \
  --project=ralphton \
  --zone=asia-northeast3-a \
  --machine-type=n2-standard-8 \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --tags=openclaw
```

**VM 2 - 감시자 (Watcher Claw)**
```bash
gcloud compute instances create ralphton-watcher \
  --project=ralphton \
  --zone=asia-northeast3-a \
  --machine-type=n2-standard-8 \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-balanced \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --tags=openclaw
```

### 2단계: 기본 환경 셋업 (양쪽 VM 공통)

- Node.js 22.x LTS 설치
- git, tmux, build-essential 설치
- OpenClaw 설치 (기존 VM에서 소스 clone + pnpm install)

### 3단계: OpenClaw 설정

**VM 1 (개발자) 설정**
- LLM: Claude (Anthropic API)
- 채널: Discord 봇으로 연결
- 역할: 코드 작성, 개발 작업 수행

**VM 2 (감시자) 설정**
- LLM: Codex (OpenAI API)
- 채널: Discord 봇으로 연결
- 역할: 코드 리뷰, 감시, 질문

### 4단계: Discord 서버 및 봇 생성

**Discord 서버 생성**
- 새 Discord 서버 "Ralphton-Openclaw" 생성
- 전용 채널: #dev-chat (개발자-감시자 대화용)

**Discord 봇 2개 생성** (Discord Developer Portal)
- 봇 1: "Developer-Claw" — VM 1의 OpenClaw가 사용
- 봇 2: "Watcher-Claw" — VM 2의 OpenClaw가 사용
- 각 봇에 Message Content Intent 활성화
- 서버에 봇 초대 (Send Messages, Read Message History 권한)

### 5단계: Cron 잡 설정

**감시자 (VM 2)**
- 10~15분마다 개발자에게 진행 상황 질문

**개발자 (VM 1)**
- 작업 완료 시 자동 보고
- 일정 시간 침묵 시 자동 상태 보고

### 6단계: 실행 및 검증

- 양쪽 VM에서 openclaw-gateway 실행
- Discord에서 대화가 오가는지 확인
- cron 잡 동작 확인

## 확정 사항

- **VM 스펙**: 양쪽 모두 n2-standard-8 (8 vCPU, 32GB RAM)
- **개발자 LLM**: Claude (Anthropic)
- **감시자 LLM**: Codex (OpenAI)
- **채널**: Discord

## 핵심 파일 (기존 VM 참고)

- `/home/inkeun/openclaw/` — OpenClaw 소스코드
- `/home/inkeun/.openclaw/openclaw.json` — 메인 설정 파일
- `/home/inkeun/.openclaw/agents/` — 에이전트 정의
- `/home/inkeun/.openclaw/credentials/` — 인증 정보
