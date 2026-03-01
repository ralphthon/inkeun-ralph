# Anti-Stuck Override — 기술 문서

## 개요

Anti-Stuck Override는 Behavior Cloning 모델이 학습 분포 밖 상태(벽/코너 stuck)에 빠졌을 때, 런타임에서 강제 개입하여 탈출시키는 안전장치입니다.

이 기능 하나로 rollout 성공률이 **0% → 40.5%** (best seed 50%)로 상승했습니다.

---

## 배경: 왜 필요했나

### 문제: WALL_STUCK

v3_2nd Ep25 모델은 LIFTING_LOOP_TRAP을 해결하고 벽돌을 운반할 수 있게 되었지만, 새로운 병목이 발견되었습니다:

- `has_brick=1` 상태에서 벽/코너(-7.5, -7.5)로 직진
- 학습 데이터에 "벽에 끼였을 때 탈출하는" 시퀀스가 없음
- BC 모델이 distribution 밖 상태를 만나면 동일 액션 반복 → 영구 고착

### Imitation Learning의 근본 한계

Expert-only 데이터로 학습하면 "잘 되는 경우"만 학습됩니다. 실제 추론에서 미세한 오차가 누적되면 한 번도 본 적 없는 상태에 도달하고, 모델은 무력해집니다. 이것이 전형적인 **covariate shift** (DAgger 문제)입니다.

---

## 구현

### 소스 파일

`~/simulator/rollout-act.js` (Developer VM)

### 핵심 코드 (~20줄)

```javascript
// CLI 플래그
const ANTI_STUCK = getArg('anti_stuck', 'off') === 'on';

// 매 추론 스텝마다 위치 이력 저장
stuckHistory.push({ x: loader.x, z: loader.z });

// 최근 30스텝(≈3초) 전 위치와 현재 위치 비교
if (ANTI_STUCK && stuckHistory.length > 30) {
  const old = stuckHistory[stuckHistory.length - 30];
  const dx = loader.x - old.x, dz = loader.z - old.z;

  // 이동 거리가 0.1 미만이면 "stuck" 판정
  if (Math.sqrt(dx*dx + dz*dz) < 0.1) {
    // 모델 출력을 무시하고 강제 reverse + random turn
    const overrideAction = {
      steering: (Math.random() > 0.5 ? 1 : -1),  // 랜덤 좌/우 풀스티어
      throttle: -0.8,   // 후진
      bucket: -1,        // 버킷 내림
      lift: -1           // 리프트 내림
    };
    lastAction = overrideAction;  // 모델 예측값 덮어쓰기
  }
}
```

### 동작 원리

1. **감지**: 10Hz 추론이므로 30스텝 = 약 3초. 3초간 이동 거리 < 0.1 → stuck 판정
2. **개입**: 모델 출력을 완전히 무시하고, `throttle=-0.8`(후진) + 랜덤 `steering`(±1 풀턴) 강제 주입
3. **1회성**: 다음 추론 스텝에서 모델이 다시 제어권을 가짐. 여전히 stuck이면 다시 override 발동
4. **로깅**: 발동 시점의 frame, 위치, 적용된 액션을 `anti_stuck_log`에 기록

### CLI 사용법

```bash
# anti_stuck OFF (기본값)
xvfb-run -a node rollout-act.js --episodes 5 --out ~/rollouts --anti_stuck=off

# anti_stuck ON
xvfb-run -a node rollout-act.js --episodes 5 --out ~/rollouts --anti_stuck=on
```

---

## 성능 효과

### 정량 결과

- **v3_2nd Ep25 (best model)**
  - OFF: 0/12 = 0% → ON: 평균 40.5%, best seed 6/12 = 50%
  - anti_stuck 발동 횟수: 에피소드당 13~21회

- **v3_2nd Ep50 (과적합 모델)**
  - OFF: 0/12 = 0% → ON: 2/12 = 16.7%
  - policy 자체가 망가져 override만으로는 한계

- **Wall FT best (폐기)**
  - OFF: 0% → ON: 4/12 = 33.3%
  - Ep25보다 하락 → avoidance ≠ recovery 확인

### anti_stuck_log 분석 (Ep25 best, 5/12 수거)

```
frame 444:  (-7.5, -7.5)  → 코너 stuck → reverse+turn
frame 534:  (-7.31, -7.34) → 코너 근처 → 추가 탈출
frame 819:  (-5.06, -3.45) → 벽 근처 → 탈출
frame 1068: (-7.5, -7.5)  → 다시 코너 → 탈출
frame 1920: (-7.5, -7.5)  → 또 코너 → 탈출
frame 2397: (-6.07, -4.75) → 후반부 stuck → 탈출
```

**패턴**: 코너(-7.5, -7.5)에 반복적으로 돌아가서 끼이는 현상. 모델이 box 방향(-6,-6)으로 가다가 벽에 충돌하는 navigation 문제.

---

## 한계 & 개선 방향

### 현재 한계

- **1회성 개입**: 탈출 후 바로 같은 벽으로 재진입
- **랜덤 방향**: 탈출 방향이 무작위라 비효율적
- **쿨다운 없음**: 탈출 직후 모델이 다시 벽으로 가면 즉시 재stuck

### 개선 방안

1. **쿨다운 추가**: 탈출 후 2~3초간 turn bias + min throttle 유지
2. **방향성 탈출**: 벽/코너 위치를 감지하여 반대 방향으로 탈출
3. **Recovery 데이터 학습**: stuck 상태에서 시작 → 탈출하는 데모로 모델 자체가 탈출 학습 (v6 batch 준비 완료)
4. **Goal hint 추가**: state에 (dx_to_box, dz_to_box) 추가하여 navigation 근본 해결

---

## 교훈

> **BC 모델의 한계를 인정하고, 런타임 안전장치로 보완하는 것이 실용적이다.**
> 모델이 완벽하지 않아도, 간단한 heuristic override 하나로 0% → 40.5%를 달성할 수 있다.
> Production에서 BC/IL 모델을 배포할 때 anti-stuck 같은 safety net은 선택이 아니라 필수다.

---

## 관련 파일

- 구현: `~/simulator/rollout-act.js` (Developer VM)
- 결과 (best): `gs://ralphton-handoff/demo/best_rollout_ep25_seed1000.mp4`
- 리포트: `gs://ralphton-handoff/demo/FINAL_REPORT.json`
- 모델: `gs://ralphton-handoff/checkpoints/v3_2nd_epoch_025/`
- v6 recovery 시나리오: `gs://ralphton-handoff/scenarios/batch_v6_stuck_init_recovery_loader/`
