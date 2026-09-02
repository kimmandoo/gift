# GIFT Brand Rename and Pixel Logo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the working-tree product identity to `gift` and replace the
existing mascot/logo artwork with a clear 2D pixel-game shiba-and-gift brand.

**Architecture:** Keep the existing Flutter/Dart boundaries and behavior. Apply
one deterministic identity migration across source, tests, documentation,
desktop metadata, and output paths, then install one generated square mascot
asset as the source for Flutter and desktop icons. Build the README wordmark
deterministically from that mascot and the bundled Jersey 15 font so product
text is exact.

**Tech Stack:** Flutter 3.47.2, Dart 3.13.2, `dart:io`, Windows PowerShell
for checked-in raster derivatives, PNG/ICO desktop assets, Jersey 15 font.

---

## File map

Identity migration touches every tracked text file currently containing the
product name, including `pubspec.yaml`, Dart sources and tests, README,
`TASKS.md`, `CHANGELOG.md`, `docs/`, `.serena/project.yml`, CI, and the Linux,
macOS, and Windows runner metadata. The source file
`lib/src/app/gift_app.dart` becomes `lib/src/app/gift_app.dart`; the root
widget becomes `GiftApp`.

Brand assets have these responsibilities:

- `assets/images/gift_icon.png`: 1024x1024 square pixel mascot, bundled by
  Flutter and used as the source for platform icons.
- `assets/images/gift_logo.png`: deterministic 1280x512 README wordmark made
  from the same mascot and an exact `GIFT` pixel-font label.
- `windows/runner/resources/app_icon.ico`: Windows multi-size icon derived
  from `gift_icon.png`.
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png`: macOS
  icon sizes derived from `gift_icon.png`; `Contents.json` keeps its existing
  size mapping.

The unused alternate mascot JPEGs are removed after a reference scan so no
old visual identity remains in the working tree.

## Task 1: Add the identity contract test first

**Files:**

- Create: `test/branding_test.dart`
- Modify: `test/app_boot_test.dart`
- Modify: `test/backend/dart_git_backend_test.dart`
- Modify: `integration_test/app_smoke_test.dart`

- [ ] **Step 1: Add a failing package/app contract test**

Create `test/branding_test.dart` with the following exact test. It documents
the user-visible package name and checks that the root app exposes the same
title after the rename:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gift/src/app/gift_app.dart';

void main() {
  testWidgets('uses the GIFT product identity', (tester) async {
    await tester.pumpWidget(const GiftApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'gift');
  });
}
```

Update the existing app boot, backend health, and integration smoke imports and
expectations to use these exact replacements:

```text
package:gift             -> package:gift
src/app/gift_app.dart    -> src/app/gift_app.dart
GiftApp                  -> GiftApp
'gift'                   -> 'gift'
```

- [ ] **Step 2: Run the focused tests and confirm the expected RED state**

Run:

```powershell
flutter test test/branding_test.dart test/app_boot_test.dart test/backend/dart_git_backend_test.dart
```

Expected result: the tests fail because the `gift` package/import and
`GiftApp` source do not exist yet. Do not change runtime behavior to make a
different assertion pass.

## Task 2: Rename the product identity in code and metadata

**Files:**

- Rename: `lib/src/app/gift_app.dart` to `lib/src/app/gift_app.dart`
- Modify: all tracked text files returned by the repository-wide legacy scan,
  excluding `.git`, build output, and dependency caches
- Rename: `assets/images/gift_icon.png` to `assets/images/gift_icon.png`
- Rename: `assets/images/gift_logo.png` to `assets/images/gift_logo.png`
- Rename: `assets/images/gift_mascot_shiba.jpg` to
  `assets/images/gift_mascot_shiba.jpg` before removing it in Task 3
- Rename: `assets/images/gift_shiba_icon.jpg` to
  `assets/images/gift_shiba_icon.jpg` before removing it in Task 3
- Rename: `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md` to
  `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md`

- [ ] **Step 1: Record the exact text-file set before replacement**

Run:

```powershell
rg -l -i --hidden -g '!.git/**' -g '!build/**' -g '!dist/**' -g '!node_modules/**' 'gift|app\.kimmandoo' .
```

Review that the output contains only text/source/metadata files and the four
product-named image paths. Do not pass binary images to a text replacement.

- [ ] **Step 2: Rename product-named files with Git-aware moves**

Run these exact moves:

```powershell
git mv lib/src/app/gift_app.dart lib/src/app/gift_app.dart
git mv assets/images/gift_icon.png assets/images/gift_icon.png
git mv assets/images/gift_logo.png assets/images/gift_logo.png
git mv assets/images/gift_mascot_shiba.jpg assets/images/gift_mascot_shiba.jpg
git mv assets/images/gift_shiba_icon.jpg assets/images/gift_shiba_icon.jpg
git mv docs/superpowers/plans/2026-09-02-gift-dart-mvp.md docs/superpowers/plans/2026-09-02-gift-dart-mvp.md
```

- [ ] **Step 3: Apply the deterministic identity replacements to text files**

For each text path from Step 1, apply the following ordered replacements while
preserving the file's existing encoding and line endings:

```text
GIFT -> GIFT
Gift -> Gift
gift -> gift
app.kimmandoo.gift -> app.kimmandoo.gift
```

The replacement must update package imports, `GiftApp` references, the
backend health product, MaterialApp title, asset paths, temporary test names,
CI artifact names, macOS/Linux/Windows metadata, and documentation. Keep
generic words such as `Git`, `git add`, and repository paths unchanged.

- [ ] **Step 4: Run the focused tests and confirm the GREEN state**

Run:

```powershell
flutter test test/branding_test.dart test/app_boot_test.dart test/backend/dart_git_backend_test.dart
```

Expected result: all focused tests pass and imports resolve through the new
package name.

- [ ] **Step 5: Check migration completeness before branding work**

Run:

```powershell
rg -n -i --hidden -g '!.git/**' -g '!build/**' -g '!dist/**' -g '!node_modules/**' 'gift|app\.kimmandoo\.gift' .
```

Expected result: no output. If a result is a historical explanation that is
still required, rewrite it as a generic "previous product identity" statement
so the current working tree remains consistently branded.

## Task 3: Replace the logo and derive desktop icon assets

**Files:**

- Modify: `assets/images/gift_icon.png`
- Modify: `assets/images/gift_logo.png`
- Modify: `windows/runner/resources/app_icon.ico`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png`
- Delete: `assets/images/gift_mascot_shiba.jpg`
- Delete: `assets/images/gift_shiba_icon.jpg`

- [ ] **Step 1: Generate the square source mascot**

Use the image-generation skill for a new raster image with this prompt:

```text
Create a clean square 2D pixel-art game mascot icon for a desktop Git client named GIFT. Show a friendly orange shiba sitting behind a small present box with a mint-green ribbon. Use a deep navy background and near-black 1-2 pixel outline, warm cream muzzle, coral cheeks, orange fur, and mint ribbon. Hard pixel clusters only, crisp nearest-neighbor edges, limited 8-color palette, no gradients, no blur, no glow, no photography, no border text, no letters, no watermark. Center the silhouette with generous padding so it remains recognizable at 16x16 and 32x32.
```

Save the accepted result as `assets/images/gift_icon.png` at 1024x1024. Inspect
the rendered image and reject any result with accidental lettering, blurry
edges, excessive detail, or a silhouette that is not legible when reduced.

- [ ] **Step 2: Build the exact README wordmark from the source icon**

Create `assets/images/gift_logo.png` as a deterministic 1280x512 PNG with a deep navy
pixel background. Place a 384x384 nearest-neighbor copy of `gift_icon.png` at the
left and draw the exact uppercase text `GIFT` at the right using
`assets/fonts/Jersey15-Regular.ttf`, with a cream face, mint shadow, and
near-black pixel-style outline. Keep the text inside the canvas and verify it
reads exactly `GIFT`; the generated artwork must not provide the wordmark
letters.

- [ ] **Step 3: Derive the macOS PNG sizes**

Resize `gift_icon.png` with nearest-neighbor sampling to the exact pixel sizes
listed below and overwrite each corresponding file:

```text
app_icon_16.png    16x16
app_icon_32.png    32x32
app_icon_64.png    64x64
app_icon_128.png   128x128
app_icon_256.png   256x256
app_icon_512.png   512x512
app_icon_1024.png  1024x1024
```

Keep `Contents.json` unchanged because its existing entries already map the
retina slots to these files.

- [ ] **Step 4: Rebuild the Windows ICO**

Create a valid multi-image ICO from nearest-neighbor PNG derivatives at
16x16, 32x32, 48x48, 64x64, 128x128, and 256x256. Preserve alpha, write a
six-byte ICO header and one directory entry per image, and store the PNG
payloads without recompressing their pixel data. The ICO directory dimension
byte cannot represent 512px (zero means 256px), so the standard Windows
maximum is used. Overwrite `windows/runner/resources/app_icon.ico` and verify
its directory contains all six sizes.

- [ ] **Step 5: Remove unreferenced alternate images**

After confirming `rg -n 'gift_mascot_shiba|gift_shiba_icon' .` returns no
references, remove the two renamed JPEGs. Their old Git contents remain
recoverable from the preceding commit.

- [ ] **Step 6: Inspect the final visual assets**

Use image inspection on `gift_icon.png`, `gift_logo.png`, one small macOS
variant, and the Windows ICO. Confirm crisp edges, consistent palette, exact
`GIFT` spelling in the wordmark, and recognizable mascot silhouette.

## Task 4: Update user-facing branding and release documentation

**Files:**

- Modify: `README.md`
- Modify: `lib/src/features/repository/welcome_screen.dart`
- Modify: `CHANGELOG.md`
- Modify: `docs/WORK_CHECKPOINT.md`
- Modify: `docs/RELEASING.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/research/jetbrains-git-mvp-behavior.md`
- Modify: `docs/POST_MVP_ROADMAP.md`
- Modify: `TASKS.md`

- [ ] **Step 1: Update README logo markup and prose**

Use the new asset and exact accessible label:

```html
<img src="assets/images/gift_logo.png" alt="GIFT pixel shiba mascot" width="360" style="image-rendering: pixelated;" />

# GIFT
```

Change current-product prose to `GIFT`/`gift`, and update clone, `cd`, build
artifact, and license examples to the new repository/package identity while
leaving generic Git instructions unchanged.

- [ ] **Step 2: Update the welcome screen branding**

The app bar and semantic image label must use these exact values:

```dart
title: const Text('GIFT'),
image: const AssetImage('assets/images/gift_icon.png'),
semanticLabel: 'GIFT pixel mascot',
```

The `MaterialApp.title` remains the machine-readable lowercase value `gift`.

- [ ] **Step 3: Add the dated changelog entry in past tense**

Under `## 2026-09-02`, add:

```markdown
- breaking(branding): renamed the product identity and desktop metadata to gift and replaced the mascot with a 2D pixel-game logo.
```

Do not use a `release(scope):` commit subject or create a release tag.

- [ ] **Step 4: Rewrite checkpoint and planning references**

Update `docs/WORK_CHECKPOINT.md` so it records this session's active task,
changed files, verification commands/results, and the exact next action. The
checkpoint must not claim a future task is complete. Rename any old plan path
to `docs/superpowers/plans/2026-09-02-gift-dart-mvp.md` and describe the
current identity as `gift`.

## Task 5: Full verification and handoff

**Files:**

- Modify: `docs/WORK_CHECKPOINT.md` with final verification results
- No source changes expected after verification unless a check fails

- [ ] **Step 1: Format and analyze**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
```

Expected result: formatting exits 0 with no changed files and Flutter reports
no diagnostics.

- [ ] **Step 2: Run the full test suite**

Run:

```powershell
flutter test
```

Expected result: every existing test plus `test/branding_test.dart` passes.

- [ ] **Step 3: Run repository verification and diff checks**

Run:

```powershell
dart run tool/verify.dart
git diff --check
rg -n -i --hidden -g '!.git/**' -g '!build/**' -g '!dist/**' -g '!node_modules/**' 'gift|app\.kimmandoo\.gift' .
```

Expected result: the verification helper passes, `git diff --check` is clean,
and the legacy scan prints no output. If the Linux native build is attempted,
record the existing `libgtk-3-dev` host-package blocker without treating it as
a source failure.

- [ ] **Step 4: Confirm the final status and commit the session**

Run:

```powershell
git status --short --branch
git diff --stat
git diff --name-status
```

Review that only the requested identity, documentation, and asset changes are
present. Update the checkpoint with the actual test counts and any blocker,
then commit all remaining session changes with:

```powershell
git add -A
git commit -m "feat(branding): rename product to gift and refresh pixel logo"
```

Expected result: one ordinary feature commit is created locally, with no
release tag and no `release(scope):` subject.

## Self-review

- The spec's scope is covered by Tasks 1-4; verification and checkpoint
  requirements are covered by Task 5.
- The logo prompt explicitly excludes generated lettering, while the README
  wordmark step renders exact text deterministically.
- Package/import/symbol/file-name mappings are consistent: `gift`, `GiftApp`,
  `gift_app.dart`, and `app.kimmandoo.gift`.
- No task depends on rewriting Git history or changing persisted theme/workspace
  keys, so existing user data behavior stays compatible.
