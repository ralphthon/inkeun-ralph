# 축사 시뮬레이터 Lessons Learned

> 2026-02-28 | cowshed-simulator 개발 과정에서 발견한 버그와 교훈

---

## 1. 물리엔진 회전 관성 미제어 → 피치/롤 회전

### 증상
- 로더가 앞뒤(피치), 좌우(롤)로 기울어지면서 영상이 흔들림
- 시간이 지날수록 기울어짐이 심해짐

### 원인
cannon-es 물리엔진이 로더 body에 중력과 충돌 반응을 적용하면서 **피치/롤 방향 회전을 자유롭게 허용**. `setFromEuler(0, rotation, 0)`은 angularVelocity가 0이 아닐 때만 호출해서, 나머지 시간에는 물리엔진이 body를 자유 회전시킴.

### 해결
```javascript
// 매 프레임 yaw만 적용, 피치/롤 강제 0 고정
loader.body.quaternion.setFromEuler(0, loader.rotation, 0);
loader.body.angularVelocity.set(0, 0, 0);  // 물리 회전 관성 제거
```

### 교훈
> **차량형 시뮬레이션에서 물리엔진은 이동만 맡기고, 회전은 직접 제어하라.**
> 물리엔진에 회전을 맡기면 지면 충돌, 가속/감속 시 예측 불가능한 기울어짐 발생.
> 특히 게임/시뮬에서 "arcade physics"로 만들 때는 rotation을 kinematic하게 관리.

---

## 2. THREE.Quaternion.setFromEuler() 잘못된 인자

### 증상
- `THREE.Quaternion: .setFromEuler() encountered an unknown order: undefined` 경고 매 프레임 출력
- 로더 mesh가 피치 방향으로 회전

### 원인
```javascript
// ❌ 잘못됨 — THREE.Quaternion.setFromEuler()는 Euler 객체를 받음
loader.mesh.quaternion.setFromEuler(0, 0, 0);

// ✅ 올바른 방법
loader.mesh.quaternion.copy(loader.body.quaternion);
// 또는
loader.mesh.quaternion.setFromEuler(new THREE.Euler(0, 0, 0));
```

CANNON.Quaternion과 THREE.Quaternion의 `setFromEuler()` API가 다름:
- **CANNON**: `setFromEuler(x, y, z)` — 숫자 3개
- **THREE**: `setFromEuler(euler)` — Euler 객체 1개

### 교훈
> **같은 이름의 메서드라도 라이브러리마다 시그니처가 다르다.**
> CANNON↔THREE 간 변환 시 항상 API 문서 확인.
> 경고 메시지를 무시하지 말 것 — "undefined order"가 실제 렌더링 문제의 원인이었음.

---

## 3. 액션 전환 시 상태 미초기화 → 잔존 속도/회전

### 증상
- forward 후 turn으로 바꿨는데 로더가 계속 전진
- turn 후 forward로 바꿨는데 계속 회전

### 원인
`executeAction()`에서 각 액션이 자기 값만 설정하고 **다른 값을 리셋하지 않음**:
```javascript
// ❌ forward 시 angularVelocity 미초기화
case ACTIONS.FORWARD:
    loader.velocity = speed;  // velocity만 설정
    break;                    // angularVelocity는 이전 값 유지!

// ❌ turn 시 velocity 미초기화
case ACTIONS.TURN_RIGHT:
    loader.angularVelocity = turnSpeed;  // angular만 설정
    break;                                // velocity는 이전 값 유지!
```

### 해결
```javascript
case ACTIONS.FORWARD:
    loader.velocity = speed;
    loader.angularVelocity = 0;  // ← 반드시 리셋
    break;
case ACTIONS.TURN_RIGHT:
    loader.angularVelocity = turnSpeed;
    loader.velocity = 0;          // ← 반드시 리셋
    break;
```

### 교훈
> **상태 머신에서 상태 전환 시 모든 관련 변수를 명시적으로 설정하라.**
> "이전 값이 남아있을 수 있다"를 항상 가정.
> 특히 velocity/rotation 같은 연속값은 0으로 명시적 리셋 필수.

---

## 4. 이산 액션의 좌우 진동 (Oscillation)

### 증상
- 86~99%의 프레임이 turn_left↔turn_right 반복
- 로더가 제자리에서 좌우로 흔들림

### 원인
1. 회전 속도(2.5 rad/s)가 너무 빠름 — 1프레임에 0.083 rad 회전
2. 각도 임계값(0.2 rad)이 너무 작음
3. → 2~3프레임이면 목표각을 넘어서 → 반대로 회전 → 무한 반복

### 해결 (단계적)
1. 회전 속도 감소: 2.5 → 1.2 rad/s
2. 임계값 증가: 0.2 → 0.8 rad
3. **forward_left/forward_right 커브 액션 추가** — 전진+회전 동시
4. **비례 조향**: angleDiff에 비례한 커브 강도 (`steerAmount = angleDiff / 1.2`)

### 교훈
> **이산 액션(turn/forward)만으로는 부드러운 경로 추적이 불가능.**
> 반드시 "전진+회전" 복합 액션이 필요.
> 이상적으로는 **연속 제어**(steering angle)로 전환해야 함 — 이산 액션은 본질적으로 진동에 취약.

> **회전 속도 × 프레임 시간 vs 임계값** 관계를 반드시 계산:
> - 1프레임 회전량 = angular_speed × dt
> - 이 값이 임계값의 절반 이상이면 진동 발생
> - 규칙: `threshold > 2 × angular_speed × dt`

---

## 5. 카메라 초기 위치 미설정 → 시작 시 스윙

### 증상
- 영상 시작 시 카메라가 크게 회전하면서 시점이 급변
- 특히 follow 카메라에서 심함

### 원인
follow 카메라 초기 위치가 (0,0,0)인데, 로더는 (x, -12) 부근에서 시작.
lerp(0.02~0.05)로 부드럽게 따라가는 로직이라 초기 수 초간 큰 이동 발생.

### 해결
```javascript
// 시나리오 시작 시 모든 카메라를 로더 위치 기준으로 초기화
initCamerasAtLoader(cameraManager, loader);
```

### 교훈
> **카메라는 시뮬레이션 시작 시 반드시 목표 위치로 초기화.**
> lerp 기반 추적 카메라는 초기값이 멀면 시작 수 초가 쓸모없어짐.
> 학습 데이터에서 시작 N프레임이 오염되면 모델 성능에 직접 영향.

---

## 6. 카메라 up 벡터 미고정 → 롤 회전

### 증상
- ego/follow 시점에서 카메라가 롤(좌우 기울기) 방향으로 회전
- 수평선이 기울어져 보임

### 원인
`camera.lookAt()` 호출 시 THREE.js가 내부적으로 up 벡터 기반으로 orientation 계산.
up 벡터가 기본값 (0,1,0)이어도, 특정 각도에서 gimbal 이슈로 롤이 발생할 수 있음.

### 해결
```javascript
camera.up.set(0, 1, 0);  // 매 프레임 up 벡터 강제 고정
camera.lookAt(target);
```

### 교훈
> **`lookAt()` 호출 전에 항상 `camera.up`을 명시적으로 설정.**
> birds_eye처럼 위에서 내려보는 카메라는 up 벡터를 (0,0,-1) 등으로 별도 지정.

---

## 7. headless-gl 환경의 GLTF 제한

### 증상
- Soldier.glb: `self is not defined` 에러 (DRACOLoader)
- Xbot.glb: SkinnedMesh 렌더링 안 됨 (빈 화면)
- RobotExpressive.glb: 정상 동작

### 원인
- **headless-gl = WebGL 1.0** — bone texture, SRGB, 많은 WebGL 2.0 기능 미지원
- **DRACOLoader**: Web Worker(`self`)에 의존 → headless 환경에서 불가
- **SkinnedMesh**: bone matrix를 texture로 전달하는 방식이 WebGL 1.0에서 제한적

### 해결
- GLB 모델 선택 시 **일반 Mesh + bone hierarchy** 구조인지 확인
- Draco 압축 사용하지 않은 모델 선택
- `fs.readFileSync` → `ArrayBuffer` → `GLTFLoader.parse()` 방식 사용

### 교훈
> **headless-gl 환경에서는 모든 3D 모델이 동작하지 않는다.**
> 모델 선택 전 반드시 테스트 렌더링.
> 체크리스트: Draco 압축 ✗, SkinnedMesh 주의, WebGL 2.0 전용 기능 ✗

---

## 8. 1920×1080 렌더링 시 메모리 부족 (OOM Kill)

### 증상
- Full HD 5시점 렌더링 중 프로세스가 SIGKILL로 종료
- 2번째 카메라 인코딩 시점에서 사망

### 원인
- 1920×1080 프레임 PNG: ~6MB × 300프레임 = 디스크 I/O 과부하
- FFmpeg 인코딩 시 메모리 사용량 급증
- GCP VM 메모리 제한

### 해결
- 학습용은 640×480으로 충분 (ACT 모델은 224×224로 리사이즈)
- Full HD는 프레젠테이션/데모용으로만 단일 시점 생성

### 교훈
> **학습 데이터 해상도는 모델 입력 해상도에 맞추라.**
> 불필요하게 높은 해상도는 시간·메모리·저장공간 낭비.
> 640×480 → 224×224 리사이즈가 1920×1080 → 224×224보다 10배 효율적.

---

## 요약 체크리스트 (새 시뮬레이터 만들 때)

- [ ] 차량 회전은 물리엔진 대신 kinematic 제어
- [ ] 매 프레임 `body.angularVelocity.set(0,0,0)` 으로 물리 회전 관성 제거
- [ ] CANNON↔THREE API 차이 확인 (특히 `setFromEuler`)
- [ ] 경고 메시지 무시하지 않기
- [ ] 액션 전환 시 모든 속도/회전 변수 명시적 리셋
- [ ] `threshold > 2 × angular_speed × dt` 확인
- [ ] 복합 액션(forward+turn) 반드시 포함
- [ ] 비례 제어 (angleDiff에 비례한 조향)
- [ ] 카메라 초기 위치 = 타겟 위치로 세팅
- [ ] `camera.up` 매 프레임 명시적 설정
- [ ] headless-gl 모델 호환성 사전 테스트
- [ ] 학습용 해상도 = 모델 입력 해상도 기준

---

*이 문서는 같은 실수를 반복하지 않기 위한 참고자료입니다.*
