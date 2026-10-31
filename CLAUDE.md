# Store Tile Hider for PS5: project notes for coding agents and contributors

One PS5 homebrew payload, `build/StoreTileHider-<version>.elf`: every run toggles the "PlayStation Store" and "All Apps" tiles of the home screen (hides them if any is shown, shows them if all are hidden) and says what it did in a notification.
The file does its job and ends (no server, no network). This file is the long-term memory of the project: the decisions, the findings from a real console,
the traps. It is written for an AI coding agent that starts without any context (and for humans). Read it before you change anything.

**Read first:**
- `README.md`: what the payloads do, how to build, run and test.
- **`docs/payload-safety-notes.md`: the safety model (there is no sandbox; a payload runs with effective uid 0). Read it before you add any file, network, process or device access. The main goal is to minimize the risk of harm to the console.**
- `THIRD_PARTY_NOTICES.md`: licenses. The whole project is GPL-3.0-or-later.

The maintainer (Alexander) tests on a real console (firmware 11.20) and works in Russian; the code, comments, commits and docs are English. The layout of this repository, the build checks and the tests follow
[freefelt/transmission_ps5](https://github.com/freefelt/transmission_ps5) on purpose: keep them the same.

---

## 1. How to work here

1. **Discuss before you change.** For anything bigger than a small fix, say what you intend to do and wait for agreement. Answer a question first; if the answer implies a change, propose it instead of doing it.
2. **After a change: build and check imports** (`./build.sh`, a minute or two). The PS5 loader crashes on an import it does not know; `scripts/check-imports.sh` (run by `build.sh`) must print "no extra imports" for the file.
   Never use a libc or SDK function that has not been through the check (`fopen`/`fclose`/`fflush` were caught once; the log file uses `open`/`write`/`close`). The check is the authority; the allowed list holds the imports of builds that were run on a console.
3. **Tests are quick** (`tests/build/build-test-binaries.sh`, then `scripts/test.sh smoke` or `full`: about a minute). Run them after a change in `src/`.
4. **Never claim something works on the console unless it was tried there.** Say exactly what was verified on the host and what was not. **The file of this repository has not been run on a console yet** (the method, `visible=0`, was: see section 4); the first run on a console is the first thing to do before the first release.
5. **Test builds between releases** are made with `STH_DEBUG=N ./build.sh`: `last-run.log` then says "0.1 debug N" (the notification has no version: it is one short line), the name of the file stays `StoreTileHider-0.1.elf`. Never in a release.
6. **Raise the version** (`VERSION`, `0.N`: raise the second number, there is no third number) after a change that goes to a console; releases are made by a tag (`docs/releasing.md`).
7. **New functionality comes with tests.** A test must fail if the feature is broken; measure the real behaviour first, do not guess.
8. **Reports are short.** "All tests passed", or a short statement of what failed and why.
9. **Never break the data of a console:** the payloads change one column of two rows per user and nothing else; keep it that way. Any new write needs a backup, a transaction, a check and a test.
10. **Keep it small.** The project is deliberately minimal: two tiles, one column. Features of the tools it is compared with (moving tiles between tabs, pinning, restoring whole databases, a web page) are out of scope.

**The SDK and the firmware.** The startup code of the SDK (`crt`) knows the firmware versions one by one (v0.40 added 13.00/13.20, v0.41 13.40, v0.42 13.60, v0.45 also 14.00/14.10); a payload built with an SDK that does not know the firmware does not even reach `main()`.
So the SDK is **v0.45, the latest release**, pinned with a SHA-256 in `scripts/deps.sh`; the build compares the stamp `.deps/ps5-payload-sdk/.sth-sdk-version` with the pinned version and replaces an older SDK. Raise it only to a newer release, and update the SHA-256 from the release.

## 2. Layout and build

```
build.sh                  deps.sh -> build-elf.sh -> check-imports.sh
scripts/deps.sh           SDK v0.45 and SQLite 3.53.4 into .deps/ (versions and SHA-256 pinned, stamps for the installed ones)
scripts/build-elf.sh      SQLite for the PS5 (flags in the script), then the program; checks that the file carries the tile ids, the version and the SDK version
scripts/check-imports.sh  imports of the ELF against scripts/allowed-imports.txt
scripts/test.sh           the test runner: list | smoke | full | <area> | suite <file>
src/store_tiles.c         everything: backup, state, transaction, check, notification, log (sth_run)
src/main.c                calls sth_run()
tests/                    suites/{toggle,safety,real}, lib/harness.py, build/ (host build), check-env.sh, setup-env.sh
docs/, .github/workflows/ safety notes, releasing; Build, Tests, Release
```

The SDK is installed in `.deps/ps5-payload-sdk` (`source toolchain/prospero.sh` gives `CC`, `STRIP`, ...). Build on macOS needs Homebrew `llvm@18`; on Linux `clang-18 lld-18 llvm-18-dev`.
The host build of the tests is the same code with `-DSTH_HOST_TEST`: the paths move to `/tmp` (overridable with `STH_APP_DB`, `STH_BACKUP`, `STH_LOG`), the notification goes to stderr.

## 3. What a run does (`sth_run`, one toggle)

1. `backup_db`: `app.db.first.bak` (once, never overwritten), `app.db.<time>.bak` (the last 10 kept), through the SQLite backup API into `/data/StoreTileHider/backup`. No copy, no change.
2. Open `app.db` read-write, find the user tables `tbl_iconinfo_<uid>` (refuse if there are none or a table lacks `titleId`/`visible`).
3. `BEGIN IMMEDIATE` (busy timeout 5 s). **Inside the transaction** the state is read: `total` rows of the two tiles in all user tables, `shown` of them with `visible IS NOT 0` (NULL counts as shown). None found: rollback, exit 1. Any shown: the target is `visible=0` (hide); all hidden (`shown == 0`): `visible=1` (show). A mixed state hides all: the aim of the tool is hiding. The notification says which case it was.
4. `UPDATE ... SET visible=? WHERE titleId=?` for each of the two ids in each user table; a missing tile is reported and skipped.
5. `COMMIT`, `PRAGMA quick_check`, read back (no row of the two tiles has another value). Then a **one-line** notification ("tiles hidden / плитки скрыты" or "tiles shown / плитки показаны", or the reason nothing was changed) and the details in `/data/StoreTileHider/last-run.log`. Keep the notification this short: the maintainer asked for it (2026-10-31).

Nothing else is written. `journal_mode` is never touched; the SQLite of the PS5 build is compiled without WAL (the console's database is not in WAL mode).

## 4. Findings from a real console (firmware 11.20)

- The home screen database is `/system_data/priv/mms/app.db` (tables `tbl_contentinfo`, `tbl_conceptmetadata`, `tbl_version`, and per user `tbl_iconinfo_<uid>`, `tbl_concepticoninfo_<uid>`, `tbl_info_<uid>`, `tbl_group_<uid>`, `tbl_playlist_<uid>`, `tbl_addon_<uid>`) and `appinfo.db` (`tbl_appinfo`, `tbl_conceptinfo`). The system tiles are the titles `NPXS#####`.
- **`visible=0` in `tbl_iconinfo_<uid>` hides a system tile** and it stays hidden after reboots, sleep and (reported by the maintainer) rebuilds of the database after kernel panics. Verified on a console with an earlier web-based version of this tool. Codes: `NPXS40047` PlayStation Store (`pshome:gamestore`, Games tab), `NPXS40056` All Apps (`psmediahub:main?id=all_apps`, Media tab, the first tile from the left).
  Other system tiles seen with `visible=0` in the maintainer's database: Plus (`NPXS40037`), Welcome hub (`NPXS40063`), Remote Play (`NPXS40074`), Share Play (`NPXS40099`), Disc Player (`NPXS40140`), What's New / Music Home (`NPXS40053`/`40054`), disc error tiles. The Game Library (`NPXS40071`) and Media Gallery (`NPXS40075`) were visible.
- **"App Library" (`NPXS40139`, `pslibraryhub:main?space=media`) cannot be hidden by the database.** Tried on 2026-10-30 with three levels (the user rows only; plus the ems flags and `tbl_concepticoninfo`; plus `tbl_contentinfo`, `tbl_conceptmetadata`, `tbl_info_*` and `appinfo.db`, i.e. everything the TabShifter method writes): the writes were verified in copies of the databases, they persisted across reboots, the tile stayed. Probably the shell draws it itself. Its original values on this console were `dispLocation` 148 in every layer, 2196 in `tbl_concepticoninfo`, `visible` 0, NULL ems flags (TabShifter's 188 / 2236 are wrong for 11.20). This code was removed from the project on purpose; do not bring it back without new evidence.
- The two context-menu items of a game tile ("Check for updates", "Check the state of saved-data sync") were hidden earlier by the maintainer with fields of `appinfo.db` (an experiment of the web version, not part of this project).
- Facts about the database that cost time: the `ems*Flag` columns are NULL for system tiles (a tool that writes 0 instead of NULL does not restore exactly); `tbl_version` holds sync counters that the system bumps by itself; the database changes all the time while the console is used (last-access times, new tiles), so two copies made at different times differ even when nobody edited anything.
- [PS5-TabShifter](https://github.com/xvvulcanvx/PS5-TabShifter) (v1.3.0, 11 days old when studied) edits the same files in a much broader way: moves tiles between tabs, pins, installs its own "TS" tile, restores a single backup over the live file. Its issues (2026-10) show what to avoid: tiles that came back after sleep or after a rebuild (#16, #17, #22), a restore that wiped later-installed PS4 shortcuts (#13), a tile that could not be removed (#20), changed `HUBAPP_URI` that broke the Welcome widgets (#4, #10), padlocks on games after a rebuild (#8, #12). Do not run both tools; one tile, one tool.

## 5. Tests

`tests/suites/` by area (`scripts/test.sh list`): **toggle** (the first run hides and nothing else changes, the second shows and the database equals the original, five alternating runs, the state before the run decides: both hidden / one hidden / one user hidden / NULL, partial databases, one user, other tiles are never touched), **safety** (backups before the change, the first copy kept, pruning, no copy no change, rollback on an error, busy database, unexpected schemas, no stray files),
**real** (optional: a copy of a real `app.db` in `dbs/` or `STH_REAL_DIR`; two runs in a row, each checked to change exactly the two tiles' `visible` in every user table). The test databases are shaped like the real one (`tests/lib/harness.py: fresh`). A suite prints `PASS`/`FAIL` lines and `N/M checks passed`.
`dbs/` is git-ignored: it holds private data of a console.

## 6. Open questions

- Is the behaviour the same on other firmware (10.xx, 12.xx, 13.xx)? `tbl_iconinfo_*` is expected to be the same (TabShifter issues mention the same layout from 13.00 on), but nothing here was run there.
- Do the tiles return after a Rest Mode on other firmware? On 11.20 they did not. TabShifter users on 12-13 reported that Store came back after sleep or after some payloads (the cause is not known).
- Is a toggle the right control? One run, one file; the price is that you must read the notification to know where you ended up. A second file (or a marker) could be added if people want a one-way "hide".

## 7. Status and plans

- 0.1 is ready to tag after the first run of the file on a console (two runs: hide, then show) (see 1.4) and a green Tests workflow. No screenshots or icon yet (the README of `transmission_ps5` has them; a console notification is the only "UI" here).
- Ideas, only if asked: other tile ids (Plus, Remote Play, Share Play) as a separate file. A user added after the first run needs nothing: every run reads the list of user tables.

## 8. Decisions of the maintainer worth remembering

- The project is **only** the hiding of the two tiles and its undo, in **one file that toggles** (the maintainer dropped the two-file design on 2026-10-31): everything else that the first experiments had (a web page, a library tile, removal of TabShifter's tile) was dropped.
- Backups stay (first + last 10) even though they are a last resort: a failed write is rolled back by SQLite, the copies are for the human who wants to compare.
- Names: **Store Tile Hider** (`store_tile_hider_ps5`), the file `StoreTileHider-<version>.elf` (the version in the name, as `Transmission-<version>.elf` in `transmission_ps5`).
- Layout, licence (GPL-3.0-or-later, the same `LICENSE`), build checks (pinned SDK v0.45 with a stamp, SHA-256 of every download, the import check) and tests follow `transmission_ps5`.
