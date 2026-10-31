# Third-party notices

Store Tile Hider for PS5 is licensed under the **GPL-3.0-or-later** (see [`LICENSE`](LICENSE)). It is built from, and linked with, the
components below, each of which keeps its own license. The authoritative texts are in the sources of the components (the build
downloads them into `.deps/`); this file is a summary and not legal advice.

## Linked into `StoreTileHider-<version>.elf`

| Component | Version | License |
|---|---|---|
| [SQLite](https://www.sqlite.org) (the amalgamation `sqlite3.c`) | 3.53.4 | public domain |
| PS5 payload SDK ([ps5-payload-dev/sdk](https://github.com/ps5-payload-dev/sdk), John Törnblom) | v0.45 | GPL-3.0-or-later for its scripts, headers and start files (as stated in their headers); it also carries LLVM's libc++ (Apache-2.0 with LLVM exception) and FreeBSD-derived headers (BSD) |

The SQLite files are taken from the npm package [better-sqlite3](https://github.com/WiseLibs/better-sqlite3) 13.0.3 (MIT): only `sqlite3.c` and `sqlite3.h`
are used, their SHA-256 sums are pinned in `scripts/deps.sh`. SQLite is built with the options listed in `scripts/build-elf.sh`.

## Acknowledgements

Projects whose sources and issues helped the development:
[PS5-TabShifter](https://github.com/xvvulcanvx/PS5-TabShifter) (which tables of the home screen database matter), and
[transmission_ps5](https://github.com/freefelt/transmission_ps5) (the layout of the repository, the build checks and the tests follow it).
