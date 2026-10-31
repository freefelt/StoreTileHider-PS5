# Changelog

All notable changes of the released versions. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the heading of
every version is `## [<version>]`, and the text under it becomes the notes of the GitHub release (see `docs/releasing.md`).

## [0.1] - 2026-10-31

The first public release.

### Features
- One file, `StoreTileHider-<version>.elf`: each run toggles the "PlayStation Store" tile (Games tab) and the "All Apps" tile (Media tab) by changing the `visible` flag in the home screen database. If any of the tiles is shown they are hidden; if all of them are hidden they are shown again.
- A notification on the console (English and Russian) says what was done and why, the same text is in `/data/StoreTileHider/last-run.log`.
- A copy of the database before every change (`/data/StoreTileHider/backup`: the first copy is never overwritten, the last 10 are kept); without a copy nothing is changed.
- One transaction: any error rolls everything back. Afterwards the database is checked and the result is read back.
- No server, no page, no network: the file does its job and ends.

### Notes
- Built with PS5 Payload SDK v0.45 (the latest release); the build checks the SDK version and the SHA-256 of every download.
- Developed on firmware 11.20, where the method (`visible=0`) was tried on a console: the tiles stay hidden after reboots and sleep. Other firmware versions are not verified.
