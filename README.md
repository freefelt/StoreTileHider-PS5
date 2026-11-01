<div align="center">

<h1>Store Tile Hider for PS5</h1>

**English** · [Русский](README.ru.md)

**An unofficial, open-source payload for the PS5 homebrew scene.**
Hide the "PlayStation Store" and "All Apps" tiles from the home screen with one file, bring them back with another.

[![Release](https://img.shields.io/github/v/release/freefelt/store_tile_hider_ps5?label=release)](https://github.com/freefelt/store_tile_hider_ps5/releases/latest)
[![Build](https://img.shields.io/github/actions/workflow/status/freefelt/store_tile_hider_ps5/build.yml?label=build)](https://github.com/freefelt/store_tile_hider_ps5/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-green)](LICENSE)
[![PS5 firmware](https://img.shields.io/badge/PS5%20firmware-11.20%20tested-brightgreen)](#-good-to-know)
[![PS5 payload SDK](https://img.shields.io/badge/PS5%20payload%20SDK-v0.45-blue)](https://github.com/ps5-payload-dev/sdk)
[![Downloads](https://img.shields.io/github/downloads/freefelt/store_tile_hider_ps5/total)](https://github.com/freefelt/store_tile_hider_ps5/releases)
[![Stars](https://img.shields.io/github/stars/freefelt/store_tile_hider_ps5?style=flat)](https://github.com/freefelt/store_tile_hider_ps5/stargazers)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](#-contributing)

</div>

> [!IMPORTANT]
> This project is under development, so expect rough edges. It is developed on firmware **11.20**, where the method was tried on a console; other firmware versions are not verified yet. Your console must **already** be able to run payloads (an ELF loader that listens on port 9021). This
> project does not jailbreak anything and does not help with it.

> [!NOTE]
> **Unofficial.** This project is not made, endorsed or supported by Sony. "PlayStation" and "PS5" belong to Sony. They are used here only to say what this is for.

## ✨ What you get

- **One file, `StoreTileHider-<version>.elf`.** Send it to the console and it **hides** two tiles: **PlayStation Store** (the first tile on the Games tab) and **All Apps** (the first tile on the Media tab). Send it again and it **shows** them, if they are hidden. Every run is one toggle.
- **A short notification.** Just "tiles hidden" or "tiles shown" (in English and Russian). The details (why, the check, both tiles) are in `/data/StoreTileHider/last-run.log`.
- **One thing is changed in the system database:** the `visible` flag of these two tiles. Nothing else is touched. The method was tried on a console: the tiles stay hidden after reboots and sleep.
- **A copy before every change.** The console's tile database is copied to `/data/StoreTileHider/backup` first; if the copy fails, nothing is changed. The very first copy is never overwritten.
- **All or nothing.** The change is one database transaction: on any error everything is rolled back. Afterwards the database is checked and the result is read back.
- **No server, no page, no network.** The file does its job and ends. Nothing keeps running.

## 📥 Install

**What you need:** a PS5 that can already run payloads, and a computer or a payload sender that can reach the console in your **home network**.

### Step 1. Download the file

👉 **[Open the latest release](https://github.com/freefelt/store_tile_hider_ps5/releases/latest)**

On that page scroll down to **Assets** and click the file **`StoreTileHider-<version>.elf`**: it downloads to your computer.
The version is always in the name of the file, so you can see which one you have. Older versions are on the [page with all releases](https://github.com/freefelt/store_tile_hider_ps5/releases).

### Step 2. Find the address of your PS5

On the PS5 open **Settings → Network → Connection Status → View Connection Status**. Write down the **IP address**, for example `192.168.1.42`.

### Step 3. Send the file to the console

Send the file to the **ELF loader** of your console, port **9021**. Use the payload sender you already use, or this command on macOS and
Linux (put your IP address in it):

```sh
nc -q0 192.168.1.42 9021 < StoreTileHider-<version>.elf
```

### Step 4. Read the message

After a second or two the console shows a short notification: **`tiles hidden / плитки скрыты`** or **`tiles shown / плитки показаны`**.
The details are in `/data/StoreTileHider/last-run.log`, for example:

```
Store Tile Hider 0.1 (SDK v0.45)
tiles: NPXS40047, NPXS40056
The tiles were shown, so they are hidden. / Плитки были видны, поэтому скрываю их.
NPXS40047 PlayStation Store: visible=0 (rows: 1)
NPXS40056 All Apps: visible=0 (rows: 1)
database check: ok; read back: matches
```

### Step 5. Look at the home screen

If a tile is still on the screen, enter a game and come back to the home screen, or reboot the console. 🎉

### Show the tiles again (or hide them again)

Send the same file once more (Step 3). Each run is one toggle: if the tiles are hidden, it shows them (the notification says "tiles shown"); if any of them is shown, it hides them.

> [!TIP]
> Always read the notification: it says whether the run hid or showed the tiles. Sending the file does not need a reboot of the console, and you can send it as many times as you like.

### Remove

Send the file once more if the tiles are hidden and you want them back, then delete the file. All the data of the payload is in `/data/StoreTileHider/`; delete that folder if you want to remove everything.

## 💡 Good to know

- **Tested on firmware 11.20.** If you try another one, please tell us how it went (open an issue and attach `/data/StoreTileHider/last-run.log`).
- **The tiles come from the console's database.** If the system rebuilds its database (for example after a crash), the tiles can come back: send the file again: it hides them if they are shown (read the notification, it says what was done).
- **Only these two tiles.** The "App Library" tile of the Media tab stays on the screen even when all its rows in the database are changed (probably the system draws it itself), so this method cannot hide it.
- **Not together with TabShifter.** [PS5-TabShifter](https://github.com/xvvulcanvx/PS5-TabShifter) edits the same database in a different way; if you use it, hide and show a tile with the same tool, and do not use its "Restore DB Backup" after this one.
- **A restored copy loses what was installed later.** The copies in `/data/StoreTileHider/backup` are a last resort: putting a whole old database back removes everything installed after it was made. To undo this payload just send the file again.
- **No password and no network access.** The payloads do not listen on any port and do not connect anywhere.

## 🛟 Something does not work?

| Problem | What to do |
|---|---|
| No notification appears | Check that the console really runs the ELF loader (port 9021), that the IP address is right and that your computer is in the same network. Send the file again. |
| "nothing was changed (no backup)" | `/data` is full or not writable. Free some space and send the file again; nothing was changed. |
| "nothing was changed (database busy)" | The system was writing to its database. Wait a few seconds and send the file again. |
| "nothing was changed (unexpected database)" | The database of this firmware is shaped differently. Nothing was changed; please open an issue with `last-run.log`. |
| The tiles are still shown | Enter a game and come back, or reboot the console. If they are still there, check that `last-run.log` says "read back: matches" and which way the run went (a run on hidden tiles shows them). |
| The tiles came back by themselves | The system rebuilt its database. Send the file again: it hides them (the notification says "tiles hidden"). |

Still stuck? Open an [issue](https://github.com/freefelt/store_tile_hider_ps5/issues) and attach the file `/data/StoreTileHider/last-run.log`.

## 🛠 Build it yourself

```sh
./build.sh
```

That is all: the script downloads what it needs into `.deps/` (the PS5 SDK and SQLite), builds the file, checks its imports and writes
**`build/StoreTileHider-<version>.elf`** (about 1 MB). Every download is pinned to an exact version and verified with a
SHA-256; nothing newer is ever picked up silently. The SDK is **v0.45**, the latest release: the build checks the version of the SDK that is installed in `.deps/`
(a folder left by an older build is replaced). The first build takes a minute or two.

| System | Needs |
|---|---|
| **macOS** (not verified) | [Homebrew](https://brew.sh) (the script installs `llvm@18` with it; `./build.sh --no-brew` skips that), `curl`, `tar`, `make`, `unzip` (all part of the system) |
| **Linux** (Ubuntu 24.04 is what it is checked on) | `clang-18 lld-18 llvm-18-dev make curl unzip` |
| **Windows** | use [WSL2](https://learn.microsoft.com/windows/wsl/install) with Ubuntu and follow the Linux line; building natively is not supported |

Verified on Ubuntu 24.04 (x86_64). On macOS it should work too (the scripts are written for it), but it has not been verified and is not checked automatically.
The tools that are not pinned are only the ones on your machine (clang 18): their minor versions can differ from the ones used by the author.

The PS5 loader crashes on an import it does not know, so the build ends with `scripts/check-imports.sh`: it compares the imports of the file with
`scripts/allowed-imports.txt` (the imports of the builds that were run on a console) and fails on a new one.

## 🧪 Tests

The tests run the same code on your machine (the paths are moved to `/tmp`, nothing touches a console or needs root) on test databases shaped like the one of a console.

```sh
sudo tests/setup-env.sh                       # once, Ubuntu only: clang, SQLite headers, Python (on macOS there is nothing to install)
tests/check-env.sh                            # checks the machine
tests/build/build-test-binaries.sh            # the program built for this machine (repeat after changes in src/)
scripts/test.sh smoke                         # a quick check; `full` runs everything (about a minute); `scripts/test.sh list` shows the areas
```

The suite `real` runs on a copy of the database of a real console if you put one in `dbs/` (it is private and never committed).

## 🗂 Repository layout

| Folder | What it is |
|---|---|
| `src/` | the sources: `main.c` and `store_tiles.c` / `store_tiles.h` (everything: backup, transaction, check, notification) |
| `scripts/` | the build steps called by `build.sh`, the import check (`allowed-imports.txt`), `test.sh`, `release-notes.sh` |
| `tests/` | the tests: `suites/` (by area), `lib/` (helpers), `build/` (the test build), `check-env.sh`, `setup-env.sh` |
| `docs/` | documentation: the safety notes and how a release is made |
| `.github/workflows/` | the checks that run on GitHub: build, tests, release |
| `VERSION` | the version of the payload (it becomes the name of the file and is written in `last-run.log`) |

How the pieces fit together: `build.sh` runs `scripts/deps.sh` (SDK and SQLite, both pinned and checked), then `scripts/build-elf.sh` (builds SQLite for the PS5 and links
the program) and `scripts/check-imports.sh`.

## 🤝 Contributing

Issues and pull requests are welcome. Please keep a change small and focused, and say on which firmware you tried it:
the tests run on a host, not on a console, and a change that was not tried on a console should say so.

- **Read [`CLAUDE.md`](CLAUDE.md).** It is the long-term memory of the project: the layout, the rules (for example, the PS5 loader
  crashes on an unknown import, so `./build.sh` runs an import check), the findings from a real console, what was tried and did not work (the "App Library" tile), and the open questions. It is written for coding agents as much as for
  people. Also read [`docs/payload-safety-notes.md`](docs/payload-safety-notes.md) before you touch files, the network, processes or devices:
  a payload has no sandbox, and the main aim of this project is to minimize the risk of harm to the console.
- Comments, commit messages and documentation are in English.
- Run the checks that match your change (see [Tests](#-tests)).

**Working with a coding agent.** If you use an AI agent (Claude Code or another one that reads `CLAUDE.md`), start it in the root of the
repository with a prompt like this:

> Read `CLAUDE.md` and `docs/payload-safety-notes.md` completely, then `README.md`. Do not change anything yet.
> Tell me in a few sentences how the project is built and tested and what the rules of this repository are. After that I will describe the
> change I want. Discuss the plan with me before editing, keep the change small, build with `./build.sh` (it must report no extra
> imports), and tell me exactly what you verified and what you could not (you cannot try anything on a console). Do not add new
> dependencies, file or network access, or system calls without asking.

## 📜 License and credits

The project is licensed under the **GPL-3.0-or-later**. The PS5 payload SDK
([ps5-payload-dev/sdk](https://github.com/ps5-payload-dev/sdk)), SQLite and the other
components keep their own licenses; they are listed in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
Thanks to [xvvulcanvx/PS5-TabShifter](https://github.com/xvvulcanvx/PS5-TabShifter) whose source and issues helped to understand which tables of the home screen database matter, and to
[freefelt/Transmission-PS5](https://github.com/freefelt/Transmission-PS5), the layout of whose repository this one follows.
