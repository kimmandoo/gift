# Rust + Flutter Git GUI 설계

- 문서 상태: 구현 계획 작성 전 승인 후보
- 작성일: 2026-09-01
- 제품 가칭: Branchline

## 1. 목적

Branchline은 JetBrains IDE의 Git 도구 창에서 유용한 작업 흐름을 관찰하고, 이를 독립적인 Rust + Flutter Desktop 애플리케이션으로 재구현하는 크로스 플랫폼 Git GUI다. Windows, macOS, Linux에서 같은 핵심 기능과 일관된 조작 경험을 제공하는 것이 목표다.

여기서 “리버싱”은 정식으로 사용할 수 있는 JetBrains 제품의 화면과 공개된 Git 동작을 블랙박스 방식으로 관찰해 기능 요구사항과 테스트 사례로 변환한다는 뜻이다. JetBrains 바이너리 디컴파일, 내부 코드 추출, 프로토콜 우회, 라이선스 검증 우회, 아이콘·폰트·상표·화면 자산 복사는 범위에 포함하지 않는다. 결과물은 동작 흐름만 독립적으로 재현하는 clean-room 구현이어야 한다.

## 2. 사용자와 성공 기준

주 사용자는 IDE를 열지 않고도 변경 확인, stage, commit, 브랜치 전환, 이력 확인, pull/push를 빠르게 수행하려는 개발자다.

MVP가 성공한 것으로 보는 기준은 다음과 같다.

1. 세 운영체제에서 기존 저장소를 열고 staged, unstaged, untracked, conflicted 파일을 구분할 수 있다.
2. 파일 diff를 확인하고 파일 단위 stage/unstage/discard를 수행할 수 있다.
3. commit을 만들고 기본 브랜치를 생성하거나 전환할 수 있다.
4. 페이지 단위 Git 로그, 간단한 그래프, commit 상세와 파일 diff를 볼 수 있다.
5. 현재 upstream을 기준으로 fetch, fast-forward-only pull, 일반 push를 수행할 수 있다.
6. 모든 Git 작업은 UI를 멈추지 않으며, 장시간 네트워크 작업은 진행 상태와 취소 기능을 제공한다.
7. Git 자격 증명을 앱이 직접 저장하지 않고 사용자의 기존 Git, SSH, credential helper 설정을 사용한다.
8. Windows, macOS, Linux CI에서 Rust 테스트, Flutter 테스트, 통합 테스트와 배포 빌드가 통과한다.

## 3. MVP 범위

### 3.1 포함 기능

- 시작 화면: 저장소 폴더 열기, 최근 저장소, 최근 항목 제거
- 저장소 상태: staged, unstaged, untracked, conflicted 그룹과 브랜치/upstream 요약
- 변경 파일: 선택, 다중 선택, 파일 단위 stage/unstage, 지원되는 tracked working-tree 변경의 안전 확인 후 discard
- diff: unified diff, hunk 구분, 행 번호, 추가/삭제 강조, 바이너리/대용량 파일 안내
- commit: 메시지 작성, 현재 staged 파일 commit, 성공 후 상태 자동 갱신
- 로그: 200개 단위 페이지 조회, topology 기반 그래프 lane, 작성자·시간·subject, 상세 파일 목록과 diff
- 브랜치: 로컬/원격 브랜치 목록, 검색, 새 브랜치 생성, checkout/switch
- 원격 작업: fetch, upstream 대상 `pull --ff-only`, 일반 push, 확인 후 최초 upstream 설정 push
- 공통 동작: 새로고침, 진행 표시, 취소, 오류 상세 복사, 키보드 단축키, light/dark/system 테마

### 3.2 명시적 비범위

다음 기능은 JetBrains Git 경험의 장기적인 호환 목표에는 포함될 수 있지만 첫 구현 계획에는 넣지 않는다.

- merge/rebase 대화상자와 대화형 rebase
- cherry-pick, revert, reset UI
- stash/shelve
- 3-way conflict 편집기
- hunk 또는 행 단위 stage
- amend, GPG/SSH commit signing, hooks 관리
- blame, file history, submodule, worktree, Git LFS 전용 UI
- GitHub/GitLab 로그인, issue, pull/merge request
- 내장 터미널과 코드 편집기
- 여러 저장소를 동시에 여는 탭 또는 다중 창
- 강제 push와 자동 stash

비범위 기능은 MVP 코드에 빈 버튼이나 동작하지 않는 placeholder로 노출하지 않는다.

## 4. Clean-room 기능 분석 절차

JetBrains 기능을 재현할 때 각 작업을 다음 순서로 기록한다.

1. 공개 문서와 정상적인 제품 UI에서 사용자 작업을 관찰한다.
2. 입력 저장소 상태, 사용자 동작, 화면 결과, 실행 후 Git 상태를 행동 시나리오로 작성한다.
3. JetBrains 고유 명칭과 시각 자산을 제거하고 중립적인 요구사항으로 변환한다.
4. 동일한 저장소 fixture에서 기대 Git 상태를 검증하는 통합 테스트를 먼저 만든다.
5. 독립 구현 결과를 시나리오와 비교하되 내부 코드나 비공개 자산은 참조하지 않는다.

분석 결과는 이후 `docs/research/` 아래에 기능별 문서로 축적한다. 각 문서는 출처가 공개 문서인지, 직접 관찰인지 구분하고 관찰한 제품 버전과 OS를 기록한다. 이 설계 문서는 분석 방법만 정하며 실제 JetBrains 설치 파일이나 캡처 자산을 저장소에 포함하지 않는다.

## 5. 기술 선택

### 5.1 애플리케이션 구성

- UI: Flutter Desktop + Dart
- 상태 관리: Riverpod
- Rust 연결: `flutter_rust_bridge`
- Git 엔진: 사용자의 시스템 Git CLI
- Rust 비동기 실행: Tokio 기반 비동기 프로세스와 취소
- 로컬 설정: Flutter의 플랫폼별 application-support 디렉터리에 JSON 저장
- 지원 Git: Git 2.35 이상

Tauri와 WebView는 사용하지 않는다. Flutter는 네이티브 데스크톱 창과 렌더링을 담당하고 Rust는 Git 및 저장소 도메인 로직을 담당한다.

시스템 Git CLI를 선택하는 이유는 기존 SSH 키, credential helper, Git config, attributes, filters, hooks와의 호환성이 `libgit2` 단독 구현보다 높기 때문이다. 시작 시 `git --version`과 실행 경로를 확인하며, Git이 없거나 버전이 낮으면 설치 안내와 다시 확인 버튼을 제공한다. 설정 화면에서 Git 실행 파일을 직접 선택할 수도 있다.

### 5.2 논리 구조

```text
Flutter Desktop
  ├─ App shell / navigation
  ├─ Changes feature
  ├─ Log feature
  ├─ Branch feature
  ├─ Commit feature
  └─ Operation/error presentation
             │ generated async API / event stream
             ▼
flutter_rust_bridge boundary
             │
             ▼
Rust Git Core
  ├─ repository registry
  ├─ application services
  ├─ Git process executor
  ├─ porcelain/diff/log parsers
  ├─ mutation lock and cancellation
  └─ typed domain models and errors
             │ argv + cwd, no shell
             ▼
System Git / SSH / credential helper
```

Flutter는 Git 명령 문자열이나 Git 출력 형식을 알지 않는다. Rust는 widget, 색상, 선택 상태를 알지 않는다. 두 계층은 생성된 타입과 비동기 API만 공유한다.

### 5.3 제안 디렉터리 구조

```text
branchline/
  lib/
    main.dart
    src/
      app/
      features/
        repository/
        changes/
        commit/
        log/
        branches/
        remotes/
      shared/
      rust/                 # 생성된 bridge 코드
  native/
    Cargo.toml
    src/
      api/                  # flutter_rust_bridge 진입점
      domain/
      executor/
      parser/
      service/
      error.rs
  test/
  integration_test/
  native/tests/
  fixtures/
  docs/
```

MVP에서는 Rust를 여러 crate로 미리 분리하지 않는다. 하나의 Rust crate 안에서 모듈 경계를 유지하고 실제 재사용 요구가 생길 때만 workspace crate로 분리한다. 생성된 bridge 파일은 직접 수정하지 않는다.

## 6. 계층과 인터페이스

### 6.1 저장소 레지스트리

Flutter가 폴더를 열면 Rust는 경로를 canonicalize하고 `git rev-parse --show-toplevel`로 실제 루트를 확인한다. 성공하면 프로세스 수명 동안만 유효한 불투명 `RepositoryId`를 반환한다. 이후 Flutter는 임의의 작업 디렉터리 문자열 대신 이 ID를 전달한다.

최근 저장소에는 경로만 저장하며 앱 재시작 후 다시 열어 새 ID를 발급한다. 이동되었거나 삭제된 경로는 최근 목록에는 남겨 두되 “찾을 수 없음”으로 표시하고 사용자가 제거할 수 있게 한다.

### 6.2 Git 프로세스 실행기

모든 Git 호출은 하나의 실행기를 거친다.

- 셸을 사용하지 않고 실행 파일, argv, cwd를 분리한다.
- 파일 인자는 `--` 또는 NUL 구분 pathspec 입력으로 옵션과 분리한다.
- stdout/stderr를 제한된 버퍼나 스트림으로 읽어 교착을 방지한다.
- read 작업과 mutation 작업을 구분한다.
- repository별 mutation은 한 번에 하나만 실행한다.
- operation ID, 시작 시각, 종류, 취소 토큰을 관리한다.
- 오류 로그에서 URL 사용자 정보와 비밀 가능성이 있는 값을 제거한다.
- 사용자가 설정한 Git 환경을 상속하되 앱 내부 비밀 환경 변수는 전달하지 않는다.

`discard`, `commit`, `switch`, `pull`, `push` 같은 mutation이 성공하면 해당 저장소 snapshot generation을 증가시키고 관련 read query를 무효화한다. 오래된 generation의 응답은 Flutter가 화면에 적용하지 않는다.

### 6.3 주요 API

bridge의 공개 API는 명령 문자열 대신 의도가 드러나는 함수로 제한한다.

```text
open_repository(path) -> RepositoryOpened
get_status(repository_id) -> RepositorySnapshot
get_file_diff(repository_id, change_id, options) -> FileDiff
get_commit_file_diff(repository_id, commit_id, parent_index?, history_file_id, options) -> FileDiff
stage_files(repository_id, change_ids) -> MutationResult
unstage_files(repository_id, change_ids) -> MutationResult
prepare_discard(repository_id, change_ids) -> DiscardPreview
discard_files(repository_id, confirmation_token) -> MutationResult
commit(repository_id, message) -> CommitResult
get_log_page(repository_id, cursor, page_size) -> CommitPage
get_commit_details(repository_id, object_id, parent_index?) -> CommitDetails
list_branches(repository_id) -> BranchList
list_remotes(repository_id) -> RemoteList
create_branch(repository_id, name, start_point) -> MutationResult
switch_branch(repository_id, branch_ref) -> MutationResult
create_tracking_branch_and_switch(repository_id, remote_branch_ref, local_name) -> MutationResult
fetch(repository_id, remote_id) -> OperationId
pull_ff_only(repository_id) -> OperationId
push(repository_id) -> OperationId
push_set_upstream(repository_id, remote_id, remote_branch_name) -> OperationId
operation_events(operation_id) -> Stream<OperationEvent>
cancel_operation(operation_id) -> CancelResult
```

`prepare_discard`는 현재 status를 다시 읽고 지원되는 대상인지 확인한 뒤 대상 경로, 폐기될 working-tree 상태, 보존될 staged 상태, snapshot generation을 포함한 `DiscardPreview`와 60초 동안 유효한 confirmation token을 반환한다. Flutter는 이 preview로 확인 대화상자를 표시한다. `discard_files`는 token에 묶인 대상만 처리하며 새 change ID를 받지 않는다. 실행 직전에 generation과 대상 상태가 달라졌으면 `StaleConfirmation`으로 거부한다. 단순 boolean은 실수나 stale UI로 인한 삭제를 막기에 부족하므로 사용하지 않는다.

`get_commit_details`와 `get_commit_file_diff`는 동일한 optional `parent_index` 규칙을 사용한다. root commit은 parent가 없으므로 `None`만 허용하고 empty tree와 비교한다. parent가 하나 이상이면 `Some(index)`만 허용하며 UI의 기본값은 `Some(0)`이다. merge commit에서 parent 선택을 바꾸면 `get_commit_details`를 다시 호출해 그 parent와 비교한 `HistoryFileChange` 목록을 새로 받는다. 따라서 file ID는 선택한 commit, parent 기준과 generation에 묶이고 다른 기준의 diff 요청에 재사용할 수 없다.

각 `HistoryFileChange`에는 불투명 history file ID, 이전/현재 표시 경로와 변경 종류가 있다. `get_commit_file_diff`는 이 ID를 사용하며 표시 경로를 pathspec으로 재사용하지 않는다. Rust는 `parent_index`가 commit의 실제 parent 범위와 file ID에 기록된 기준에 모두 일치하는지 검증한다.

### 6.4 핵심 모델

- `RepositorySnapshot`: 루트, HEAD 상태, local branch, upstream, ahead/behind, generation, change groups
- `FileChange`: 불투명 change ID, 표시 경로, 이전 경로, staged/unstaged 상태, change kind, conflict kind
- `FileDiff`: 파일 메타데이터, hunks, truncated 여부, binary 여부
- `DiffHunk` / `DiffLine`: 범위, line kind, old/new line number, text
- `CommitSummary`: object ID, parents, graph lane 정보, author, timestamp, subject, refs
- `CommitDetails`: summary, body, parent 목록, 선택된 optional parent index, 해당 비교 기준의 `HistoryFileChange` 목록과 통계
- `HistoryFileChange`: 불투명 file ID, 이전/현재 표시 경로, change kind
- `BranchRef`: 불투명 ref ID, 표시 이름, local/remote, current, upstream, ahead/behind
- `RemoteInfo`: 불투명 remote ID, 표시 이름, fetch/push URL의 redacted 형태
- `RemoteList`: repository generation과 `RemoteInfo` 목록
- `DiscardPreview`: confirmation token, 만료 시각, generation, 폐기/보존 상태 설명
- `OperationEvent`: started, progress, output summary, completed, failed, cancelled
- `GitError`: category, user message, diagnostic, retryability, exit code

Unix의 비 UTF-8 파일명은 Rust 내부에서 원시 바이트를 보존한다. Flutter에는 손실 허용 표시 문자열과 불투명 ID만 전달하므로, 사용자가 보게 되는 문자열을 다시 Git pathspec으로 사용하지 않는다.

## 7. Git 명령과 동작 정책

파서는 사람이 읽는 기본 출력이나 locale에 의존하지 않는다.

- 상태: `git status --porcelain=v2 -z --branch`
- working tree diff: `git diff --no-ext-diff --no-color --find-renames -- <pathspec>`
- staged diff: `git diff --cached --no-ext-diff --no-color --find-renames -- <pathspec>`
- stage: NUL 구분 pathspec을 사용하는 `git add`
- unstage: `git restore --staged`를 기본으로 사용
- commit: 메시지를 stdin 파일 입력으로 전달하는 `git commit -F -`
- 브랜치 목록: 명시적 구분자를 포함한 `git for-each-ref`
- 로그: `--topo-order`와 명시적 NUL 구분 format을 사용하고 200개씩 조회
- 브랜치 생성/전환: `git switch` 계열 명령
- pull: upstream이 존재할 때만 `git pull --ff-only --progress`
- push: upstream이 존재할 때 일반 `git push --progress`

MVP는 자동 merge commit, 자동 rebase, 강제 push, 자동 stash를 수행하지 않는다. fast-forward가 불가능하거나 dirty worktree 때문에 전환할 수 없으면 Git 상태를 바꾸지 않고 원인과 사용자가 다음에 할 수 있는 작업을 설명한다.

discard는 working-tree facet이 있는 tracked modified/deleted/type-changed 파일에만 제공한다. staged와 unstaged 변경이 동시에 있으면 `git restore --worktree`로 working tree를 index 상태로 복원하므로 staged 내용은 보존된다. staged-only, untracked, conflicted, renamed/copied 항목에는 MVP의 discard를 제공하지 않고 이유를 표시한다. 사용자는 staged-only 변경을 먼저 unstage한 뒤 discard할 수 있다. untracked 파일 삭제와 conflict 해결은 외부 도구에서 수행한다. 이 정책은 `git clean`, index 손실, rename 양쪽 경로의 부분 삭제를 피한다.

`list_remotes`는 Git remote 이름을 불투명 remote ID로 바꿔 반환한다. `fetch`와 `push_set_upstream`은 이 ID만 받고 실행 직전에 같은 repository의 현재 remote인지 재검증한다. 표시 이름이나 redacted URL을 다시 명령 인자로 사용하지 않는다.

upstream이 없는 branch에서는 pull과 기본 push를 비활성화한다. remote가 정확히 하나일 때 “upstream 설정 후 push” 확인 화면에서 `push_set_upstream`을 호출한다. remote가 여러 개면 사용자가 `RemoteList`의 항목과 유효한 branch 이름을 선택한 뒤 같은 API를 호출한다. Rust는 현재 local branch를 동작 직전에 다시 확인하고 `git push --set-upstream <remote> <local>:<remote-branch>`를 실행한다. detached HEAD에서는 이 동작을 허용하지 않는다.

branch popup에서 local branch를 선택하면 `switch_branch`를 사용한다. remote branch를 선택했을 때는 detached HEAD로 checkout하지 않는다. 동일 remote branch를 추적하는 local branch가 있으면 그 local branch로 전환하고, 없으면 제안된 local 이름을 확인한 후 `create_tracking_branch_and_switch`가 `git switch --track -c <local> <remote-ref>`를 실행한다.

Git hook은 사용자의 기존 설정대로 실행한다. hook 실패는 commit 실패로 표시하고 stderr 진단을 노출하되 hook을 우회하는 버튼은 제공하지 않는다.

## 8. 상태 갱신과 동시성

앱은 다음 시점에 status를 다시 읽는다.

- 저장소를 처음 열었을 때
- 창이 다시 foreground가 되었을 때
- 앱이 수행한 mutation이 끝났을 때
- 사용자가 새로고침을 실행했을 때
- 창이 활성 상태일 때 3초 간격의 lightweight polling이 변경을 감지했을 때

polling은 이전 status 요청이 끝나지 않았거나 mutation이 진행 중이면 중첩하지 않는다. snapshot hash가 같으면 Flutter로 전체 변경 목록을 다시 보내지 않는다. 대규모 저장소에서 재귀 파일 감시자가 OS 자원 한도를 소모하지 않도록 MVP에는 recursive watcher를 넣지 않는다.

Rust read 작업은 동시에 실행할 수 있지만 동일 저장소의 mutation은 직렬화한다. Flutter는 각 요청의 repository ID와 generation을 확인해 이전 선택이나 이전 상태에서 도착한 응답을 버린다.

## 9. UI 설계

### 9.1 시각 원칙

- JetBrains 화면을 픽셀 단위로 복제하지 않고 정보 밀도와 작업 흐름만 참고한다.
- Material 3를 기반으로 하되 과한 elevation, gradient, animation을 사용하지 않는다.
- 시스템 light/dark 테마를 따르며 사용자가 고정할 수 있다.
- 색상만으로 상태를 구분하지 않고 아이콘, 레이블, +/- 기호를 함께 사용한다.
- 모든 주요 작업은 키보드만으로 실행 가능해야 한다.
- JetBrains 상표, 로고, 아이콘, 전용 폰트를 포함하지 않는다.

### 9.2 창 구성

```text
┌ Repository / Branch ───────────── Fetch  Pull  Push ┐
├ Changes | Log ──────────────────────────────────────┤
│ Changes tree       │ Diff viewer        │ Commit    │
│ staged/unstaged    │ unified hunks      │ message   │
│ untracked/conflict │                    │ files     │
│                    │                    │ action    │
└ Status / progress / error summary ──────────────────┘
```

- 상단 bar는 저장소, 현재 branch, ahead/behind, fetch/pull/push만 표시한다.
- `Changes` 화면은 왼쪽 변경 목록, 가운데 diff, 오른쪽 commit panel의 3열 구조다.
- 창 폭이 좁아지면 commit panel을 오른쪽 drawer로 접고 변경 목록의 최소 폭을 유지한다.
- `Log` 화면은 graph가 포함된 commit 목록과 선택 commit 상세의 2열 구조다.
- branch 선택기는 검색 가능한 popup이며 local과 remote를 구분한다.
- 장시간 작업은 하단 status bar와 operation drawer에 표시한다.

### 9.3 주요 상호작용

- 파일 한 번 클릭: diff 표시
- 체크박스 또는 명시적 Stage/Unstage 버튼: staging 상태 변경
- 파일 다중 선택: 동일 작업 일괄 적용
- discard: `prepare_discard`가 반환한 폐기/보존 상태를 설명하는 확인 대화상자. 지원하지 않는 상태에서는 버튼 대신 이유 표시
- commit: staged 파일이 없거나 메시지가 비어 있으면 비활성화하고 이유 표시
- pull/push: 현재 branch와 upstream을 동작 직전에 다시 검증
- 오류: 짧은 사용자 메시지와 접을 수 있는 진단 세부 정보 제공

기본 단축키는 `Ctrl`을 사용하고 macOS에서는 해당 동작을 `Cmd`로 매핑한다.

- 저장소 열기: `Ctrl/Cmd+O`
- 새로고침: `F5` 또는 `Cmd+R`
- commit message focus: `Ctrl/Cmd+K`
- commit 실행: `Ctrl/Cmd+Enter`
- 검색/필터 focus: `Ctrl/Cmd+F`
- 작업 취소: `Esc`

OS 예약 단축키와 충돌하는 경우 해당 플랫폼 runner에서 별도 매핑을 사용하고 메뉴에 실제 단축키를 표시한다.

## 10. Diff와 로그 성능

변경 목록과 로그 목록은 Flutter lazy list로 렌더링한다. diff는 hunk 단위 widget으로 나누고 화면에 가까운 부분만 생성한다.

- 로그 기본 page size: 200 commits
- 단일 diff 표시 한도: 5 MiB 또는 20,000 lines 중 먼저 도달한 값
- 한도를 넘으면 앞부분만 표시하고 “터미널 또는 외부 도구에서 열기” 안내 제공
- binary 파일은 내용 대신 크기와 변경 종류 표시
- status와 파서 작업은 Rust thread에서 수행하고 Flutter UI isolate에서 대용량 patch를 파싱하지 않음
- 네트워크 출력은 bounded stream으로 전달하며 전체 stderr를 메모리에 무제한 보관하지 않음

성능 한도는 데이터 손실을 뜻하지 않는다. Git 작업은 전체 파일에 적용되며 UI preview만 잘린다. 잘림 여부는 항상 화면에 명시한다.

## 11. 오류 처리

Rust는 오류를 다음 category로 분류한다.

- GitNotFound / UnsupportedGitVersion
- NotRepository / RepositoryMoved
- InvalidRevision / DetachedHead / UnbornBranch
- DirtyWorktree / MergeConflict / NonFastForward
- AuthenticationRequired / PermissionDenied / NetworkUnavailable
- HookRejected / Cancelled / Timeout
- ParseFailure / UnsupportedRepositoryState / Internal

원격 Git process는 pseudo-terminal을 만들지 않고 stdin을 닫은 상태로 실행하며 `GIT_TERMINAL_PROMPT=0`을 설정한다. Unix에서는 Git child를 `setsid`로 새 session에 넣어 controlling terminal을 제거하고, Windows에서는 새 process group과 console window를 만들지 않는 creation flags를 사용한다. 따라서 descendant OpenSSH가 `/dev/tty`나 console 입력을 요구할 수 없고 terminal 전용 prompt는 실패한다.

사용자가 이미 구성한 OS credential helper, 별도 GUI AskPass, SSH agent와 `GIT_ASKPASS`/`SSH_ASKPASS` 환경은 그대로 사용할 수 있다. 이 외부 helper는 terminal이 없어도 독립 GUI 또는 agent protocol로 동작한다. 앱 내부 username/password/token/passphrase 입력창과 SSH host-key 승인창은 MVP에서 제공하지 않는다. GUI AskPass가 구성되지 않은 passphrase key나 host-key 신뢰가 필요한 경우 사용자가 터미널에서 먼저 agent/known_hosts를 설정하도록 안내한다.

외부 credential helper가 자체 GUI를 표시하는 동안 process는 실행 상태로 유지되며 사용자는 언제든 취소할 수 있다. 인증 관련 exit와 redacted stderr는 `AuthenticationRequired` 또는 `PermissionDenied`로 분류한다. 별도의 `authentication-required` stream event로 비밀을 요청하지 않는다. 이 정책으로 Flutter/Rust bridge를 통해 credential이 이동하거나 보이지 않는 stdin prompt 때문에 작업이 무기한 멈추는 상황을 피한다.

사용자 메시지는 다음 행동을 제안하지만 자동으로 위험한 복구를 실행하지 않는다. 예를 들어 non-fast-forward push에는 fetch 후 상태 확인을 제안하며 force push를 제안하지 않는다. parse failure에는 Git 버전, 실행한 동작, redacted stderr를 포함한 진단 복사 기능을 제공한다.

취소는 먼저 child process에 정상 종료 신호를 보내고 짧은 유예 후 종료한다. process tree 정리는 Windows와 Unix adapter로 분리한다. 취소 뒤에는 status를 다시 읽어 Git이 실제로 변경한 상태를 화면에 반영한다.

## 12. 보안과 개인정보

- 모든 Git 실행은 shell-free argv 방식이다.
- Flutter가 전달한 repository ID, ref ID, change ID는 Rust registry에서 다시 검증한다.
- ref name은 Git의 ref format 규칙으로 검증한다.
- 파일 표시 문자열을 명령 인자로 재사용하지 않는다.
- commit message와 path를 로그에 기본 기록하지 않는다.
- remote URL의 사용자 정보와 credential 가능 값은 진단에서 redaction한다.
- 비밀번호, 토큰, SSH private key를 앱 설정에 저장하거나 bridge로 전달하지 않는다.
- destructive discard에는 대상 재검증과 confirmation token이 필요하다.
- 앱 업데이트 자동 실행과 임의 코드 다운로드는 MVP에 포함하지 않는다.

## 13. 플랫폼 및 배포

### 13.1 공통

각 운영체제 산출물은 해당 운영체제의 CI runner에서 빌드한다. release에는 SHA-256 checksum과 Git 최소 버전, signing/notarization 상태, 최초 실행 방법을 포함한다.

- Windows: x64 portable ZIP을 기본 산출물로 제공하고 설치형 패키지는 후속 release로 둔다.
- Linux: x64 AppImage와 `.deb`를 제공하고 필요한 GTK/system library를 명시한다.
- macOS: Apple Silicon과 Intel을 포함하는 universal `.app` 및 DMG를 제공한다.

추가 CPU architecture는 Flutter와 CI runner 지원을 검증한 뒤 별도 release target으로 추가한다. MVP의 “세 OS 지원”은 위 기본 architecture 산출물을 뜻한다.

### 13.2 macOS ad-hoc signed 배포

Apple Developer ID와 notarization 없이 배포하는 MVP에서는 self-signed certificate가 아니라 ad-hoc signing을 사용한다. release script는 Flutter framework, Rust dynamic library와 다른 nested Mach-O를 안쪽부터 명시적으로 서명한 뒤 마지막에 outer `.app`을 서명한다. `--deep`은 누락된 nested component를 대신 서명하는 수단으로 사용하지 않고 최종 검증에만 사용한다.

```text
codesign --force --sign - <nested Mach-O components, inside-out>
codesign --force --sign - Branchline.app
codesign --verify --deep --strict Branchline.app
```

release에는 “ad-hoc signed이며 Developer ID signed 또는 notarized 상태가 아님”을 명시한다. ad-hoc signing은 앱 번들의 로컬 무결성을 확인하지만 Apple이 신뢰하는 배포 서명이 아니며 Gatekeeper를 자동 통과시키지 않는다. 다운로드한 앱의 최초 실행은 Finder에서 우클릭 후 `Open`을 선택하거나 System Settings의 Privacy & Security에서 사용자가 직접 허용해야 한다. 이 절차를 release 문서에 설명한다.

앱 자체가 quarantine attribute를 제거하거나 Gatekeeper 설정을 변경하거나 사용자 승인 없이 보안 정책을 우회해서는 안 된다. 향후 Apple Developer 계정이 준비되면 동일 build pipeline에 Developer ID signing과 notarization 단계를 추가할 수 있다.

## 14. 테스트 전략

### 14.1 Rust 단위 테스트

- porcelain v2, branch, log, diff parser golden fixtures
- rename, copy, 공백·탭·줄바꿈·Unicode 및 Unix 비 UTF-8 경로
- merge conflict, detached HEAD, unborn branch, bare repo 오류
- exit code와 stderr의 typed error 변환
- URL 및 credential redaction
- generation과 repository mutation lock

### 14.2 Rust 통합 테스트

테스트마다 임시 저장소와 로컬 bare remote를 생성한다. 실제 Git CLI로 다음 흐름을 검증한다.

- open → edit → status → stage → commit
- stage → unstage, tracked working-tree discard, staged 내용 보존, stale confirmation 거부
- untracked/conflicted/renamed 항목에서 discard 비활성화
- branch create/switch와 dirty worktree 거부
- paginated log와 merge topology fixture
- root commit의 `None` 기준과 merge commit의 parent별 file list/diff
- local bare remote를 이용한 fetch/pull/push 및 non-fast-forward 실패
- remote branch에서 tracking local branch 생성, upstream 최초 설정 push, detached HEAD 거부
- stale/다른 repository의 remote ID 거부
- 비대화형 credential/SSH 실패가 hang 없이 typed error로 끝나는지 검증
- 공백, 대시, shell metacharacter가 포함된 경로
- hook 실패와 사용자 config 누락
- operation cancel 뒤 실제 저장소 상태 재조회

네트워크 서비스나 실사용 credential에 의존하지 않는다.

### 14.3 Flutter 테스트

- Riverpod controller 단위 테스트
- Changes, Diff, Commit, Log, Branch popup widget 테스트
- 빈 상태, loading, stale response, 오류, 취소 상태
- light/dark theme와 주요 창 폭 golden 테스트
- 키보드 focus traversal과 OS별 shortcut 테스트

### 14.4 Bridge 및 E2E 테스트

- 생성된 Dart/Rust type contract compile 검사
- 실제 Rust core를 연결한 Flutter integration smoke test
- Windows, macOS, Linux에서 저장소 열기와 local commit smoke test
- release artifact 실행, Git 탐지, ad-hoc signature 검증

## 15. 완료 조건

MVP는 다음 항목을 모두 만족해야 완료로 판단한다.

1. 섹션 3.1의 사용자 흐름이 세 OS smoke test에서 동작한다.
2. shell metacharacter와 특수 파일명 fixture가 명령 주입 없이 통과한다.
3. local bare remote만 사용하는 fetch/pull/push 통합 테스트가 통과한다.
4. destructive discard가 확인 없이 실행되지 않는다.
5. UI isolate가 Git process 또는 patch parsing 때문에 block되지 않는다.
6. 지원 배포 artifact와 checksum을 CI가 생성한다.
7. macOS 앱은 ad-hoc signature 검증을 통과하며 Developer ID 미서명·미공증 상태의 최초 실행 안내가 포함된다.
8. JetBrains의 코드, 상표, 아이콘, 캡처 자산이 결과물에 포함되지 않는다.

## 16. 구현 순서의 경계

이 문서 이후 작성할 구현 계획은 하나의 MVP를 다음 수직 단계로 나눈다.

1. Flutter/Rust bridge와 임시 저장소 기반 테스트 harness
2. 저장소 열기, typed status, Changes 화면
3. diff와 stage/unstage/discard
4. commit과 자동 상태 갱신
5. paginated log와 branch 생성/전환
6. fetch, fast-forward pull, push, progress/cancel
7. 세 OS 패키징, macOS ad-hoc signing, E2E 검증

각 단계는 Rust 통합 테스트와 Flutter 표시를 함께 완성한다. 전체 Rust core를 먼저 만든 뒤 UI를 한꺼번에 붙이는 방식은 사용하지 않는다.
