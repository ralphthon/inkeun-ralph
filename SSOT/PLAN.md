# Ralphton 마스터 플랜

> **목표**: Physical AI 파이프라인 자동화 — 로더가 레고를 자율적으로 치우는 시뮬레이션 → ACT 학습
> **플랜시간**: 2/28 15:00 ~ 3/1 12:00 (21시간)
> **야간 집중**: 20:00 ~ 08:00 (12시간)

플랜시간이 끝나면 주최측이 정한 repo에 이 프로젝트의 내용을 initial commit하고
자율적으로 작동하게 한다.
각 VM을 만들어서 밤새 작동하게 할거다.
이 레포는 로컬 노트북에 위치할거고, initial trigger를 걸어서 각 VM에 명령을 내릴건데,
VM들은 모두 디스코드에서 대화를 할거야.

**Watcher VM** (n2-standard-8, asia-northeast3-a) → 지휘자. 타임라인 관리, Phase 전환, 장애 대응
**DomainExpert VM** (n2-standard-4, asia-northeast3-a) → 도메인 지식 기반 롱테일 식별 및 시나리오 JSON config 생성
**Developer VM** (n2-standard-8, asia-northeast3-a) → 시뮬레이터 개발, headless 렌더링, 배치 비디오 생성
**Training VM** = ralphton-a100 (A100 40GB Spot, us-central1-a) → LeRobot 변환 + ACT 학습 + checkpoint 관리
**Evaluation VM** (n2-standard-4, asia-northeast3-a) → 데이터 품질 검증, 모델 평가, 피드백 루프 생성

initial trigger를 하면 이 레포를 살펴보고 각 VM에게 `SSOT/{에이전트명}/INSTRUCTIONS.md`를 전송한다.
각 VM은 에이전트 역할을 하며, 서로 디스코드 `#claw-dev-chat`에서 `@멘션` 기반으로 대화한다.

**전송 방식**: initial trigger 스크립트가 GCS 버킷(`gs://ralphton-handoff/ssot/`)에 SSOT 폴더를 업로드하고, 각 VM의 Discord 봇을 시작시킨다. 각 에이전트는 버킷에서 자신의 INSTRUCTIONS.md를 다운로드하여 실행한다.

## 대화를 하는 규칙

### 기본 통신 프로토콜

- **채널**: Discord `#claw-dev-chat` (Guild: `1477168227384561758`)
- **호출 방식**: 반드시 `@멘션`으로 상대를 지정 (멘션 없는 메시지는 무시됨)
- **1:1 대화**: 한 번에 한 에이전트만 멘션 (멀티멘션 금지 — 혼선 방지)
- **루프 방지**: 응답에 상대를 재멘션하지 않음. 추가 작업이 필요할 때만 명시적으로 멘션

### 메시지 구조

모든 에이전트는 다음 형식으로 메시지를 작성:

```
[상태] 내용

- 상태: REPORT / REQUEST / DONE / BLOCKED / HANDOFF
- 내용: 자유 형식, 핵심만 간결하게
```

- **REPORT**: 진행 상황 보고 (Watcher에게)
- **REQUEST**: 다른 에이전트에게 작업 요청
- **DONE**: 단계 완료 알림 + 산출물 경로
- **BLOCKED**: 막힌 상황 + 원인 설명
- **HANDOFF**: 다음 에이전트에게 작업 인계 + 필요 정보 전달

### 역할별 행동 규칙

**Watcher (지휘자, GPT-4o)**
- Phase 타임라인에 따라 각 에이전트에게 작업 지시
- 10분마다 진행 상황 체크 (`@Developer 상태 보고해`)
- BLOCKED 수신 시 대안 제시 또는 다른 에이전트에게 지원 요청
- DONE 수신 시 다음 Phase 트리거

**Developer (개발자, Claude Opus 4.6)**
- 코드 작성, 빌드, 테스트 수행
- 산출물 생성 시 경로를 명시 (`~/output/episode_001/`)
- 에러 발생 시 로그 첨부하여 BLOCKED 보고

**DomainExpert (도메인 전문가)**
- 에지케이스 시나리오 목록 생성
- Developer에게 시나리오 파라미터 전달 (레고 개수, 배치, 장애물)

**Training (학습 에이전트)**
- Developer로부터 HANDOFF 받으면 데이터 검증 → 학습 시작
- loss/epoch 주기적으로 REPORT
- checkpoint 저장 시 경로 공유

**Evaluation (평가 에이전트)**
- Training의 checkpoint로 평가 실행
- 성공률, 실패 원인 분석 후 REPORT
- 개선 필요 시 DomainExpert에게 REQUEST (추가 시나리오)

### 공유 버킷 (HANDOFF 저장소)

- **버킷**: `gs://ralphton-handoff`
- **리전**: `asia-northeast3` (서울, VM과 동일)
- **접근**: 모든 VM에서 읽기/쓰기 가능 (`gcloud storage` 사용)

**디렉토리 구조:**

```
gs://ralphton-handoff/
├── ssot/                    ← PLAN.md, 레퍼런스 파일 (초기 트리거 시 업로드)
├── scenarios/               ← DomainExpert → Developer (시나리오 파라미터)
├── episodes/                ← Developer → Training (시뮬레이션 산출물)
│   ├── episode_001/
│   │   ├── ego.mp4
│   │   ├── birds_eye.mp4
│   │   ├── follow.mp4
│   │   ├── actions.jsonl
│   │   └── metadata.json
│   └── ...
├── dataset/                 ← Developer → Training (LeRobot HDF5 변환 후)
├── checkpoints/             ← Training → Evaluation (학습 checkpoint)
├── reports/                 ← Evaluation → Watcher (평가 리포트)
└── logs/                    ← 각 에이전트 작업 로그
```

**사용 규칙:**
- 산출물은 반드시 버킷에 업로드 후 DONE/HANDOFF 메시지에 버킷 경로 명시
- 로컬 경로(`~/output/...`) 대신 버킷 경로(`gs://ralphton-handoff/episodes/...`) 사용
- 대용량 파일은 디스코드에 올리지 않음 — 버킷 경로만 공유

**예시:**
```
[DONE] Phase 1 시뮬레이터 완성. 에피소드 5개 생성 완료.
경로: gs://ralphton-handoff/episodes/episode_001~005/
메타데이터: gs://ralphton-handoff/episodes/batch_001_meta.json
```

### 작업 인계 (HANDOFF) 체인

```
Watcher → Developer: Phase 시작 지시 + gs://ralphton-handoff/ssot/
Developer → Training: DONE + gs://ralphton-handoff/dataset/
Training → Evaluation: DONE + gs://ralphton-handoff/checkpoints/
Evaluation → DomainExpert: REQUEST + gs://ralphton-handoff/reports/ (실패 패턴)
DomainExpert → Developer: REQUEST + gs://ralphton-handoff/scenarios/ (추가 시나리오)
```

### 금지 사항

- 멘션 없이 메시지 보내기 (무시됨)
- 응답에 상대를 자동 재멘션 (무한 루프 위험)
- 한 메시지에 여러 에이전트 동시 멘션
- SSOT 파일 직접 수정 (Watcher만 SSOT 업데이트 권한)
- 산출물을 버킷에 올리지 않고 DONE 보고
- 로컬 경로만 공유 (다른 VM에서 접근 불가)

---

## 목표

기존 레고 치우기 게임(클릭 기반)을 **로더가 자율적으로 레고를 치우는 시뮬레이터**로 발전시키고, 에지케이스를 식별해서 계속적으로 다양한 비디오 데이터를 생성하고 획득하여 이를 이용해 ACT 모델을 학습해 **로더의 자율 레고 수거 행동을 시뮬레이션에서 재현**하는 것이 최종 목표다.

- **레퍼런스**: `SSOT/reference/lego-cleanup-game.html` — Three.js 기반 방+레고 환경
- **변경점**: 사람 클릭 → 로더(차량형 로봇)가 자율 주행하며 레고 수거
- **로더 액션**: steering, throttle, bucket(삽), lift(리프트) — 연속 4DoF
- **데이터 출력**: 다시점 비디오(MP4) + 연속 액션(JSONL) → LeRobot HDF5 → ACT 학습

레퍼런스 게임에서 재활용하는 것:
- 방 환경 (바닥, 벽, 창문, 가구)
- 레고 블록 생성 (크기/색상/분포)
- Three.js 렌더링 파이프라인

새로 만들어야 하는 것:
- 로더 모델 + cannon-es 물리
- Expert Agent (상태 머신: 스캔→접근→수거→운반→배치)
- 다시점 카메라 시스템 (ego, birds_eye, follow)
- headless 렌더링 (xvfb-run + headless-gl)
- 액션 데이터 기록기 (매 프레임 JSONL)

---

## 인프라 현황

- **ralphton-a100** (us-central1-a) — A100 40GB Spot, **TERMINATED**
  - SSH: `gcloud compute ssh ralphton-a100 --project=ralphton --zone=us-central1-a`
  - PyTorch 2.7, CUDA 12.8
  - 용도: ACT 학습 (Phase 3)

- **ralphton-developer** (asia-northeast3-a) — n2-standard-8, **RUNNING** (34.47.121.197)
  - 용도: 개발자 OpenClaw (Claude) + 시뮬레이터 배치 생성
  - SSH: `gcloud compute ssh ralphton-developer --project=ralphton --zone=asia-northeast3-a`

- **ralphton-watcher** (asia-northeast3-a) — n2-standard-8, **RUNNING** (34.158.215.255)
  - 용도: 감시자 OpenClaw (Codex)
  - SSH: `gcloud compute ssh ralphton-watcher --project=ralphton --zone=asia-northeast3-a`

- **ralphton-domain-expert** (asia-northeast3-a) — n2-standard-4, **미생성**
  - 용도: 도메인 전문가 에이전트 — 시나리오 생성 + 에지케이스 식별
  - SSH: `gcloud compute ssh ralphton-domain-expert --project=ralphton --zone=asia-northeast3-a`
  - 생성 명령:
    ```bash
    gcloud compute instances create ralphton-domain-expert \
      --project=ralphton --zone=asia-northeast3-a \
      --machine-type=n2-standard-4 --boot-disk-size=50GB \
      --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud
    ```

- **ralphton-evaluator** (asia-northeast3-a) — n2-standard-4, **미생성**
  - 용도: 평가 에이전트 — 데이터 검증 + 모델 평가 + 피드백 루프
  - SSH: `gcloud compute ssh ralphton-evaluator --project=ralphton --zone=asia-northeast3-a`
  - 생성 명령:
    ```bash
    gcloud compute instances create ralphton-evaluator \
      --project=ralphton --zone=asia-northeast3-a \
      --machine-type=n2-standard-4 --boot-disk-size=50GB \
      --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud
    ```

---

## 핵심 결정사항

- **시뮬레이터**: 레고 치우기 게임 레퍼런스 기반, 로더가 자율 수거
- **모델**: ACT 우선 (VLA는 학습 시간 이슈, 추후 확장)
- **실행 환경**: GCP VM 기반 (로컬 아님)
- **자율 실행**: 5-에이전트 체제 (Watcher + DomainExpert + Developer + Training + Evaluation) + Discord + GCS 버킷
- **데이터**: 비디오 + 연속 액션 데이터 (JSONL) 필수 — 비디오만으론 부족
- **에지케이스**: AI 추천으로 생성 (FMEA 파이프라인은 미구축)
- **게임 퀄리티**: 3D 애셋 참조로 향상

---

## 기술 교훈 (lessons-learned.md에서)

시뮬레이터 개발 시 반드시 적용할 것:
- 로더 회전은 물리엔진 대신 kinematic 제어 (피치/롤 고정)
- 매 프레임 `body.angularVelocity.set(0,0,0)` 으로 물리 회전 관성 제거
- CANNON↔THREE API 차이 확인 (특히 `setFromEuler`)
- 액션 전환 시 모든 속도/회전 변수 명시적 리셋
- `threshold > 2 x angular_speed x dt` 확인 (진동 방지)
- 복합 액션(forward+turn) 반드시 포함, 비례 조향
- 카메라 초기 위치 = 타겟 위치로 세팅
- headless-gl 모델 호환성 사전 테스트
- 학습용 해상도 640x480 (모델 입력 224x224로 리사이즈)

---

## 사전 조건 (Phase 0) — 20:00 전 완료

- [ ] **OpenClaw 듀얼 시스템 세팅 확인** — developer/watcher VM에 OpenClaw 동작 여부
- [ ] **Discord 봇 연결 확인** — 채팅방에서 두 봇이 대화 가능한지
- [ ] **레퍼런스 게임 VM 전송** — lego-cleanup-game.html을 developer VM에 배치
- [ ] **Node.js + headless-gl 환경 확인** — developer VM에서 headless 렌더링 가능 여부

---

## Phase 1: 레고 로더 시뮬레이터 구축 — 20:00~22:00

**목표**: 레퍼런스 게임을 기반으로 로더 자율 수거 시뮬레이터 완성

### 1a. 환경 변환 (20:00~20:30)
- 레퍼런스 게임의 방+레고 환경을 headless Node.js로 포팅
- Three.js + headless-gl + cannon-es 세팅
- 브라우저 의존성 제거 (OrbitControls, DOM 등)

### 1b. 로더 구현 (20:30~21:00)
- 로더 모델 (BoxGeometry 기반 또는 GLB)
- cannon-es 물리 바디 (kinematic 회전 제어)
- 액션 공간: steering(-1~1), throttle(-1~1), bucket(-1~1), lift(-1~1)
- lessons-learned 교훈 모두 적용

### 1c. Expert Agent (21:00~21:30)
- 상태 머신: SCANNING → APPROACHING → LOWERING_BUCKET → SCOOPING → LIFTING → TRANSPORTING → DUMPING
- 가장 가까운 레고 탐색 → 비례 조향으로 접근 → 버킷 내리기 → 수거 → 박스로 운반
- 연속 액션 출력 (매 프레임)

### 1d. 데이터 기록 + 다시점 카메라 (21:30~22:00)
- 카메라: ego(로더 시점), birds_eye(천장), follow(3인칭)
- 매 프레임 기록:
  - 비디오: 3시점 PNG → FFmpeg MP4
  - 액션: steering, throttle, bucket, lift (JSONL)
  - 상태: 로더 위치/방향, 남은 레고, 수거 레고
- 메타데이터: metadata.json (시나리오 설정, 결과)

**성공 기준**: 1개 에피소드가 headless로 완주되고, 3시점 비디오 + 액션 JSONL이 동기화되어 저장됨

**의존**: Phase 0 (VM 환경)

---

## Phase 2: 배치 생성 + LeRobot 변환 — 22:00~23:30

**목표**: 시나리오 50~100개 배치 생성 + LeRobot HDF5 변환

### 2a. 배치 생성 시작 (22:00~22:30)
- 시나리오 랜덤화: 레고 개수(10~50), 위치, 색상, 방 레이아웃
- 배치 스크립트 실행 (xvfb-run 백그라운드)
  ```bash
  nohup xvfb-run node batch-generate.js --count 100 > batch.log 2>&1 &
  ```
- 처음 5개 시나리오 생성 확인 후 백그라운드 전환

### 2b. LeRobot 변환 (22:30~23:00)
- 생성된 시나리오의 비디오(MP4) + 액션(JSONL) → LeRobot HDF5 + Parquet
- 변환기 구현 또는 기존 변환기 활용
- 샘플 5개 검증 (프레임 동기화, 액션 범위)

### 2c. 데이터 품질 검증 + A100 전송 (23:00~23:30)
- 프레임 수 일치 확인 (비디오 프레임 == 액션 타임스텝)
- 액션 분포 시각화 (steering, throttle, bucket, lift)
- 데이터를 A100 VM으로 scp 전송

**성공 기준**: 최소 50개 에피소드가 LeRobot HDF5로 변환되고, A100 VM에 전송됨

**의존**: Phase 1 (시뮬레이터 완성)

---

## Phase 3: ACT 학습 — 23:30~03:00

**목표**: ACT 모델 파일럿 학습 → 평가 → 풀 데이터 학습

### 3a. LeRobot 환경 세팅 (23:30~00:00)
- A100 VM 시작: `gcloud compute instances start ralphton-a100 --project=ralphton --zone=us-central1-a`
- SSH 접속 후 LeRobot 설치/설정
- ACT config 작성:
  - chunk_size: 20
  - batch_size: 64
  - lr: 1e-4
  - backbone: ResNet18
  - action_dim: 4 (steering, throttle, bucket, lift)
  - camera_names: [ego] (또는 [ego, birds_eye])

### 3b. 파일럿 학습 (00:00~02:00)
- 현재까지 생성된 에피소드로 ACT 학습 시작
- checkpoint 주기: 50 epoch마다 (Spot 선점 대비)
- loss 커브 모니터링 (wandb 또는 텐서보드)

### 3c. 평가 + 추가 학습 (02:00~03:00)
- 학습된 policy를 시뮬레이터에서 실행 (가능한 경우)
- loss 감소 추세 확인
- 배치 생성 추가 완료분으로 데이터 보강 → 재학습 (백그라운드)

**성공 기준**: loss가 지속적으로 감소

**의존**: Phase 2 (LeRobot 데이터), A100 VM 정상 동작

**리스크**: Spot 인스턴스 선점 → checkpoint에서 재개

---

## Phase 4: 휴머노이드 RL — 03:00~06:00

**목표**: PPO 구현 + standing policy + walking policy 학습

### 4a. PPO 구현 (03:00~04:00)
- 기존 물리엔진+래그돌 코드 위에 PPO 알고리즘 구현
- 관측 공간: 관절 각도, 각속도, body orientation, 접촉 정보
- 행동 공간: 관절 토크 (연속)
- 네트워크: MLP (256, 256) actor-critic

### 4b. Reward 설계 (04:00~04:30)
- **Standing reward**:
  - 머리 높이 유지 보상
  - body 수직 유지 보상 (roll/pitch 패널티)
  - 에너지 효율 패널티 (관절 토크 최소화)
  - 생존 보상 (넘어지지 않으면 +1/step)
- **Walking reward** (standing 안정화 후):
  - 전진 속도 보상
  - 측면 이동 패널티
  - 발 접촉 패턴 (교대 보행)

### 4c. Standing 학습 (04:30~05:15)
- PPO로 standing policy 학습
- 수백만 스텝 (CPU 기반, ralphton-developer VM 활용)
- 10초 이상 서있기 달성 시 성공

### 4d. Walking 학습 (05:15~06:00)
- standing policy 기반으로 walking reward 추가
- curriculum learning: 느린 속도 → 빠른 속도
- 5m 이상 직선 보행 달성 시 성공

**성공 기준**: standing 10초 이상 + walking 5m 이상

**의존**: 별도 트랙 (Phase 1-3과 독립). ACT 학습이 A100에서 백그라운드로 돌아가는 동안 CPU로 진행.

---

## Phase 5: 문서화 + 데모 — 06:00~08:00

### 5a. 결과 정리 (06:00~06:45)
- 각 Phase 성과 요약
- ACT 학습 곡선 캡처
- 휴머노이드 RL 학습 곡선 캡처
- 성공/실패 분석

### 5b. 데모 영상 (06:45~07:30)
- 로더 레고 치우기 시뮬레이터 실행 영상 (Expert Agent)
- ACT 학습된 policy 실행 영상 (가능한 경우)
- 휴머노이드 standing/walking 영상
- 배치 생성 과정 타임랩스 (선택)

### 5c. 다음 단계 (07:30~08:00)
- VLA 확장 계획 (언어 지시 추가)
- 에지케이스 생성기 설계 (강아지, 아이 등 동적 장애물)
- Sim-to-Real 전이 전략 (D2E VAPT)
- OpenClaw 듀얼 시스템 개선점

**성공 기준**: 데모 영상 2개 이상 + 결과 문서 완성

---

## 참고 문서

- `SSOT/reference/lego-cleanup-game.html` — 레퍼런스 게임 (Three.js 방+레고)
- `simulation-plan.md` — D2E 프레임워크 전체 방법론
- `hackathon-plan.md` — OpenClaw 듀얼 시스템 아키텍처
- `lessons-learned.md` — 시뮬레이터 기술 교훈 8가지
- Obsidian 참조:
  - [[20260228 랄프톤 오픈클로와 텔레그램으로 작성한 계획]]
  - [[20260228 랄프톤 모델선정가이드]]
  - [[20260228 랄프톤 학습데이터 생성시 주의할점]]

---

## 병렬 실행 타임라인 (5-에이전트 매핑)

```
시간    Watcher         DomainExpert        Developer           Training            Evaluation
20:00   Phase 시작 지시  시나리오 v1 생성     #### 환경 변환
20:30   모니터링         대기                #### 로더 구현
21:00   상태 체크        대기                #### Expert Agent
21:30   모니터링         대기                #### 데이터 기록
22:00   Phase 2 트리거   시나리오 v2 준비     #### 배치 생성 시작
22:30   모니터링         대기                #### LeRobot 변환      대기
23:00   Phase 3 트리거   대기                #### 검증              데이터 수신 대기     데이터 검증 시작
23:30   상태 체크        대기                .... 추가 배치         #### A100 세팅       #### 품질 리포트
00:00   모니터링         대기                .... 추가 배치         #### 파일럿 학습      #### 프레임 검증
01:00   상태 체크        대기                .... 추가 배치         #### 학습 중...       대기
02:00   Phase 평가 지시  피드백 반영          .... 추가 시나리오     #### 평가+추가학습    #### 모델 평가
03:00   Phase 4 트리거   추가 시나리오        #### PPO 구현         .... 백그라운드       #### 평가 리포트
04:00   모니터링         대기                #### Reward            ....                피드백 → DomainExpert
04:30   상태 체크        시나리오 v3          #### Standing          ....                대기
05:15   모니터링         대기                #### Walking           ....                대기
06:00   Phase 5 트리거   최종 정리            #### 결과 정리         최종 checkpoint      최종 평가
07:00   최종 점검        대기                #### 데모 영상         대기                대기
08:00   종료 보고        종료                #### 완료              종료                종료
```

- `####` = 활성 작업, `....` = 백그라운드 실행, `대기` = 다음 지시 대기
- Watcher는 전 시간대 활성 (10분 간격 체크)
- DomainExpert ↔ Evaluation 피드백 루프: 02:00~04:00 사이 작동
