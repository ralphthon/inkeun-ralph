# Ralphton

21시간 해커톤(2/28 15:00 ~ 3/1 12:00)용 **Physical AI 파이프라인** 프로젝트.

5개 AI 에이전트가 각각 GCP VM에서 Discord를 통해 협업하며, LEGO 수거 시뮬레이터 구축 → 학습 데이터 생성 → ACT 모델 훈련을 자율적으로 수행한다.

## D2E Framework (Desktop to Embodied AI)

AI가 게임을 만들고, 게임이 학습 데이터를 생성한다.

- **Tech stack**: Three.js + cannon-es (LLM 코드 생성에 친화적)
- **학습 해상도**: 640x480 → 224x224 (모델 입력)
- **로더 액션 스페이스**: 4D continuous — steering, throttle, bucket, lift (각 [-1, 1])
- **Expert Agent**: 7개 상태 (SCANNING → APPROACHING → LOWERING_BUCKET → SCOOPING → LIFTING → TRANSPORTING → DUMPING)
- **카메라**: ego, birds_eye, follow 3시점 동시 녹화

## 5-Agent Multi-VM System

- **Watcher** (GPT-4o, n2-standard-8): 지휘자. 타임라인 관리, 10분 간격 상태 체크, 페이즈 전환 결정
- **Developer** (Claude Opus 4.6, n2-standard-8): 시뮬레이터 코드 개발, headless 렌더링, 배치 생성
- **DomainExpert** (n2-standard-4): FMEA 방법론 기반 롱테일/에지케이스 식별, SPS 우선순위 기반 시나리오 JSON config 생성
- **Training** (A100 Spot, us-central1-a): ACT 모델 훈련, 체크포인트 관리
- **Evaluation** (n2-standard-4): 데이터/모델 품질 검증, 실패 분석

## Handoff Chain

```
GCS Bucket: gs://ralphton-handoff/

Watcher → Developer: ssot/
Developer → Training: dataset/ (episodes/ → LeRobot HDF5)
Training → Evaluation: checkpoints/
Evaluation → DomainExpert: reports/
DomainExpert → Developer: scenarios/
```

## Quick Start

```bash
# 의존성 설치
npm install

# 환경변수 설정
cp .env.example .env  # 토큰 등 입력

# Discord 봇 실행
node watcher-bot.js
node developer-bot.js
node domain-expert-bot.js
node training-bot.js
node evaluation-bot.js
```

## Project Structure

```
├── SSOT/                      # 오케스트레이션 블루프린트
│   ├── PLAN.md                # 마스터 타임라인, 아키텍처
│   ├── watcher/               # Watcher 에이전트 지침
│   ├── developer/             # Developer 에이전트 지침
│   ├── domain-expert/         # DomainExpert 에이전트 지침
│   ├── training/              # Training 에이전트 지침
│   ├── evaluation/            # Evaluation 에이전트 지침
│   └── reference/             # 시뮬레이터 원본 (ground truth)
├── claw-bot.js                # Discord 봇 팩토리
├── *-bot.js                   # 각 에이전트 봇 인스턴스
├── scripts/                   # 유틸리티 스크립트
└── vm-configs/                # GCP VM 설정
```

## Phase Timeline

- **Phase 0** (pre-20:00): 인프라 셋업, VM 연결 확인
- **Phase 1** (20:00-22:00): 시뮬레이터 구축, 1개 에피소드 완성
- **Phase 2** (22:00-23:30): 배치 생성 50+개, LeRobot HDF5 변환
- **Phase 3** (23:30-03:00): ACT 모델 훈련 (A100)
- **Phase 4** (03:00-06:00): Humanoid RL (병렬)
- **Phase 5** (06:00-08:00): 문서화 + 데모

## Communication Protocol

- 채널: Discord `#claw-dev-chat`
- 메시지 형식: `[STATUS] message` (STATUS: REPORT, REQUEST, DONE, BLOCKED, HANDOFF)
- 에이전트 간 멘션 필수: `@agent_name`
