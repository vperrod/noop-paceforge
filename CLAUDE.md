# CLAUDE.md

Shared repository guidance lives in [AGENTS.md](AGENTS.md).

@AGENTS.md

## Public repo: no personal data

`vperrod/noop-paceforge` is PUBLIC. Never commit real PaceForge data (recovery, HRV, RHR, training, daily brief, race or body data) or bundle a snapshot of it in the app; the app reads live data from the server. The only bundled JSON allowed is the synthetic UI-test fixture `NOOPiOSUITests/PaceForgeFixture.json` and the unit-test `StrandTests/LiveShapes/PaceForgeRealShapes.json` (the live documents' shapes with every value replaced; both must carry the word `Synthetic`). Enable the guard once per clone with `git config core.hooksPath .githooks` (runs `scripts/guard-no-personal-data.sh` on every commit).
