# Ralphton — Physical AI 파이프라인

21시간 해커톤(2/28 15:00 ~ 3/1 12:00)용 **Physical AI 파이프라인** 프로젝트.

5개 AI 에이전트가 각각 GCP VM에서 Discord를 통해 협업하며, 축사 로더 시뮬레이터 구축 → 학습 데이터 생성 → ACT 모델 훈련을 자율적으로 수행한다.

## D2E 논문 기반

이 프로젝트는 **[D2E: Scaling Vision-Action Pretraining on Desktop Data for Transfer to Embodied AI](https://worv-ai.github.io/d2e/)** (ICLR 2026) 논문의 방법론을 축사 로더 도메인에 적용한다.

[![D2E Pipeline Overview](example-data/d2e-teaser.png)](https://worv-ai.github.io/d2e/)

D2E의 핵심 아이디어:

- **데스크톱 데이터 → 로봇 AI**: 대규모 언어 모델이 인터넷 텍스트를 활용하듯, 데스크톱 상호작용(게임 등)을 로봇 학습의 사전학습 데이터로 활용
- **OWA Toolkit**: 31개 게임에서 335.6시간 데이터 수집, 152배 압축률
- **Generalist-IDM**: 다양한 환경에서 제로샷 일반화, YouTube 1,000시간+ 의사 라벨링
- **Vision-Action Pretraining (VAPT)**: 데스크톱 사전학습 표현을 물리적 작업으로 전이
- **성과**: LIBERO 조작 96.6%, CANVAS 네비게이션 83.3%, SO101 실제 로봇 80% 성공률

Ralphton은 이 파이프라인을 **축사 로더 시뮬레이터**에 적용하여, 시뮬레이션 데이터로 사전학습한 뒤 실제 농업 로봇으로 전이하는 것을 목표로 한다.

## 프로젝트 개요

VLA/IL 모델 학습을 위한 합성 비디오 데이터 생성 파이프라인.
축사에서 소똥을 로더로 퍼서 옮기는 작업을 시뮬레이션하고, 다양한 시점의 비디오와 액션 라벨을 자동 생성한다.

**최종 목표**: 실제 농업용 로더에 학습된 모델을 적용하여 자율 작업 수행

## 시뮬레이터 데모

아래는 Expert Agent가 20개 레고 블록을 자동으로 수거하는 에피소드 영상이다.

https://github.com/user-attachments/assets/placeholder

> `example-data/` 디렉토리에 3개의 에피소드 영상(webm, ~46초)과 18개의 액션 토큰 파일(jsonl)이 포함되어 있다.

<video src="example-data/loader-cleanup-1772270551158.webm" controls width="640"></video>

<video src="example-data/loader-cleanup-1772270933800.webm" controls width="640"></video>

## D2E Framework (Desktop to Embodied AI)

AI가 게임을 만들고, 게임이 학습 데이터를 생성한다.

- **핵심 아이디어**: 브라우저 시뮬레이터에서 Expert Agent가 플레이 → 비디오 + 액션 토큰 자동 생성 → IL/VLA 모델 학습
- **Tech stack**: Three.js + cannon-es (LLM 코드 생성에 친화적)
- **학습 해상도**: 640x480 → 224x224 (모델 입력)
- **로더 액션 스페이스**: 4D continuous — steering, throttle, bucket, lift (각 [-1, 1])
- **Expert Agent**: 8개 상태 머신 (SCANNING → APPROACHING → LOWERING_BUCKET → SCOOPING → LIFTING → TRANSPORTING → DUMPING → COMPLETE)
- **카메라**: ego, birds_eye, follow 3시점 동시 녹화

## 전체 파이프라인

```
1. Scenario Generation     AI Agent가 일반 + 롱테일 시나리오 자동 생성
        │                  SpaTiaL 제약 검증
        ▼
2. Simulation + Rendering  Three.js + cannon-es 물리 시뮬레이션
        │                  headless-gl 기반 다중 시점 렌더링
        ▼
3. Auto Labeling           프레임별 액션 토큰 + 상태 자동 기록
        │                  SpaTiaL predicates 라벨링
        ▼
4. Training                Multi-view contrastive + consistency loss
        │                  ACT 모델 (chunk_size 20, batch 64, ResNet18)
        ▼
5. Evaluation              Sim 성공률 측정 → Real 환경 테스트
```

각 단계 완료 후 다음 단계가 자동 트리거되며, 실패 시 자동 재시도 및 롱테일 케이스가 추가된다.

## 액션 토큰 (Action Token)

시뮬레이터는 매 프레임마다 **4D 연속 액션 벡터**와 상태 정보를 자동 기록한다.

### 구조

각 프레임의 액션 토큰은 다음 정보를 포함한다:

- **frame / time**: 프레임 번호와 경과 시간(초)
- **state**: Expert Agent 상태 머신의 현재 상태
- **loader**: 로더의 위치(x, z), 회전각, 버킷 각도, 리프트 높이
- **actions**: 4D 연속 액션 벡터
  - `steering` [-1, 1]: 좌/우 조향
  - `throttle` [0, 1]: 전/후진
  - `bucket` [-1, 1]: 버킷 상/하
  - `lift` [-1, 1]: 리프트 상/하
- **remaining / collected**: 남은/수거된 레고 개수

### 예시 (example-data/actions-*.jsonl)

```json
{
  "frame": 32,
  "time": 1.067,
  "state": "TRANSPORTING",
  "loader": {
    "x": 4.152,
    "z": 5.214,
    "rotation": 0.82,
    "bucketAngle": 0.3,
    "liftHeight": 0.8
  },
  "actions": {
    "steering": -0.45,
    "throttle": 0.6,
    "bucket": 0,
    "lift": 0
  },
  "remaining": 19,
  "collected": 1
}
```

### 에피소드 통계 (example-data 기준)

- **프레임 수**: 에피소드당 ~5,500 프레임 (약 183초, 30fps)
- **상태 전이 사이클**: SCANNING → APPROACHING → LOWERING_BUCKET → SCOOPING → LIFTING → TRANSPORTING → DUMPING → (반복)
- **수거 완료**: 20/20 블록 전량 수거
- **에피소드 수**: 3개 영상 × 9개 카메라 시점 = 총 18개 액션 파일

## 다중 시점 전략

동일한 액션 시퀀스를 여러 시점에서 동시에 녹화한다:

- **1인칭 (Ego)**: 로더 운전석 시점 — 실제 배포 시점, action과 직결
- **3인칭 고정**: 축사 코너 CCTV 시점 — 전체 공간 이해, spatial reasoning
- **3인칭 추적**: 로더를 따라다니는 카메라 — object-centric representation
- **Bird's Eye**: 위에서 내려다보는 평면도 — planning, 경로 시각화
- **랜덤 시점**: 무작위 위치/각도 — view-invariant feature 학습

### 왜 다중 시점인가?

- **Robust한 representation** 형성
- **Sim-to-real transfer** 개선
- **Cross-view Verification**: 1인칭에서 성공으로 보여도 3인칭에서 충돌 감지 시 재시도

## 이론적 기반

### NL2SpaTiaL + 다중 시점

```
자연어: "로더를 소똥 더미 가까이로 이동"
    ↓
SpaTiaL: closeTo(loader, manure_pile)
    ↓
1인칭: 더미가 화면 중앙으로 이동
3인칭: 로더-더미 거리 감소
2D:    두 점이 가까워짐
```

모든 시점에서 같은 spatial predicate가 만족되어야 함 → **Consistency Loss**

### VLA-SCT Self-Correction

- 다중 시점에서 동시에 성공/실패 판정
- 궤적 평가 (효율성/안정성/부드러움)
- 실패 감지 및 자동 재시도

## 5-Agent Multi-VM System

5개 AI 에이전트가 GCP VM에서 Discord로 협업한다:

- **Watcher** (GPT-4o, n2-standard-8, asia-northeast3-a): 지휘자. 타임라인 관리, 10분 간격 상태 체크, 페이즈 전환 결정
- **Developer** (Claude Opus 4.6, n2-standard-8, asia-northeast3-a): 시뮬레이터 코드 개발, headless 렌더링, 배치 생성
- **DomainExpert** (n2-standard-4, asia-northeast3-a): FMEA 방법론 기반 롱테일/에지케이스 식별, SPS 우선순위 기반 시나리오 JSON config 생성
- **Training** (A100 Spot, us-central1-a): ACT 모델 훈련, 체크포인트 관리
- **Evaluation** (n2-standard-4, asia-northeast3-a): 데이터/모델 품질 검증, 실패 분석

### Handoff Chain (GCS Bucket: `gs://ralphton-handoff/`)

```
Watcher → Developer: ssot/
Developer → Training: dataset/ (episodes/ → LeRobot HDF5)
Training → Evaluation: checkpoints/
Evaluation → DomainExpert: reports/
DomainExpert → Developer: scenarios/
```

### Communication Protocol

- 채널: Discord `#claw-dev-chat`
- 메시지 형식: `[STATUS] message` (STATUS: REPORT, REQUEST, DONE, BLOCKED, HANDOFF)
- 에이전트 간 멘션 필수: `@agent_name`

## 롱테일 케이스 (Edge Cases)

- **장애물**: 소가 갑자기 앞으로 걸어옴, 다른 작업자 출현
- **환경**: 바닥 미끄러움, 조명 어두움, 비/눈
- **장비**: 버킷 가득 참, 유압 느림, 조향 이상
- **공간**: 좁은 코너, 문 닫힘, 기둥 사이 통과
- **복합**: 소 + 미끄러운 바닥 동시 발생

## 출력 데이터 형식

각 시나리오 실행 후 생성되는 파일:

```
scenario_001/
├── video_ego.mp4           # 1인칭 시점
├── video_fixed.mp4         # 3인칭 고정
├── video_follow.mp4        # 3인칭 추적
├── video_topdown.mp4       # Bird's eye
├── metadata.json           # 시나리오 메타데이터
├── actions.jsonl           # 프레임별 액션 토큰
└── spatial.jsonl           # 프레임별 SpaTiaL 상태
```

## Quick Start

```bash
# 의존성 설치
npm install

# 환경변수 설정
cp .env.example .env  # 토큰 등 입력

# 시뮬레이터 (브라우저)
open SSOT/reference/loader-simulator.html

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
├── example-data/              # 예시 에피소드 (영상 + 액션 토큰)
├── claw-bot.js                # Discord 봇 팩토리
├── *-bot.js                   # 각 에이전트 봇 인스턴스
├── scripts/                   # 유틸리티 스크립트
└── vm-configs/                # GCP VM 설정
```

## 기술 스택

- **3D 렌더링**: Three.js + headless-gl
- **물리 엔진**: cannon-es
- **비디오 인코딩**: FFmpeg
- **시나리오 정의**: JSON
- **학습 프레임워크**: PyTorch (ACT / LeRobot)
- **오케스트레이션**: AI Agent 5개 (Discord 기반 자율 협업)

## Phase Timeline

- **Phase 0** (pre-20:00): 인프라 셋업, VM 연결 확인
- **Phase 1** (20:00-22:00): 시뮬레이터 구축, 1개 에피소드 완성
- **Phase 2** (22:00-23:30): 배치 생성 50+개, LeRobot HDF5 변환
- **Phase 3** (23:30-03:00): ACT 모델 훈련 (A100)
- **Phase 4** (03:00-06:00): Humanoid RL (병렬)
- **Phase 5** (06:00-08:00): 문서화 + 데모

## 목표

1. **데이터 생성**: 10,000+ 시나리오, 50,000+ 비디오 (시나리오당 5개 시점)
2. **학습**: Multi-view VLA 모델, SpaTiaL consistency + Self-correction
3. **평가**: Sim 성공률 95%+, Real 성공률 80%+
4. **배포**: 실제 농업용 로더에 적용
