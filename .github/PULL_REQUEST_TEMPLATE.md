<!-- PRs must target `experimental`: `main` only receives verified release batches. -->

## What and why

## Verification

- [ ] `node --check DockModel.js` and `node --test tests/unit/*.test.mjs tests/unit/*.test.js`
- [ ] `python3 -m unittest discover -s tests/unit`
- [ ] `qmllint -I /usr/share/omarchy/shell Dock.qml DockHost.qml components/*.qml components/settings/*.qml` (no new error kinds)
- [ ] `python3 tests/static/security-grep.py` and `bash tests/static/shaders-in-sync.sh`
- [ ] `./tests/manifest-check.sh .` and `omarchy plugin validate .`
- [ ] `./tests/smoke-test.sh` against a running dock
