# Ralphton 해커톤 회고

## 목표 vs 실제

- **목표**: 10회 학습 루프 (Generate → Train → Evaluate → Feedback 사이클)
- **실제**: 3회 루프 + Wall FT 패치 (미완료 상태로 종료)
- **Rollout 성공률**: 0% (closed-loop에서 한 번도 성공 못함)

---

## 가장 큰 병목 3가지

### 1. 에피소드 생성 속도 (가장 치명적)

1,000 에피소드 목표였는데 실제로는 전체 합쳐 ~286개 생성. 원인은 단순하다 — headless Node.js 렌더링이 **에피소드당 4~8분** 걸렸다. 1,000개면 ~100시간 필요. 21시간 해커톤에서 물리적으로 불가능한 목표였다.

v3부터 320x240/10Hz로 해상도를 낮춰 2~3분으로 줄였지만, 이미 시간이 부족했다. **병렬 생성 (multi-process headless)을 처음부터 했어야 했는데, 단일 스레드로만 돌렸던 게 핵심 실수.**

### 2. Rollout Compounding Error (기술적으로 가장 어려운 문제)

오프라인 메트릭은 훌륭했다 — Loss 0.000080, Holdout MAE 0.0059. 그런데 실제로 시뮬레이터에서 돌리면 0% 성공. 이유:

- Expert-only 50개 에피소드로 학습 → **"잘되는 경우"만 학습**
- 실제 추론에서 미세한 오차 누적 → LIFTING 상태에서 빠져나오지 못함
- 전형적인 imitation learning의 covariate shift (DAgger 문제)
- v3에서 recovery 시퀀스를 추가했지만, Wall stuck이라는 새로운 문제가 나옴

**한 번 rollout 실패 → 원인 분석 → 데이터 재생성 → 재학습 → 재평가** 이 사이클이 매번 3~4시간 걸렸다. 10회 루프는커녕 이 디버깅 루프에 시간을 다 쏟았다.

### 3. 학습 자체의 소요 시간

- v2 500 epoch: 23:15 → 04:28 KST (**5시간 13분**)
- v3 100 epoch finetune: ~1.5시간
- v3 2nd 50 epoch: ~45분
- Wall FT 10 epoch: ~45분

A100이라 GPU는 충분했지만 (40GB 중 3.4GB만 사용), 500 epoch × 50 에피소드도 5시간이 걸렸다. 10회 루프를 돌리려면 학습 1회를 30분 이내로 끝내야 하는데, 실제론 첫 full training만 5시간.

---

## 시간 배분 실제 흐름

```
20:00  Phase 1 시작 (시뮬레이터 구축)
21:00  Loop 1 에피소드 완성 ✓
22:00  Phase 2 시작 — 여기서 1,000ep 목표가 52ep로 축소
23:15  v2 학습 시작 (50 에피소드)
───── 학습 5시간 대기 ─────
03:10  Rollout 실패 확인, 원인 분석 시작
04:28  v2 학습 완료 → 즉시 v3 데이터 생성 착수
05:50  v3 200 에피소드 완성
06:17  v3 finetune 100ep 완료 → 여전히 rollout 0%
07:25  WALL_STUCK 문제 확인, v5 wall patch 생성
08:44  Wall FT 시작 (ETA 09:30)
09:00~ 시간 종료...
```

**23:15~04:28 사이 5시간이 완전히 학습 대기 시간이다.** 이 구간에 Developer가 v3 데이터를 미리 준비했어야 했는데, 첫 학습 결과를 보고 방향을 잡으려 했기 때문에 병렬화가 안 됐다.

---

## 에피소드 생성 상세

- **v1**: ~10개 (Loop 1 검증용)
- **v2**: 52개 (13 시나리오 × 4)
- **v3**: 200개 (320x240/10Hz, recovery 시퀀스 포함)
- **v5 wall patch**: 24개 (anti-stuck override)
- **합계**: ~286개 (목표 1,000개의 28.6%)

---

## ACT 학습 Config

```yaml
policy:
  name: act
  chunk_size: 20
  n_action_steps: 20
training:
  batch_size: 64
  lr: 1e-4  # Wall FT에서는 2e-6으로 낮춤
  epochs: 500  # Wall FT는 10ep
  seed: 42
  save_checkpoint_every: 50
model:
  backbone: resnet18
  transformer_layers: 6
  action_dim: 4  # steering, throttle, bucket, lift
dataset:
  camera_names: [ego]
  image_size: [224, 224]
observation:
  state_dim: 4  # loader_x, loader_z, loader_rotation, legos_remaining
```

---

## Rollout 실패 원인 분석

### Root Cause 1: ImageNet 정규화 불일치 (03:10 KST 발견)

- 학습: `/255.0`만 적용
- 추론: ImageNet mean/std를 추가로 적용
- 수정 후에도 compounding error 지속

### Root Cause 2: Covariate Shift (03:43 KST 확인)

- Expert-only 50개 에피소드 → error recovery 시퀀스 없음
- 로더가 박스 근처(-6,-6)에서 LIFTING 상태 탈출 불가
- 분포 밖 상태에 대한 학습 데이터 부재

### Root Cause 3: WALL_STUCK (07:25 KST 발견)

- 벽 근처(-7.5,-7.5) 시나리오가 학습 데이터에 없음
- v5 wall patch + Wall FT로 대응 시도 (미완료)

---

## 인프라 이슈

### gcloud 인증 만료 (03:54 KST~)

- `gcloud auth login` 토큰이 해커톤 도중 만료
- non-interactive 환경에서 재인증 불가
- Watchdog의 VM 상태 확인/자동 복구 기능 상실
- 우회: SSH key 직접 사용 + Discord 활동으로 에이전트 생존 확인

### GCS Scope 불일치 (21:00 KST)

- DomainExpert VM의 gcloud scp/storage cp 실패
- 시나리오 전달이 Discord tarball → GCS 업로드로 우회
- 핸드오프 체인의 첫 번째 장애

### Watcher 에이전트 침묵 (22:17~22:50 KST)

- Phase 2 진입 직후 33분간 무응답
- Watchdog가 4회 연속 트리거 후 복구
- Developer가 직접 Training/Evaluation과 소통하도록 전환

---

## 10회 루프를 달성하려면 필요했던 것

1. **에피소드 생성 병렬화**: headless 프로세스 4~8개 동시 실행 → 시간 1/4~1/8로 단축
2. **학습 epoch 축소**: 500 epoch이 아니라 초반엔 50~100 epoch로 빠르게 검증 → rollout 테스트 → 문제 확인 후 full training
3. **Recovery 데이터를 처음부터 포함**: Expert-only가 아니라 DAgger 스타일로 perturbation + recovery 시퀀스를 1루프부터 넣었으면 rollout 디버깅에 시간을 덜 썼을 것
4. **Throughput 사전 계산**: "에피소드 1개 = X분" 측정 후 현실적 목표 설정
5. **학습-생성 파이프라인 병렬화**: 학습 대기 5시간 동안 다음 루프의 데이터를 미리 준비

---

## 비용 분석

### GCP VM (5대, 총 ~$20)

**서울 리전 (asia-northeast3-a) — 4대**

- `ralphton-watcher`: n2-standard-8 (8vCPU/32GB), 디스크 100GB
- `ralphton-developer`: n2-standard-8 (8vCPU/32GB), 디스크 100GB
- `ralphton-domain-expert`: n2-standard-4 (4vCPU/16GB), 디스크 50GB
- `ralphton-evaluator`: n2-standard-4 (4vCPU/16GB), 디스크 50GB
- 소계: 약 $6 (시간당 $0.15~0.30 × 가동시간)

**미국 리전 (us-central1-a) — 1대**

- `ralphton-a100`: A100 40GB (Spot 인스턴스, 정가 대비 60~70% 할인)
- 실제 GPU 사용량: 3.4GB / 40GB (8.5%) — 과잉 스펙
- 소계: 약 $14 (시간당 ~$2.48 × 약 5.5시간 실가동)

### AI API 호출 (가장 비싼 항목, ~$50~100)

**에이전트별 사용 모델**

- Watcher: OpenAI GPT-5.2 Pro
- Developer: Anthropic Claude Opus 4.6
- DomainExpert: OpenAI GPT-5.2 Pro
- Training: Anthropic Claude Opus 4.6
- Evaluation: Anthropic Claude Opus 4.6

**로컬 Watchdog (CCD)**

- 모델: Claude Sonnet (API 호출)
- 실행 간격: 10분마다 cron
- 호출당 예산 제한: $2.00
- 가동 시간: ~13시간 → 최대 78회 호출

### 기타

- **GCS 스토리지**: 약 20GB (에피소드 + HDF5 + 체크포인트) → $1 미만
- **Discord 봇**: 5개 인스턴스, 13시간+, 200+ 메시지 → 무료

### 총 예상 비용: 약 $70~120 (약 9만~16만원)

### 비용 효율성 이슈

- **A100 GPU가 놀았다**: 40GB 중 3.4GB만 사용 (8.5%). T4나 L4로도 충분했을 가능성 높음
- **서버보다 API가 비쌈**: VM 비용 $20 vs API 비용 $50~100. 에이전트들의 "대화"가 가장 비쌈
- **별도 비용 추적 없었음**: 해커톤 특성상 사전 예산 관리 없이 진행. 정확한 청구액은 GCP Billing + API Console 확인 필요

---

## 잘된 점

- 5개 AI 에이전트가 Discord로 13시간+ 자율 협업한 것 자체는 성공
- CCD Watchdog가 에이전트 침묵을 5분 내 감지하고 복구
- ACT 오프라인 수렴은 훌륭 (Loss 0.000080)
- Rollout 실패 원인을 해커톤 내에서 정확히 진단 (ImageNet norm, covariate shift, wall stuck)
- 적응형 데이터 전략 (v3 recovery 시퀀스, v5 wall-aware expert)을 시간 내에 설계하고 부분 검증

---

## 핵심 교훈

> **오프라인 메트릭이 좋다고 실제로 동작하는 건 아니다.** Imitation learning에서 rollout 검증을 1루프부터 빠르게 돌려야 한다. 5시간 학습 후 "0% 성공"을 발견하면 이미 늦다.

> **Throughput을 먼저 측정하라.** "1,000 에피소드"라는 목표는 생성 속도를 한 번도 측정하지 않고 세운 숫자였다. 에피소드 1개 생성에 4~8분이 걸린다는 사실을 알았다면 처음부터 병렬화하거나 목표를 조정했을 것이다.

> **학습과 데이터 생성을 병렬화하라.** 학습 5시간 대기 구간이 가장 큰 낭비였다. 첫 학습이 돌아가는 동안 다음 버전의 데이터를 미리 만들었어야 했다.
