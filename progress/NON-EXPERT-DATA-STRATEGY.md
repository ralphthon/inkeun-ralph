# Non-Expert 데이터 생성 전략

Expert-only 데이터의 covariate shift 문제를 해결하기 위한 비-Expert 데이터 생성 방법 정리.

## Expert-only 데이터의 문제

Expert 데이터만으로 학습하면 모델이 **"완벽한 궤적"만 알고, 실수에서 복귀하는 법을 모른다.** 실전에서 미세한 오차가 누적되면 학습 분포 밖으로 나가고, 거기서 뭘 해야 할지 몰라서 발산한다.

- Ralphton v2: 52 에피소드 expert-only → Loss 0.000080 (훌륭) → **Rollout 0%**
- v3: recovery 시퀀스 200개 추가 → wall-stuck이라는 새로운 미커버 상태 등장

---

## 방법 1: DAgger (Dataset Aggregation) — 가장 정석

```
1) Expert 데이터로 초기 학습
2) 학습된 모델로 rollout 실행 (실수 발생)
3) 모델이 방문한 상태에서 Expert가 "정답 액션"을 레이블링
4) 새 데이터를 기존 데이터셋에 추가
5) 재학습 → 반복
```

이 프로젝트 맥락에서는 Expert Agent(상태머신)가 있으므로, **모델의 rollout 상태를 캡처 → 그 상태에서 Expert Agent에게 정답 액션을 계산하게 하면** 된다.

---

## 방법 2: Perturbation Injection — 가장 실용적

Expert 시연 중간에 **의도적으로 노이즈를 주입**하고, Expert가 복구하는 과정을 녹화:

```javascript
// Expert 실행 중 랜덤하게 perturbation 삽입
if (Math.random() < 0.15) {  // 15% 확률
    // 방향을 임의로 틀기
    steering += (Math.random() - 0.5) * 0.6;
    // 또는 몇 프레임 동안 잘못된 액션
}
// → Expert가 다음 스텝에서 자연스럽게 보정
// → "실수 → 복구" 시퀀스가 자동으로 녹화됨
```

**가장 구현이 쉽고** 시뮬레이터 환경에 적합하다. Expert Agent의 상태머신이 이미 있으므로, perturbation 후에도 상태머신이 자동으로 복구 궤적을 생성한다.

---

## 방법 3: State Reset Injection — v3에서 시도한 것

특정 "어려운 상태"에서 에피소드를 시작:

```javascript
// 벽 근처에서 시작
loader.position.set(-7.5, 0, -7.5);
// 박스를 이미 들어올린 상태에서 시작
state = 'LIFTING';
// → Expert가 여기서 복구하는 과정을 녹화
```

v3에서 200개 recovery 에피소드를 만들었지만, **wall-stuck이라는 새로운 미커버 상태**가 등장. 수작업으로 상태를 열거하는 방식은 한계가 있다.

---

## 방법 4: Noise-Augmented Policy (가장 체계적)

학습 시 action에 직접 노이즈를 더해서 "약간 틀린 행동"에 대한 내성을 키움:

```python
# 학습 시 action augmentation
action_noise = torch.randn_like(action) * 0.05
augmented_action = action + action_noise
# loss는 원래 expert action에 대해 계산
```

---

## 방법 5: Temporal Ensemble + Receding Horizon — 추론 시 보완

데이터 자체는 아니지만, 추론 시 compounding error를 줄이는 기법:

```python
# chunk_size=20이지만 매 스텝 새로 예측하고
# 여러 예측의 가중 평균을 사용
weights = np.exp(-np.arange(chunk_size) * 0.1)  # 최근 예측에 가중치
action = np.average(predictions, weights=weights, axis=0)
```

---

## 이 프로젝트에 가장 적합한 조합

**Perturbation Injection + DAgger 루프**

```
1) Expert Agent에 15~20% perturbation 추가하여 에피소드 생성
2) 벽/코너/박스 근처 등 다양한 초기 위치에서 시작
3) ACT 학습 (100 epoch으로 빠르게)
4) Rollout → 실패 지점 수집
5) 실패 지점에서 Expert Agent가 recovery → 추가 에피소드 생성
6) 데이터 병합 후 재학습
```

### 왜 이 조합인가

- Expert Agent(상태머신)가 이미 존재 → **사람이 직접 조작할 필요 없이** 시뮬레이터에서 자동으로 recovery 데이터를 대량 생성 가능
- Perturbation은 "예측하지 못한 상태"를 체계적으로 만들어줌
- DAgger 루프는 실제 모델의 실패 지점을 커버

### RETROSPECTIVE.md의 교훈

> "Recovery 데이터를 처음부터 포함했으면 rollout 디버깅에 시간을 덜 썼을 것"

---

## 참고 문헌

- **DAgger**: Ross et al., "A Reduction of Imitation Learning and Structured Prediction to No-Regret Online Learning" (AISTATS 2011)
- **ACT**: Zhao et al., "Learning Fine-Grained Bimanual Manipulation with Low-Cost Hardware" (RSS 2023)
- **D2E**: WoRV AI, "Desktop to Embodied AI" (2025)
