<!-- PRs must target `experimental`: `main` only receives verified release batches. -->

## What and why

## Verification

- [ ] `node --check` each of `DockModel.js`, `DockLabels.js`, `DockLayout.js`, `DockMarks.js`, `DockMarkGeometry.js`, and `node --test tests/unit/*.test.mjs tests/unit/*.test.js`
- [ ] `python3 -m unittest discover -s tests/unit -p 'test_*.py'`
- [ ] `qmllint -I /usr/share/omarchy/shell Dock.qml DockHost.qml components/*.qml components/settings/*.qml components/logic/*.qml` (no new error kinds)
- [ ] `python3 tests/static/security-grep.py`, `python3 tests/static/structure-check.py` and `bash tests/static/shaders-in-sync.sh`
- [ ] `./tests/manifest-check.sh .` and `omarchy plugin validate .`
- [ ] `./tests/smoke-test.sh` against a running dock
