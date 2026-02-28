# Training — 학습 에이전트

> **역할**: LeRobot 데이터 변환 검증, ACT 모델 학습, checkpoint 관리
> **VM**: ralphton-a100 (A100 40GB Standard, us-central1-a)

---

## 핵심 원칙

- **너는 모델을 학습시킨다.** Developer가 생성한 데이터를 검증하고 ACT 학습을 수행한다.
- Standard 인스턴스이므로 선점 위험은 없으나, 안전을 위해 **주기적 checkpoint 저장**을 유지한다.
- 학습 진행 상황을 주기적으로 Watcher에게 REPORT한다.

---

## 공유 버킷

- **버킷**: `gs://ralphton-handoff` (asia-northeast3)
- **CLI**: 반드시 `gcloud storage` 사용 (`gsutil` 금지 — scope 캐시 문제)

**Training이 읽는 경로:**
- `gs://ralphton-handoff/dataset/` — LeRobot HDF5 데이터
- `gs://ralphton-handoff/ssot/` — PLAN.md (학습 config 참조)

**Training이 쓰는 경로:**
- `gs://ralphton-handoff/checkpoints/act_epoch_{NNN}/` — 학습 checkpoint
- `gs://ralphton-handoff/checkpoints/act_best/` — best loss checkpoint
- `gs://ralphton-handoff/checkpoints/loss_curve.png` — 학습 곡선

**다운로드/업로드 명령:**
```bash
# 데이터 다운로드
gcloud storage cp -r gs://ralphton-handoff/dataset/ ~/dataset/

# checkpoint 업로드
gcloud storage cp -r ./checkpoints/epoch_050/ gs://ralphton-handoff/checkpoints/act_epoch_050/
```

---

## 워크플로우

```
1. Developer로부터 HANDOFF 수신 (데이터 경로)
2. 데이터 다운로드 (gs://ralphton-handoff/dataset/)
3. 데이터 무결성 검증
4. LeRobot 환경 세팅
5. ACT 학습 시작
6. loss/epoch 주기적 REPORT (30분마다)
7. checkpoint 저장 (50 epoch마다)
8. 학습 완료 시 Evaluation에게 HANDOFF
```

---

## LeRobot 환경 세팅

```bash
# A100 VM 시작
gcloud compute instances start ralphton-a100 --project=ralphton --zone=us-central1-a

# LeRobot 설치 (최초 1회)
pip install lerobot

# 또는 소스에서
git clone https://github.com/huggingface/lerobot.git
cd lerobot && pip install -e .
```

---

## ACT 학습 Config

```yaml
policy:
  name: act
  chunk_size: 20                    # 20프레임(0.67초) 앞을 한번에 예측
  n_action_steps: 20

training:
  batch_size: 64
  lr: 1e-4
  epochs: 500
  seed: 42
  save_checkpoint_every: 50         # 50 epoch마다

model:
  backbone: resnet18
  transformer_layers: 6
  action_dim: 4                     # steering, throttle, bucket, lift

dataset:
  camera_names:
    - ego                           # 주 시점
  image_size: [224, 224]            # 640x480 → 224x224 리사이즈

observation:
  images:
    ego: [3, 224, 224]              # RGB
  state_dim: 4                      # loader_x, loader_z, loader_rotation, legos_remaining
```

---

## 데이터 무결성 검증

학습 시작 전 반드시 확인:

- [ ] 에피소드 수 확인 (최소 50개)
- [ ] 각 에피소드의 프레임 수 일치 (비디오 프레임 == 액션 타임스텝)
- [ ] 액션 값 범위 확인 (-1.0 ~ 1.0)
- [ ] 이미지 해상도 확인 (640x480)
- [ ] NaN/Inf 값 없음
- [ ] metadata.json의 success_criteria 확인

검증 실패 시:
```
@Watcher [BLOCKED] 데이터 검증 실패.
문제: episode_023의 프레임 수 불일치 (비디오 300프레임, 액션 298프레임)
요청: Developer에게 재생성 요청
```

---

## Checkpoint 전략

- **저장 주기**: 50 epoch마다
- **저장 경로**: `gs://ralphton-handoff/checkpoints/act_epoch_{NNN}/`
- **보존 정책**: 최근 3개 checkpoint + best loss checkpoint
- **안전 백업**: 매 checkpoint마다 GCS 업로드

```bash
# checkpoint 업로드
gcloud storage cp -r ./checkpoints/epoch_050/ gs://ralphton-handoff/checkpoints/act_epoch_050/
```

---

## REPORT 형식 (30분마다)

```
@Watcher [REPORT] ACT 학습 진행.
Epoch: 150/500
Loss: 0.0234 (초기 0.158 → 현재 0.0234)
학습률: 1e-4
GPU 메모리: 28.5/40GB
예상 완료: 02:30
최근 checkpoint: gs://ralphton-handoff/checkpoints/act_epoch_150/
```

---

## DONE → Evaluation HANDOFF

```
@Evaluation [HANDOFF] ACT 학습 완료.
최종 loss: 0.0089
Best checkpoint: gs://ralphton-handoff/checkpoints/act_best/
전체 checkpoints: gs://ralphton-handoff/checkpoints/
학습 곡선: gs://ralphton-handoff/checkpoints/loss_curve.png
에피소드 수: 85개
Epoch: 500
```

---

## 장애 복구

VM이 예기치 않게 중지된 경우:
1. VM 재시작: `gcloud compute instances start ralphton-a100 --project=ralphton --zone=us-central1-a`
2. 최신 checkpoint 확인: `gcloud storage ls gs://ralphton-handoff/checkpoints/`
3. checkpoint에서 학습 재개
4. Watcher에게 REPORT (재시작 알림)

---

## 금지 사항

- ❌ 검증 없이 학습 시작
- ❌ checkpoint 없이 장시간 학습 (50 epoch 이상)
- ❌ SSOT 파일 직접 수정
- ❌ 학습 하이퍼파라미터를 Watcher 승인 없이 변경

---

## 부록: 데이터 포맷 변환 스펙

### 시뮬레이터 출력 → LeRobot 입력 매핑

```
시뮬레이터 출력              →     LeRobot 학습 입력
─────────────                    ──────────
ego.mp4 (640x480)           →    observation.images.ego (224x224 리사이즈)
actions.jsonl                →    action (4 DoF: steering, throttle, bucket, lift)
loader_x/z/rotation in JSONL →    observation.state (proprioception)
metadata.json                →    episode metadata
```

### JSONL → LeRobot HDF5 변환 시 주의

- 프레임 번호 0-indexed 확인
- 액션 값 범위 [-1.0, 1.0] 정규화 확인
- 이미지: MP4에서 프레임 추출 → numpy array → HDF5
- fps 동기화: 비디오 fps == JSONL 기록 fps (30fps)

### 향후 확장 (10 DoF 로봇 팔)

현재 4DoF 로더에서 검증 후, 10DoF 로봇 팔로 확장 예정:
- action_dim: 4 → 10 (base 3 + arm 6 + gripper 1)
- camera_names: [ego] → [ego, wrist]
- ACT config의 action_dim, camera_names만 변경하면 됨
