# 코드 흐름 안내

이 문서는 처음 코드를 읽는 사람을 위한 gitflu의 지도입니다. 앱은
Flutter 화면과 Dart 백엔드가 같은 프로세스 안에서 동작합니다.

제품의 동작 목표는 익숙한 데스크톱 Git 작업 흐름과 상태 전환을 명확하게
재현하는 것입니다. 시각적으로는
`docs/superpowers/specs/2026-09-02-jetbrains-git-gui-pixel-ui-design.md`의
미니멀한 2D 도트 게임그래픽 규칙을 따릅니다. 따라서 기능을 추가할 때는
먼저 동작 원장에 시나리오를 적고, 그 다음 Flutter 화면과 Dart 백엔드를
연결합니다. 모든 코드는 독립적으로 작성하고 에셋도 프로젝트의 시각
규칙에 맞게 관리합니다.

## 한 번의 저장소 열기 흐름

```text
main.dart
  └─ GitfluApp
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
   `GitfluApp`에 전달합니다.
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

## 변경 목록을 읽는 흐름

```text
ChangesScreen
  └─ changesControllerProvider (Riverpod)
       └─ ChangesController.refresh()
            └─ GitGateway.getStatus()
                 └─ DartGitBackend.getStatus()
                      └─ RepositoryService.getStatus()
                           ├─ ProcessGitRunner
                           └─ parseGitStatus()
                                └─ GitStatusSnapshot
```

1. `ChangesScreen`은 Riverpod family provider에서 현재 저장소용
   `ChangesController`를 받습니다. 테스트에서는 같은 화면에 fake
   controller를 직접 주입할 수 있습니다.
2. 컨트롤러는 처음 한 번 즉시 status를 읽고, 화면이 살아 있는 동안 5초
   간격으로 다시 읽습니다. 이미 요청 중이면 다음 요청은 건너뜁니다.
3. 백엔드는 opaque repository ID를 실제 root로 해석한 뒤 Git에
   `status --porcelain=v2 -z --branch`를 요청합니다.
4. `parseGitStatus`는 NUL로 분리된 원본 경로를 보존하면서 staged,
   unstaged, untracked, conflicted facet을 만듭니다.
5. 원본 출력 hash가 바뀔 때만 generation을 올립니다. 화면은 snapshot을
   받아 네 그룹으로 그리며, 선택한 파일이 여전히 있으면 선택을 유지합니다.

## 선택 파일 diff 흐름

```text
ChangesScreen
  └─ ChangesController.selectChange()
       └─ GitGateway.getDiff(path, scope)
            └─ DartGitBackend.getDiff()
                 └─ RepositoryService.getDiff()
                      ├─ ProcessGitRunner (4 MiB capture limit)
                      └─ parseUnifiedDiff()
                           └─ GitDiffSnapshot
                                └─ ListView.builder (visible diff lines)
```

1. 변경 목록의 행을 누르면 컨트롤러가 선택 경로만 기록하고 diff를 별도로
   요청합니다. 그래서 status 목록은 diff를 기다리느라 막히지 않습니다.
2. staged 전용 변경은 `--cached` 범위로 시작하고, 두 facet이 모두 있는
   변경은 working-tree 범위로 시작합니다. 화면의 segmented control로
   두 범위를 다시 읽을 수 있습니다.
3. rename이면 status가 알려준 원래 경로도 Git pathspec에 함께 전달합니다.
   파서는 rename 메타데이터, binary 응답, hunk별 줄 번호를 화면 모델로
   바꿉니다.
4. diff 응답은 4 MiB에서 캡처를 멈추지만 프로세스 파이프는 끝까지
   drain합니다. 오래 걸리거나 이전 선택에 대한 응답은 현재 선택을
   덮어쓰지 않습니다.

## 선택 파일 stage/unstage 흐름

```text
ChangesScreen
  └─ ChangesController.stageSelected()/unstageSelected()
       └─ GitGateway.stage()/unstage()
            └─ DartGitBackend
                 └─ RepositoryService._mutatePath()
                      ├─ AppState.runMutation(repositoryId)  (serialized)
                      ├─ git add -- path
                      │    또는 git restore --staged -- path
                      └─ getStatus() → refreshed GitStatusSnapshot
```

1. 컨트롤러는 현재 선택이 있을 때만 액션을 노출하고, 충돌 파일에는
   mutation 버튼을 노출하지 않습니다.
2. backend는 화면이 보낸 경로를 opaque repository ID로 찾은 root에서
   별도의 argv 값으로 전달합니다. 경로에 공백이나 셸 문자가 있어도
   셸 문자열로 조합하지 않습니다.
3. 같은 repository ID의 mutation은 `AppState` queue에서 한 번에 하나씩
   실행합니다. 각 명령이 끝나면 status를 다시 읽어 staged/unstaged
   그룹과 generation을 즉시 갱신합니다.

## 선택 파일 discard 흐름

```text
ChangesScreen
  └─ prepareDiscard() → createDiscardPreview(path)
       └─ status hash + working-tree diff hash + 2-minute token
            └─ confirmation dialog
                 └─ confirmDiscard(token)
                      └─ AppState.runMutation(repositoryId)
                           ├─ re-check token, status, and diff fingerprints
                           ├─ git restore --worktree -- token.path
                           └─ getStatus() → refreshed selection
```

1. discard는 untracked 또는 conflicted 파일에는 제공하지 않습니다. 이
   단계는 파일 삭제가 아니라 tracked working-tree 내용을 index 기준으로
   되돌리는 기능이며, staged 변경은 유지합니다.
2. preview token은 2분 뒤 만료되고 repository ID와 경로에 묶입니다.
   확인 직전에 status와 diff fingerprint를 다시 비교하므로 다른 작업이나
   파일 수정이 끼어들면 복원을 실행하지 않고 stale 오류를 보여줍니다.
3. 확인 취소는 token을 화면 상태에서 제거합니다. 복원 후 선택 파일이
   사라지면 selection도 함께 비우고, staged facet이 남으면 선택을 유지해
   새 diff를 읽습니다.

## staged commit 흐름

```text
ChangesScreen
  └─ commit message editor
       └─ ChangesController.commit(message)
            └─ GitGateway.commit(repositoryId, message)
                 └─ DartGitBackend
                      └─ RepositoryService.commit()
                           ├─ AppState.runMutation(repositoryId)  (serialized)
                           ├─ git commit --file=-  + UTF-8 stdin
                           ├─ hook/process error → typed GitError
                           └─ getStatus() → GitCommitResult
                                └─ clear staged UI and show commit ID
```

1. 편집기는 staged facet이 하나 이상 있을 때만 보입니다. 빈 메시지는
   버튼을 비활성화하고, commit 중에는 다른 mutation과 편집을 잠급니다.
2. 백엔드는 모든 staged 경로를 한 번에 commit합니다. 메시지를 argv에
   넣지 않고 `--file=-`와 UTF-8 stdin으로 전달하므로 한글, 악센트,
   이모지와 셸 문자가 포함된 메시지도 같은 경로로 처리됩니다.
3. commit 뒤 status를 다시 읽어 새 HEAD의 `branch.oid`와 staged 상태를
   함께 반환합니다. 성공하면 선택이 사라진 파일은 선택 해제하고,
   working-tree facet이 남은 파일은 선택을 유지합니다.
4. Git의 process failure 진단에 hook 관련 표식이 있으면
   `GitErrorCategory.hookRejected`로 분류해 화면에 원인을 짧게 보여줍니다.
   원본 stderr는 실행기에서 redaction된 진단으로만 보존됩니다.

## history와 graph 흐름

```text
HistoryScreen
  └─ HistoryController.refresh()/loadMore()
       └─ GitGateway.getHistory(limit, offset)
            └─ DartGitBackend
                 └─ RepositoryService.getHistory()
                      ├─ git log --all --topo-order --max-count/--skip
                      └─ parseGitHistory() → GitHistoryPage
                           └─ deterministic parent lanes
```

1. 백엔드는 화면이 요청한 크기보다 한 commit을 더 읽어 `hasMore`를
   계산합니다. 최대 page size를 제한해 큰 history가 한 번에 메모리를
   점유하지 않도록 합니다.
2. 각 record는 object ID, parent IDs, author, 날짜, subject, body로
   파싱됩니다. 각 행은 commit lane뿐 아니라 위쪽 lane에서 아래쪽 lane으로
   이어지는 segment 목록을 가집니다. merge/fork는 여러 segment로 표현하고,
   pagination 뒤에는 현재까지 읽은 전체 commit의 lane을 다시 계산합니다.
3. History 화면은 처음 page를 표시하고 Load more를 눌렀을 때 다음 offset을
   요청합니다. commit 행을 선택하면 오른쪽 detail pane에서 전체 ID,
   parent, author와 body를 읽을 수 있습니다.

## branch popup 흐름

```text
ChangesScreen
  └─ BranchDialog
       ├─ GitGateway.getBranches()
       │    └─ git for-each-ref refs/heads/
       └─ create/switch action
            └─ RepositoryService._runBranchAction()
                 ├─ validate Git ref name
                 ├─ AppState.runMutation(repositoryId)
                 ├─ git switch [--create] name
                 └─ getStatus() → GitBranchActionResult
```

1. popup은 `for-each-ref`를 사용해 로컬 branch와 현재 `HEAD` 표식을
   읽습니다. upstream 값이 있으면 함께 보여주고, 화면은 raw ref 명령을
   직접 조립하지 않습니다.
2. branch 이름은 NUL·공백·금지 문자를 먼저 거르고, 생성과 전환은 같은
   repository mutation queue에서 실행합니다. 작업 트리에 commit되지 않은
   변경이 있어 전환할 수 없으면 dirty-worktree 메시지로 안내합니다.
3. 성공한 결과는 새 status와 함께 dialog 밖으로 돌아옵니다. Changes
   controller가 즉시 status를 다시 읽어 branch identity와 file list를
   갱신합니다.

## remote와 cancellation 흐름

```text
ChangesScreen
  └─ RemoteDialog
       ├─ GitGateway.getRemotes() → git remote --verbose
       └─ fetch/pull/push
            └─ GitCancellationToken
                 └─ RepositoryService._runRemote()
                      ├─ AppState.runMutation(repositoryId)
                      ├─ ProcessGitRunner (bounded output + progress state)
                      ├─ cancel → process.kill() → cancelled error
                      └─ getStatus() → GitRemoteOperationResult
```

1. remote 목록은 fetch/push URL을 합쳐 보여주고, URL은 화면에 표시하기
   전에 credential redaction을 거칩니다. 설정된 remote가 없으면 별도의
   빈 상태를 보여줍니다.
2. fetch, pull, push는 한 repository에서 동시에 실행하지 않습니다. 실행
   중에는 indeterminate progress와 Cancel operation 버튼을 보여주며,
   취소해도 stderr 원문 대신 `cancelled` 분류만 노출합니다.
3. 성공하면 status를 다시 읽고 operation/remote/summary와 함께 반환합니다.
   실패 진단은 authentication, network, non-fast-forward, merge conflict로
   분류해 사용자가 다음 조치를 알 수 있게 합니다.

## pixel workspace와 keyboard 흐름

```text
GitfluApp
  ├─ persisted ThemeMode
  └─ buildPixelTheme(light/dark)
       ├─ bundled Jersey 15 pixel font
       ├─ light/dark canvas + flat panel tokens
       ├─ square borders + visible focus color
       └─ screen CallbackShortcuts
            ├─ Ctrl+R → refresh
            ├─ Ctrl+H → history
            ├─ Ctrl+Shift+B → branches
            ├─ Ctrl+Shift+R → remotes
            └─ Ctrl+Enter → commit
```

1. `lib/src/app/pixel_theme.dart`에 두 palette, Jersey 15 typography,
   표면 규칙과 theme toggle을 모아 두어 화면마다 임의의 색을 다시 정하지
   않습니다. 선택 상태는 색상뿐 아니라 semantics와 텍스트로도 드러납니다.
2. Changes와 History는 넓은 창에서 목록/상세 pane을 나란히 보여주고,
   680 px보다 좁아지면 목록을 위에, 상세를 아래에 배치합니다. 따라서
   작은 데스크톱 창에서도 상세 내용을 잃지 않습니다.
3. 각 화면의 최상위 `Focus`가 단축키를 받고, 하단 status strip은 현재
   상태와 자주 쓰는 단축키를 함께 보여줍니다. Git 진단은 기존 typed
   `GitError.userMessage`를 사용하므로 원시 명령어나 인증 정보가 화면에
   나타나지 않습니다.

## 폴더별 역할

| 경로 | 역할 |
|---|---|
| `lib/main.dart` | 앱 시작과 의존성 조립 |
| `lib/src/app/` | 최상위 Material 앱과 픽셀 테마 |
| `lib/src/features/` | 화면별 UI와 컨트롤러 |
| `lib/src/backend/domain.dart` | 백엔드와 UI가 주고받는 값 객체 |
| `lib/src/backend/commit.dart` | commit ID와 post-commit status 결과 |
| `lib/src/backend/history.dart` | bounded log record와 graph lane 계산 |
| `lib/src/backend/remote.dart` | remote model, operation result, remote parser |
| `lib/src/backend/executor.dart` | Git 프로세스 실행, 출력 제한, 취소와 비밀값 가리기 |
| `lib/src/backend/error.dart` | 사용자 메시지와 진단 정보를 가진 오류 |
| `lib/src/backend/git_installation_service.dart` | Git 경로 검색과 버전 검사 |
| `lib/src/backend/repository_service.dart` | 저장소 확인과 세션용 ID 등록 |
| `lib/src/backend/status.dart` | Porcelain v2 상태 파싱과 변경 facet/snapshot 타입 |
| `lib/src/backend/discard.dart` | 만료 가능한 discard preview token 값 객체 |
| `lib/src/backend/diff.dart` | unified diff 라인, hunk, rename/binary 파싱과 scope 타입 |
| `lib/src/backend/dart_git_backend.dart` | 백엔드 서비스들을 연결하는 facade |
| `lib/src/backend/dart_git_gateway.dart` | Flutter 계약과 백엔드를 연결하는 얇은 adapter |
| `lib/src/features/repository/changes_controller.dart` | 상태 polling과 선택 상태 관리 |
| `lib/src/features/repository/changes_screen.dart` | staged/unstaged 등 그룹형 변경 화면 |
| `lib/src/features/repository/history_controller.dart` | history paging과 commit 선택 상태 |
| `lib/src/features/repository/history_screen.dart` | commit 목록, graph marker, detail 화면 |
| `lib/src/features/repository/remote_dialog.dart` | remote 작업, progress, cancellation 화면 |
| `test/backend/diff_parser_test.dart` | hunk 줄 번호, rename, binary, empty diff 테스트 |
| `test/backend/` | 실제 Git을 사용한 백엔드 테스트 |
| `test/features/` | fake gateway를 사용한 화면 테스트 |

## 새 Git 기능을 추가할 때

새 기능은 다음 순서로 추가하면 흐름을 잃지 않습니다.

1. `domain.dart` 또는 기능별 모델 파일에 UI에 필요한 결과 타입을 추가합니다.
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
- status 흐름을 이해하려면 `test/backend/status_parser_test.dart`에서
  Porcelain v2 레코드와 facet을 먼저 읽고,
  `test/features/repository/changes_screen_test.dart`에서 컨트롤러와 화면의
  연결을 확인합니다.
- diff 흐름은 `test/backend/diff_parser_test.dart`에서 unified diff가
  화면 모델로 바뀌는 과정을 먼저 읽고,
  `test/backend/dart_git_backend_test.dart`의 임시 저장소 테스트에서
  staged/working-tree/rename 호출을 확인합니다.
- 화면 흐름은 `test/features/repository/welcome_screen_test.dart`에서
  fake gateway가 호출 경계를 어떻게 대신하는지 확인합니다.
- `test/features/settings/git_settings_dialog_test.dart`는 저장된 Git
  경로와 재시도 상태가 컨트롤러를 통해 화면에 반영되는 흐름을 보여줍니다.
