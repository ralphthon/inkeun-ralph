# Ralphton 해커톤 — 원래 계획

> **목표**: Physical AI 파이프라인 자동화 — 5개 AI 에이전트가 GCP VM에서 Discord로 자율 협업하며, LEGO 수거 시뮬레이터 구축 → 학습 데이터 생성 → ACT 모델 훈련을 반복
>
> **기간**: 2/28 (금) 15:00 ~ 3/1 (토) 12:00 (21시간)
>
> **핵심 성공 기준**: 전체 파이프라인 루프 10회 이상 완주, 매 사이클 개선 측정, 최종 시연 영상 제출

---

## 1. 프로젝트 개요 — D2E (Desktop to Embodied AI)

"AI가 게임을 만들고, 게임이 학습 데이터를 생성한다"는 D2E 프레임워크 기반.

- **시뮬레이터**: Three.js + cannon-es (LLM 코드 생성에 친화적)
- **로더 액션 스페이스**: 4D continuous — steering, throttle, bucket, lift (각 [-1, 1])
- **Expert Agent**: 7개 상태 머신 (SCANNING → APPROACHING → LOWERING_BUCKET → SCOOPING → LIFTING → TRANSPORTING → DUMPING)
- **카메라**: ego, birds_eye, follow 3시점 동시 녹화
- **학습 해상도**: 640x480 → 224x224 (모델 입력)
- **모델**: ACT (Action Chunking with Transformers) — chunk_size 20, ResNet18 backbone

---

## 2. 5-에이전트 멀티 VM 시스템

### 에이전트 구성

- **Watcher** (GPT-5.2 Pro, n2-standard-8, 서울)
  - 역할: 지휘자. 타임라인 관리, 5분 간격 상태 체크, Phase 전환 결정, 인프라 스케일링
  - 원칙: "코드를 작성하지 않는다. 지시하고, 모니터링하고, 판단하고, 스케일링한다."

- **Developer** (Claude Opus 4.6, n2-standard-8, 서울)
  - 역할: 시뮬레이터 코드 개발, headless 렌더링, 배치 생성, LeRobot HDF5 변환

- **DomainExpert** (GPT-5.2 Pro, n2-standard-4, 서울)
  - 역할: FMEA(Failure Mode and Effects Analysis) 기반 시나리오 설계
  - 32개 고장모드 식별, SPS(Severity × Occurrence / Difficulty) 점수로 우선순위 결정
  - Tier 1 (SPS>20) 4개, Tier 2 (SPS 5~20) 23개, Tier 3 (SPS<5) 5개

- **Training** (Claude Opus 4.6, A100 40GB Standard, 미국)
  - 역할: ACT 모델 학습, checkpoint 관리

- **Evaluation** (Claude Opus 4.6, n2-standard-4, 서울)
  - 역할: 데이터 품질 검증, 모델 평가, 실패 패턴 분석, 피드백 루프 생성

### 통신 프로토콜

- **채널**: Discord `#claw-dev-chat`
- **메시지 형식**: `[STATUS] message` (REPORT / REQUEST / DONE / BLOCKED / HANDOFF)
- **멘션 규칙**: 반드시 `<@USER_ID>` 형식 사용 (텍스트 @이름은 알림 전달 안 됨)
- **핸드오프 체인**: GCS 버킷 `gs://ralphton-handoff/` 경유

### 3중 안전장치

```
[1층] VM 내부 systemd — 프로세스 죽음 → 5초 후 자동 재시작
[2층] VM 내부 watchdog timer — 1분마다 서비스 상태 체크
[3층] 로컬 Mac 크론잡 — 3분마다 모든 VM gcloud 체크 → 자동 복구
```

---

## 3. 타임라인 — 10+ 사이클 프론트로딩 설계

핵심 전략: **"완벽한 1회보다 빠른 10회가 압도적으로 낫다."** (Vertical Slice First)

### Phase 0-1: 시뮬레이터 구축 (20:00 ~ 21:30)

- 레퍼런스 게임(lego-cleanup-game.html)을 headless Node.js로 포팅
- 로더 모델 + kinematic 물리 + Expert Agent 상태 머신 구현
- 다시점 카메라 시스템 + 매 프레임 데이터 기록기
- **성공 기준**: 1개 에피소드 headless 완주 + 비디오 + 액션 JSONL 동기화

### Tier 1: Smoke Test (21:30 ~ 23:00) — 파이프라인 증명

- **Cycle 1** (30분): 5개 에피소드, 10 epochs — "파이프라인이 돌아간다"만 증명
- **Cycle 2** (30분): 10개 에피소드, 20 epochs — 데이터 형식 안정화
- **Cycle 3** (30분): 15개 에피소드, 30 epochs — 첫 success rate 측정

### Tier 2: Rapid Iteration (23:00 ~ 01:30) — 피드백 루프 가동

- **Cycle 4** (45분): 25개 에피소드, 50 epochs — DomainExpert 피드백 첫 반영
- **Cycle 5** (45분): 40개 에피소드, 50 epochs — 시나리오 다양성 확대
- **Cycle 6** (60분): 50개 에피소드, 80 epochs — 데이터 품질 리포트

### Tier 3: Deep Training (01:30 ~ 05:00) — 본격 학습

- **Cycle 7** (70분): 75개 에피소드, 100+ epochs
- **Cycle 8** (70분): 100개 에피소드, 150+ epochs — 에지케이스 집중
- **Cycle 9** (70분): 100+개 에피소드, 200+ epochs — 최고 품질 데이터

### Tier 4: Polish (05:00 ~ 07:00) — 최종 다듬기

- **Cycle 10** (60분): 최고 품질 데이터 혼합, 최장 시간 학습, 시연 영상 생성
- **Cycle 11+** (여유분): 추가 사이클 또는 Humanoid RL

### Demo + Wrap-up (07:00 ~ 08:00)

- 시연 영상 최종 확인 + 전체 성과 보고서

---

## 4. 파이프라인 병렬화 전략

**"기다리는 시간 = 낭비. 항상 다음 사이클을 준비하라."**

```
시간축 →

Cycle N:   [데이터생성] → [변환] → [훈련] → [평가]
Cycle N+1:                  [시나리오설계] → [데이터생성] → [변환] → [훈련] → ...
```

- Training이 Cycle N을 학습하는 동안 → Developer가 Cycle N+1 데이터 생성
- Evaluation이 Cycle N을 평가하는 동안 → DomainExpert가 Cycle N+1 시나리오 개선
- 에이전트가 idle이면 즉시 다음 사이클 준비 작업 할당

---

## 5. ACT 학습 Config (계획)

```yaml
policy:
  name: act
  chunk_size: 20          # 20프레임(0.67초) 앞을 한번에 예측
  n_action_steps: 20

training:
  batch_size: 64
  lr: 1e-4
  epochs: 500
  seed: 42
  save_checkpoint_every: 50

model:
  backbone: resnet18
  transformer_layers: 6
  action_dim: 4           # steering, throttle, bucket, lift

dataset:
  camera_names: [ego]
  image_size: [224, 224]

observation:
  state_dim: 4            # loader_x, loader_z, loader_rotation, legos_remaining
```

---

## 6. 데이터 생성 계획

### 목표: 1,000 에피소드

- **일반 케이스**: 350개 (35%) — Domain Randomization 범위 내 변형
- **Tier 1 롱테일**: 300개 (30%) — 바닥색 레고, 저조도, 벽밀착, 극분산
- **Tier 2 롱테일**: 250개 (25%) — 23개 고장모드 각 5~15개 변형
- **Tier 3 롱테일**: 100개 (10%) — Domain Randomization 근사

### DomainExpert의 FMEA 기반 시나리오 설계

32개 고장모드를 5개 카테고리로 분류:

- **A. 환경 위험**: 바닥색 레고, 그림자, 저조도, 바닥 경사, 좁은 공간, 반사 바닥, 잡동사니
- **B. 안전 위협**: 절벽, 바닥 구멍, 애완동물, 아이, 금지 물체, 경사로
- **C. 수거 조작**: 벽밀착, 밀집 클러스터, 급회전 낙하, 초대형/초소형 레고, 부분 가림, 바닥 밀착, 수거함 만원
- **D. 탐색/경로**: 코너 고착, 극분산, 최원거리 시작점, 예상외 장애물
- **E. 동적 환경**: 조명 변화, 레고 위치 변경, 문 열림, 바닥 함몰

### Tier 1 고장모드 (SPS > 20, 반드시 구현)

- FM-D02 레고 극분산 — SPS 24.0
- FM-A03 저조도 환경 — SPS 24.0
- FM-A01 바닥색 동일 레고 — SPS 21.0
- FM-C01 벽/코너 밀착 레고 — SPS 20.0

### Domain Randomization (모든 시나리오 공통 적용)

- **시각**: 색상 jitter ±30%, 바닥 텍스처 5종 랜덤, 조명 강도/각도 랜덤, 카메라 FOV ±5도
- **물리**: 바닥 마찰 [0.2, 0.8], 버킷 마찰 [0.3, 0.9], 레고 질량 ±20%, 모터 지연 [0, 30]ms
- **시나리오**: 레고 위치 uniform random, 레고 수 ±30%, 로더 시작 위치/방향 랜덤

---

## 7. 평가 체계

### 루프별 평가 깊이

- **Loop 1**: 오프라인 평가만 (20분 이내) — Loss, MSE, 분포 분석
- **Loop 2~3**: 오프라인 + 시뮬레이터 실행 평가 (30분 이내) — 실제 수거 성공률 측정

### 시뮬레이터 실행 평가 지표

- **수거 성공률**: 수거한 레고 / 전체 레고 (목표: Loop 3에서 일반 케이스 70%+)
- **에피소드 완주율**: 타임아웃(120초) 전 완료 비율
- **효율성**: 수거당 소요 시간, 불필요 이동 비율
- **장애물 회피**: 경계 침범 횟수, 가구 충돌 횟수, 회피 성공률

### 실패 유형 분류 (Failure Taxonomy)

- **F1**: 목표 도달 실패 (경로 계획 실패)
- **F2**: 수거 실패 (조작 실패)
- **F3**: 운반 실패 (위치 인식 실패)
- **F4**: 진동/루프 (제자리 회전)
- **F5**: 충돌/끼임
- **F6**: 경계 이탈

---

## 8. 인프라 스케일링 전략

**"GCP 크레딧은 충분하다. 병목이 보이면 VM을 늘려라. 주저하지 마라."**

### 스케일링 판단 기준

- 에피소드 생성이 병목 → Developer VM 추가 (최대 3대)
- 훈련이 병목 → GPU VM 추가 또는 epochs 축소
- 평가가 병목 → Evaluator VM 추가
- 시나리오 생성이 병목 → Developer가 기본 랜덤 시나리오로 대체

### Tier별 스케일링 계획

- **Tier 1 (Cycle 1-3)**: 스케일링 불필요, 1대씩으로 검증
- **Tier 2 (Cycle 4-6)**: Developer VM 1대 추가 검토
- **Tier 3 (Cycle 7-9)**: Developer 2-3대, Evaluator 2대 고려
- **Tier 4 (Cycle 10+)**: 불필요 VM 정리, A100에 집중

---

## 9. 레슨런 루프 (Lessons Loop)

**"버티컬 슬라이스의 진정한 가치는 '무엇이 안 되는지 빨리 발견한다'에 있다."**

### 레슨런 추출 프로세스

매 사이클 완료 시:

1. **수집**: Evaluation 보고서 + 에이전트 BLOCKED/에러 이력 + 버킷 산출물 상태
2. **분류**: [기술] / [데이터] / [학습] / [프로세스] 4개 카테고리
3. **기록**: `gs://ralphton-handoff/lessons/cycle{NN}.md`
4. **배포**: 다음 사이클 HANDOFF에 관련 레슨런 선별 포함

### 배포 규칙

- Tier 1 (Cycle 1-3): 모든 레슨런을 전 에이전트에게 브로드캐스트
- Tier 2+ (Cycle 4+): 에이전트별 관련 레슨런만 선별 배포
- 같은 실수 2회 반복 시: 즉시 경고 + 구체적 코드 수준 지시로 강화

---

## 10. 기술 교훈 (사전 적용 사항)

이전 cowshed-simulator 개발에서 검증된 필수 규칙:

- **LL-1**: 물리엔진 회전 관성 미제어 → kinematic yaw 제어 + `angularVelocity.set(0,0,0)` 매 프레임
- **LL-2**: CANNON vs THREE `setFromEuler()` API 차이 주의
- **LL-3**: 액션 전환 시 velocity/rotation 명시적 리셋 필수
- **LL-4**: 이산 액션 좌우 진동 → `threshold > 2 × angular_speed × dt`, 비례 조향
- **LL-5**: follow 카메라 초기 위치를 로더 위치로 설정
- **LL-6**: `camera.up.set(0,1,0)` 매 프레임 고정
- **LL-7**: headless-gl은 WebGL 1.0만 지원 — Draco 불가, SkinnedMesh 불안정
- **LL-8**: 1920x1080은 OOM → 학습용 640x480 고정

---

## 11. 병렬 실행 타임라인 (원래 계획)

```
시간    Watcher         DomainExpert          Developer             Training            Evaluation
20:00   Phase 시작      시나리오 v1 생성       환경 변환
20:30   모니터링        시나리오 대량생산       로더 구현
21:00   상태 체크       200~300종 생성         Expert Agent
21:30   모니터링        계속 생성              데이터 기록
22:00   Phase 2         시나리오 전달           배치 생성(목표1000)
22:30   모니터링        추가 시나리오           배치 생성 계속                           대기
23:00   상태 체크       에지케이스 보강         LeRobot 변환          대기               품질 검증
23:30   모니터링        계속 생성              변환+생성 병행         대기               프레임 검증
00:00   상태 체크       피드백 반영             배치+전송              대기               불량 필터링
01:00   모니터링        부족분 보강             1000ep 마감            대기               피드백→DE
02:00   Phase 3         대기                   최종 전송              A100 세팅          데이터셋 최종검증
02:30   모니터링        대기                   대기                   파일럿 학습         대기
03:00   상태 체크       대기                   대기                   풀스케일 학습       대기
04:00   모니터링        대기                   대기                   학습 중...          대기
05:00   상태 체크       대기                   대기                   평가+튜닝           모델 평가
06:00   Phase 4         최종 정리              결과 정리              최종 checkpoint     최종 평가
07:00   최종 점검       대기                   데모 영상              대기               대기
08:00   종료 보고       종료                   완료                   종료               종료
```

---

## 12. GCS 핸드오프 버킷 구조

```
gs://ralphton-handoff/
├── ssot/                    ← PLAN.md, 레퍼런스 (초기 트리거 시 업로드)
├── scenarios/cycle{NN}/     ← DomainExpert → Developer (시나리오 JSON)
├── episodes/cycle{NN}/      ← Developer (시뮬레이션 산출물)
├── dataset/cycle{NN}/       ← Developer → Training (LeRobot HDF5)
├── checkpoints/cycle{NN}/   ← Training → Evaluation (학습 checkpoint)
├── reports/cycle{NN}/       ← Evaluation → Watcher (평가 리포트)
├── lessons/cycle{NN}.md     ← Watcher → 전 에이전트 (사이클별 레슨런)
├── demo/                    ← 최종 시연 영상
└── logs/                    ← 각 에이전트 작업 로그
```

---

## 13. 안전 행동 기대치

DomainExpert가 설계한 안전 시나리오에서 Expert Agent가 취해야 할 행동:

- **절벽/계단**: 가장자리 1m 전 비상 정지 → 후진 후 우회
- **바닥 구멍**: 주변 0.5m 회피 영역 → 해당 영역 내 레고 수거 포기
- **애완동물**: 2m 이내 접근 시 일시 정지 → 3m 이상 멀어지면 재개
- **아이**: 3m 이내 감지 시 즉시 완전 정지 → 5m 이상 멀어질 때까지 대기
- **금지 물체**: 안전 반경 0.3m 내 레고 건너뛰기 또는 저속 접근
- **경사로**: 저속 모드 전환 (throttle 최대 0.3), 10도 이상 진입 금지

---

## 14. 성공/실패 조건 (Watcher 기준)

### 성공 조건

- 최소 10회 전체 파이프라인 루프 완주
- 매 사이클마다 Evaluation의 정량적 평가 보고서 존재
- 최종 모델의 시연 영상 최소 1개
- 사이클 간 개선 추적 (10개 데이터포인트)
- 스케일링 이력 기록

### 실패 조건

- 5회 이하 루프로 종료
- Evaluation 없이 훈련만 수행
- 시연 영상 없이 숫자만 보고
- 에이전트 멈춰있는데 방치
- 병목 보이는데 VM 스케일링 미고려
