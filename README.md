# TouchBarFeedback

**한국어** | [English](README.en.md)

<p align="center"><img src="docs/demo-ko.gif" width="720" alt="터치바를 누르면 트랙패드에서 햅틱 피드백"></p>

맥북 터치바 버튼을 누를 때 **트랙패드 햅틱 진동**과 **"토독" 클릭 소리**로 피드백을 주는 메뉴 막대 앱입니다.

터치바에는 진동 모터가 없어서 누른 느낌이 거의 없죠. 이 앱은 터치바 터치를 감지해서 바로 아래 트랙패드의 햅틱 엔진(Force Touch)을 울리고, 키보드를 치는 듯한 짧은 "톡" 소리를 냅니다.

## 기능

- 터치바 **버튼**을 누를 때만 피드백 (버튼 사이나 빈 곳을 누르면 조용함)
- 햅틱 세기 3단계: 약하게 / 보통 / 강하게
- 클릭 소리: **토독**(기본, 직접 합성한 소리) / Tink / 원하는 소리 파일
- "토독"은 살짝 다른 변형 3개를 번갈아 재생해서 기계적으로 들리지 않음
- 로그인 시 자동 실행
- 메뉴는 시스템 언어에 따라 한국어 또는 영어로 표시

## 요구 사항

- 터치바가 있는 맥북 프로
- macOS 13 Ventura 이상 (macOS 15.5, Apple Silicon에서 테스트)
- Xcode 또는 Command Line Tools (`xcode-select --install`)

## 설치

```bash
git clone https://github.com/suinegyzal/TouchBarFeedback.git
cd TouchBarFeedback
./build.sh
open ~/Applications/TouchBarFeedback.app
```

`build.sh`가 소스를 컴파일해서 `~/Applications/TouchBarFeedback.app`에 설치합니다.

### 처음 실행할 때

1. **손쉬운 사용 권한**을 허용해 주세요. 터치 감지와 버튼 위치 확인에 필요합니다.
   - "손쉬운 사용 접근 요청" 창이 뜨면 **시스템 설정 열기**를 누르세요.
   - 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → **TouchBarFeedback** 켜기
2. **앱을 종료했다가 다시 실행하세요.** 권한을 켠 뒤 재실행해야 적용됩니다.
3. 터치바 버튼을 눌러보세요.

> **다시 빌드했다면** 서명이 바뀌어서 기존 권한이 적용되지 않습니다. 목록에서 켜져 있는 것처럼 보여도 예전 버전의 권한입니다. 아래 명령으로 권한 기록을 지운 뒤, 앱을 실행해서 다시 허용하고 재실행하세요.
> ```bash
> tccutil reset All local.touchbarfeedback
> ```

## 사용법

메뉴 막대의 👆 아이콘을 누르면 설정할 수 있습니다.

<p align="center"><img src="docs/menu-ko.png" width="720" alt="메뉴 막대 설정 메뉴"></p>

| 메뉴 | 설명 |
|---|---|
| 켜기 | 피드백 전체 켜기/끄기 |
| 햅틱 / 세기 | 트랙패드 진동과 세기 (세기를 고르면 바로 미리 진동) |
| 클릭 소리 | 소리 켜기/끄기와 종류 선택 (고르면 바로 미리 듣기) |
| 로그인 시 자동 실행 | 재부팅 후에도 자동 실행 |

## 동작 원리

1. **터치 감지**: `CGEventTap`(읽기 전용)으로 제스처 이벤트를 받고, 터치가 들어온 기기 종류(`NSTouch.device.deviceType == 3`)로 터치바 터치만 골라냅니다. 다른 앱의 이벤트를 막거나 바꾸지 않습니다.
2. **버튼 판별**: 손쉬운 사용 API로 현재 앱과 Control Strip이 터치바에 올린 요소(`AXFunctionRowTopLevelElements`)의 위치를 읽어서, 터치한 곳에 버튼이 있을 때만 반응합니다.
3. **햅틱**: 손가락이 트랙패드에 없어도 진동하도록 비공개 프레임워크 `MultitouchSupport`의 `MTActuator*` 함수로 트랙패드 액추에이터를 직접 구동합니다.
4. **소리**: "토독" 소리는 [`tools/make_sounds.py`](tools/make_sounds.py)로 직접 합성한 파일(`sounds/`)입니다. 지연을 줄이려고 미리 로드해 두고 재생합니다.

## 알려진 제한

- 햅틱은 애플의 **비공개 API**를 쓰기 때문에 macOS 업데이트 후 동작하지 않을 수 있습니다. 그래서 App Store에는 올릴 수 없습니다.
- 진동은 터치바가 아니라 트랙패드에서 느껴집니다.

## 문제 해결

- **반응이 없을 때**: 위의 `tccutil reset` 명령으로 권한을 초기화하고, 다시 허용한 뒤 앱을 재실행해 보세요. 대부분 이걸로 해결됩니다.
- **진단 로그 켜기**: 아래 명령을 실행하고 앱을 재실행하면 `~/Library/Logs/TouchBarFeedback.log`에 권한 상태와 터치 위치가 기록됩니다.
  ```bash
  defaults write local.touchbarfeedback debug -bool true
  ```
  끌 때는 `defaults delete local.touchbarfeedback debug`

## 제거

메뉴에서 "로그인 시 자동 실행"을 끄고 종료한 뒤 앱을 지웁니다.

```bash
rm -rf ~/Applications/TouchBarFeedback.app
tccutil reset All local.touchbarfeedback
```

## 참고

같은 아이디어를 먼저 구현한 오픈소스 프로젝트 [HapticKey](https://github.com/niw/HapticKey)를 참고했습니다.

## 라이선스

MIT
