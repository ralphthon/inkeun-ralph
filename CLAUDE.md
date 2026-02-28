# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ralphton은 21시간 해커톤(2/28 15:00 ~ 3/1 12:00)용 **Physical AI 파이프라인** 프로젝트. 5개 AI 에이전트가 각각 GCP VM에서 Discord를 통해 협업하며, LEGO 수거 시뮬레이터 구축 → 학습 데이터 생성 → ACT 모델 훈련을 자율적으로 수행한다.

## Commands

```bash
# Discord 봇 실행
node developer-bot.js
node watcher-bot.js

# 의존성 설치
npm install

# 시뮬레이터 (브라우저)
open loader-simulator.html

# headless 배치 생성 (Phase 2, 미구현)
xvfb-run node batch-generate.js --scenarios <path> --output ~/output/ --count 100

# LeRobot 변환 (Phase 2, 미구현)
python convert-lerobot.py --episodes ~/output/episodes/ --output gs://ralphton-handoff/dataset/
```

## Architecture

### 5-Agent Multi-VM System

- **Watcher** (GPT-4o, n2-standard-8, asia-northeast3-a): Conductor. 타임라인 관리, 10분 간격 상태 체크, 페이즈 전환 결정
- **Developer** (Claude Opus 4.6, n2-standard-8, asia-northeast3-a): 시뮬레이터 코드 개발, headless 렌더링, 배치 생성
- **DomainExpert** (n2-standard-4, asia-northeast3-a): 시나리오 JSON 설계 (코드 작성 안 함)
- **Training** (A100 Spot, us-central1-a): ACT 모델 훈련, 체크포인트 관리
- **Evaluation** (n2-standard-4, asia-northeast3-a): 데이터/모델 품질 검증, 실패 분석

### Communication Protocol

- 채널: Discord `#claw-dev-chat`
- 메시지 형식: `[STATUS] message` (STATUS: REPORT, REQUEST, DONE, BLOCKED, HANDOFF)
- 에이전트 간 멘션 필수: `@agent_name`

### Handoff Chain (GCS Bucket: `gs://ralphton-handoff/`)

```
Watcher → Developer: ssot/
Developer → Training: dataset/ (episodes/ → LeRobot HDF5)
Training → Evaluation: checkpoints/
Evaluation → DomainExpert: reports/
DomainExpert → Developer: scenarios/
```

### Key Source Files

- **claw-bot.js**: Discord 봇 팩토리. `createBot()` → `{send, client, channel}` 반환
- **developer-bot.js / watcher-bot.js**: 각 에이전트의 봇 인스턴스
- **loader-simulator.html**: Three.js + cannon-es 기반 브라우저 시뮬레이터 (1229줄). 로더 물리, 멀티 카메라, Expert Agent 상태머신 포함

### SSOT Directory

`SSOT/` 폴더가 전체 오케스트레이션 블루프린트:

- `PLAN.md`: 마스터 타임라인, 아키텍처, 페이즈 게이트 조건
- `developer/INSTRUCTIONS.md`: 시뮬레이터 모듈 구조, 액션 스페이스, 레코딩 포맷
- `watcher/INSTRUCTIONS.md`: 페이즈 전환 기준, 타임아웃 정책
- `domain-expert/INSTRUCTIONS.md`: 시나리오 JSON 스키마, 배치별 분포
- `training/INSTRUCTIONS.md`: ACT 설정 (chunk_size 20, batch 64, ResNet18), Spot 복원
- `evaluation/INSTRUCTIONS.md`: 검증 체크리스트, 피드백 생성 규칙

## D2E Framework (Desktop to Embodied AI)

시뮬레이터의 핵심 설계 원칙. AI가 게임을 만들고, 게임이 학습 데이터를 생성한다.

- **Tech stack**: Three.js + cannon-es (LLM 코드 생성에 친화적)
- **학습 해상도**: 640x480 → 224x224 (모델 입력)
- **로더 액션 스페이스**: 4D continuous — steering, throttle, bucket, lift (각 [-1, 1])
- **Expert Agent**: 7개 상태 (SCANNING → APPROACHING → LOWERING_BUCKET → SCOOPING → LIFTING → TRANSPORTING → DUMPING)
- **카메라**: ego, birds_eye, follow 3시점 동시 녹화

## Critical Technical Constraints (lessons-learned.md 참조)

이전 개발에서 검증된 필수 적용 사항:

- **물리 엔진 회전**: 키네마틱 yaw 제어 + `body.angularVelocity.set(0,0,0)` 매 프레임
- **CANNON ↔ THREE.js**: `setFromEuler()` API 차이 (CANNON은 숫자 3개, THREE는 Euler 객체)
- **상태 전환**: 액션 전환 시 velocity/rotation 명시적 리셋 필수
- **진동 방지**: `threshold > 2 × angular_speed × dt`, 복합 액션(전진+회전) + 비례 조향
- **카메라**: follow 카메라 초기 위치를 로더 위치로 설정, `camera.up.set(0,1,0)` 매 프레임
- **headless-gl**: Draco 압축 불가, SkinnedMesh 불안정, WebGL 1.0만 지원
- **메모리**: 1920x1080은 OOM → 학습용은 640x480 고정

## Environment Variables (.env)

- `DISCORD_TOKEN_*`: 봇별 Discord 토큰
- `DISCORD_CHANNEL`: 소통 채널명
- `GCP_PROJECT`, `GCP_ZONE`: GCP 설정
- `CLAUDE_API_KEY`: Anthropic API 키
- `GCS_BUCKET`: handoff 버킷 경로

## Phase Timeline

- **Phase 0** (pre-20:00): 인프라 셋업, VM 연결 확인
- **Phase 1** (20:00-22:00): 시뮬레이터 구축, 1개 에피소드 완성
- **Phase 2** (22:00-23:30): 배치 생성 50+개, LeRobot HDF5 변환
- **Phase 3** (23:30-03:00): ACT 모델 훈련 (A100)
- **Phase 4** (03:00-06:00): Humanoid RL (병렬)
- **Phase 5** (06:00-08:00): 문서화 + 데모
