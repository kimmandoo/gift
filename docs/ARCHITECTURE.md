# 코드 흐름 안내

이 문서는 처음 코드를 읽는 사람을 위한 gitflu의 지도입니다. 앱은
Flutter 화면과 Dart 백엔드가 같은 프로세스 안에서 동작합니다.

제품의 동작 목표는 JetBrains IDE Git GUI를 블랙박스로 관찰해 사용자에게
보이는 Git 작업 흐름과 상태 전환을 재현하는 것입니다. 시각적으로는
`docs/superpowers/specs/2026-09-02-jetbrains-git-gui-pixel-ui-design.md`의
미니멀한 2D 도트 게임그래픽 규칙을 따릅니다. 따라서 기능을 추가할 때는
먼저 동작 원장에 시나리오를 적고, 그 다음 Flutter 화면과 Dart 백엔드를
연결합니다. 원본 코드나 독점 에셋을 복사하는 방식은 사용하지 않습니다.

## 한 번의 저장소 열기 흐름

```text
main.dart
  └─ BranchlineApp
       └─ WelcomeScreen
            └─ RepositoryController
                 └─ GitGateway
                      └─ DartGitGateway
                           └─ DartGitBackend
                                ├─ GitInstallationService  (Git 찾기/검증)
                                └─ RepositoryService        (저장소 검증/등록)
                                     └─ ProcessGitRunner
                                          └─ 운영체제의 Git 실행 파일
```

1. `lib/main.dart`가 Flutter를 준비하고 `DartGitGateway`와 설정 저장소를
   `BranchlineApp`에 전달합니다.
2. `WelcomeScreen`은 화면을 그리고 `RepositoryController`를 통해 버튼
   동작을 처리합니다. 화면은 Git 명령을 직접 실행하지 않습니다.
3. `GitGateway`는 화면이 의존하는 작은 계약입니다. 테스트에서는 이
   계약을 구현한 fake 객체를 넣어 실제 Git 없이 화면을 검사할 수 있습니다.
4. `DartGitBackend`는 실제 백엔드 진입점입니다. 먼저 Git 설치를 확인한 뒤
   저장소 서비스를 호출합니다.
5. `RepositoryService`는 선택한 경로가 일반 작업 저장소인지 확인하고,
   Git이 알려준 저장소 루트를 canonical path로 바꿔 등록합니다.
6. `ProcessGitRunner`는 `Process.start`에 프로그램과 인자 목록을 따로
   전달합니다. 따라서 경로에 공백이나 `&`가 있어도 셸 문자열로 다시
   해석되지 않습니다.

## 폴더별 역할

| 경로 | 역할 |
|---|---|
| `lib/main.dart` | 앱 시작과 의존성 조립 |
| `lib/src/app/` | 최상위 Material 앱과 테마 |
| `lib/src/features/` | 화면별 UI와 컨트롤러 |
| `lib/src/backend/domain.dart` | 백엔드와 UI가 주고받는 값 객체 |
| `lib/src/backend/error.dart` | 사용자 메시지와 진단 정보를 가진 오류 |
| `lib/src/backend/executor.dart` | Git 프로세스 실행, 출력 제한, 비밀값 가리기 |
| `lib/src/backend/git_installation_service.dart` | Git 경로 검색과 버전 검사 |
| `lib/src/backend/repository_service.dart` | 저장소 확인과 세션용 ID 등록 |
| `lib/src/backend/dart_git_backend.dart` | 백엔드 서비스들을 연결하는 facade |
| `lib/src/backend/dart_git_gateway.dart` | Flutter 계약과 백엔드를 연결하는 얇은 adapter |
| `test/backend/` | 실제 Git을 사용한 백엔드 테스트 |
| `test/features/` | fake gateway를 사용한 화면 테스트 |

## 새 Git 기능을 추가할 때

새 기능은 다음 순서로 추가하면 흐름을 잃지 않습니다.

1. `domain.dart`에 UI에 필요한 결과 타입을 추가합니다.
2. `error.dart`에 사용자가 이해할 오류 분류가 필요한지 결정합니다.
3. `executor.dart`에서 사용할 `GitInvocation`의 인자 목록을 설계합니다.
4. 백엔드 service를 만들고 `DartGitBackend`에 의도를 드러내는 메서드를
   추가합니다. 화면에 Git raw command를 노출하지 않습니다.
5. `GitGateway`에 같은 의도의 메서드를 선언하고
   `DartGitGateway`에서 위임합니다.
6. 백엔드 테스트를 먼저 추가한 뒤 컨트롤러와 Flutter 화면을 연결합니다.
7. 동작 원장의 visible state와 도트 UI 스펙의 색상·간격·포커스 규칙을
   확인한 뒤 loading, empty, success, warning, error 상태를 모두 그립니다.

## 테스트를 읽는 순서

- 실행기부터 이해하려면 `test/backend/dart_git_backend_test.dart`를
  읽습니다. 버전 파싱, redaction, 실제 Git 실행, 저장소 열기를 순서대로
  보여줍니다.
- 화면 흐름은 `test/features/repository/welcome_screen_test.dart`에서
  fake gateway가 호출 경계를 어떻게 대신하는지 확인합니다.
- `test/features/settings/git_settings_dialog_test.dart`는 저장된 Git
  경로와 재시도 상태가 컨트롤러를 통해 화면에 반영되는 흐름을 보여줍니다.
