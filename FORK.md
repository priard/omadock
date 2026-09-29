# omadock — fork `priard`

Fork of https://github.com/thepathless/omadock (remote `upstream`); pushed
to https://github.com/priard/omadock (remote `fork`). No `origin`, so
`omarchy plugin update` leaves it alone.

Sync: `git fetch upstream && git merge upstream/main && git push fork priard`

## Workflow

- `main` on the fork mirrors `upstream/main`.
- Feature work goes on `feat/*` branches cut from `upstream/main`, so they
  can be sent upstream as PRs, then merged into `priard`.
- `priard` is what runs locally: upstream plus unmerged feature branches.

## Upstreamed

- #12 settings panel, background/shadow/border switches (merged 2026-09-29).
