# GIFT Brand Rename and Pixel Logo Design

## Goal

Rename the current desktop Git client product identity to `gift` throughout
the working tree and replace the existing mascot/logo artwork with a coherent
2D pixel-game identity. Git history, tags, and objects remain unchanged.

## Scope

- Rename the Dart package and every `package:` import to `gift`.
- Rename product-facing Dart symbols and source filenames that carry the old
  product name, including the app root widget.
- Rename product-facing asset files and update all asset references.
- Update README, architecture/research/task/planning/checkpoint/changelog
  references that describe the current product identity.
- Update Linux, macOS, Windows, CI, and build-helper product metadata and
  output paths to the `gift` identity.
- Keep generic Git terminology, repository paths, branch names, and unrelated
  third-party names unchanged.
- Do not rewrite `.git` history or alter existing commit objects.

## Identity rules

Use these forms consistently:

| Context | Value |
|---|---|
| Dart package / executable / app title | `gift` |
| Human-facing brand wordmark | `GIFT` |
| Dart app root symbol | `GiftApp` |
| Desktop reverse-DNS identifier | `app.kimmandoo.gift` |
| Temporary test prefixes and fixture identity | `gift` / `Gift Test` |

The migration must include both lowercase machine identifiers and title-case
symbols/text. A repository-wide legacy scan excluding `.git` must return no
obsolete product identity references after the change.

## Logo direction

Create one new square pixel-art mascot asset for the app icon and derive the
desktop platform icon variants from it. The mascot is a friendly orange shiba
holding or sitting behind a small gift box with a mint ribbon. Use a compact
palette already compatible with the app theme: deep navy outlines/background,
orange fur, warm cream muzzle, coral accent, and mint ribbon. Keep hard pixel
edges, no photographic shading, no gradients, and strong silhouette clarity at
small sizes.

The README logo should use the same visual language and present an exact
`GIFT` wordmark through the bundled pixel font or a deterministic code-native
layout. Generated artwork must not be relied on for spelling product text.
Accessibility labels and alt text must say `GIFT` or `GIFT pixel mascot`.

## Implementation and compatibility

- Preserve existing Flutter asset loading behavior and image-rendering
  settings.
- Keep icon dimensions and platform-specific asset manifests valid.
- Update generated or checked-in desktop icon outputs only from the new source
  asset; do not leave old product-named icon files referenced by packaging.
- Keep release workflow gating behavior unchanged.
- Preserve persisted user data compatibility where the product name is not
  part of the data contract. Theme and workspace keys must not be changed
  unless the existing key explicitly encodes the product identity.

## Verification

Run the repository's normal verification suite after implementation:

1. `dart format --output=none --set-exit-if-changed lib test integration_test tool`
2. `flutter analyze`
3. `flutter test`
4. `PATH=/home/mgkim/.local/flutter/bin:$PATH dart run tool/verify.dart` when
   the pinned Flutter SDK is available
5. `git diff --check`
6. A repository-wide case-insensitive legacy identity scan excluding `.git`,
   generated build folders, and dependency caches.

The final commit must update `CHANGELOG.md` in past tense under the current
date and update `docs/WORK_CHECKPOINT.md` with exact changes, verification
results, and any platform build blocker.
