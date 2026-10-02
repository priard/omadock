# Security hardening — design

Date: 2026-10-02. Status: approved in conversation, awaiting spec review.
Part 4 of 4. Fixes go upstream in `feat/hardening` (with the test-driven
bug fixes from part 3); the window-preview option goes into the open PR #22
(`feat/window-previews`).

## Audit summary

Audit of `priard` at 4097374 following the `omarchy-plugin-security`
checklist. No high-severity issue. Upstream's remediations hold: every
`Text` is PlainText, config reads go through the `CappedFileView` gate,
persisted collections are bounded, `hyprctl eval` strings contain only
constants, clamped numbers and escaped workspace names, app launches pass
ids as argv with `--`. Fork features add no new execution surface beyond a
constant `hyprctl eval`.

## Fixes

| # | issue | who controls the input | fix | regression test |
|---|---|---|---|---|
| 1 | USB drive label reaches `notify-send` unescaped (`Dock.qml:1327`); notification bodies render markup | whoever formatted the drive | in `scripts/eject-drive.py`: strip `<>&`, C0/C1 and bidi controls, cap at 64 chars; same cap/cleanup in `scripts/list-drives.py` | unit: label `<img src=x>&`, 10 KB label |
| 2 | stack thumbnails fall back to the original file, so SVG/GIF/huge images from `~/Downloads` are parsed inside the shell (`scripts/list-folder.py:157`, `FileTile.qml:59`) | any web page that triggers a download | fall back to the original only for png/jpg/webp ≤ 20 MB; never SVG or GIF (cached freedesktop thumbnails still used) | unit: `x.svg` and a 50 MB `.png` give an empty `thumb` |
| 3 | `list-folder.py` has no work budget | whoever fills a pinned folder | stop scanning after 20 000 entries and report the count as "≥ N"; run under `timeout` | unit: 100k files finish within the budget with valid JSON |
| 4 | array-like `length` freezes the shell (see part 3) | config file contents | `Array.isArray` in every bounding function | unit |
| 5 | `systemBlurSize` has no upper clamp (`Dock.qml:2185` → Hyprland `decoration.blur.size`) | config file contents | clamp to 1–100 | unit on the extracted `applyLook` |
| 6 | `urgentSoundName` unvalidated (`Dock.qml:2194`, used 2045/2635) | config file contents | accept `^[a-z0-9-]{1,48}$` or `none`, else the default | unit |
| 7 | drop paths are emitted one per line (`Dock.qml:2363, 2405`); a name with `\n` splits into two paths | whoever names a directory | reject paths containing `\n` or `\r` in `localPathsFromUrls` | unit |
| 8 | pinned folder path not required to be absolute; `-x` reaches `xdg-open` as an option (`FolderPopup.qml:69`) | config file contents | `boundPinnedFolders` keeps only absolute paths (`/` or `~/`) | unit |
| 9 | `TextField`s without `maximumLength`/`textFormat` (`SettingsPanel.qml:1382, 1692`) | – | add them so the audit grep is clean | static grep |

## Window previews option (PR #22)

New config key `windowPreviews` (default `true`) with a toggle on the
tooltip settings page, independent from `advancedTooltips`. When off, the
tooltip shows the existing window list without captures. README documents
that previews capture window contents into GPU memory only while the
tooltip is open and never write them to disk.

## Static security audit (`tests/static/security-grep.sh`)

Fails the offline tier when:

- a `Text`/`Label` lacks `textFormat: Text.PlainText`;
- `bash -c`/`sh -c` command strings are built by concatenation instead of
  passing data as positional arguments;
- `hyprctl eval` receives a string not built from the known safe helpers;
- `notify-send` is called with arguments not passed through a sanitiser;
- `RichText`, `StyledText`, `MarkdownText`, `eval(` or `new RegExp(` on
  input appear.

Known safe exceptions are listed in the script with a one-line reason each.

## Accepted, documented, not changed

- `applyPreset`, `setAlignment`, `setPosition` IPC write the config; any
  process running as the user can already write the file directly.
- Tools are found through `PATH`; committed `.qsb` binaries are checked by
  the shader-sync test (part 3), which proves they match the sources.
- The `CappedFileView` stat-then-read race is bounded by the checked size
  and a 2 s timeout.
