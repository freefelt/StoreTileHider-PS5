# Safety of PS5 payloads: notes for this project

Context: Store Tile Hider (one file, `StoreTileHider-<version>.elf`) writes to a system database of the console, so it is held to the safety rules of PS5 payloads (see
[`transmission_ps5/docs/payload-safety-notes.md`](https://github.com/freefelt/transmission_ps5/blob/main/docs/payload-safety-notes.md) for the
long discussion and the results of the rights test on firmware 11.20: there is no real sandbox, a payload runs with effective uid 0 and can write kernel memory).

Notation: **[verified]** from the code, the tests or a console, **[conclusion]** reasoning on verified facts, **[not verified]** a guess.

## 1. What the payloads touch

**[verified, in the code]**

- Reads and writes **one** system file: `/system_data/priv/mms/app.db` (the home screen database), through SQLite. Nothing else in `/system*`, `/preinst`, `/dev`.
- Writes its own files only in `/data/StoreTileHider/` (`backup/`, `last-run.log`).
- Reads the state of the two tiles and flips it (hides them if any is shown, shows them if all are hidden); sends one notification to the console (`sceKernelSendNotificationRequest`).
- **No network** (no sockets, no ports), **no `fork`/`exec`**, no kernel functions, no change of rights.
- The only change in the database: `UPDATE tbl_iconinfo_<user> SET visible=? WHERE titleId=?` (the value is decided inside the transaction from the current state) for two fixed ids (`NPXS40047`, `NPXS40056`), in one transaction.
- `journal_mode` and every other setting of the database are left as the system made them.

## 2. What protects the console

**[verified in the tests on a host; the method itself, `visible=0`, was verified on a console (firmware 11.20) in an earlier web-based version of this tool; the file of this repository has not been run on a console yet]**

- A copy of the database (the SQLite backup API, a consistent snapshot) before every change; if it fails, nothing is changed. The first copy is never overwritten.
- One `BEGIN IMMEDIATE` transaction; any error rolls back. If the system holds the database, the program waits at most 5 s and gives up without a change.
- `PRAGMA quick_check` and a read-back of the result after the change.
- The ids of the tiles are constants in the code: nothing comes from outside (there is no input at all).
- `scripts/check-imports.sh` compares the imports of the built files with `scripts/allowed-imports.txt` (the imports of builds that were run on a console): the PS5 loader crashes on an unknown import.
- The versions and SHA-256 sums of the SDK and of SQLite are pinned; the build checks the SDK version that is installed.

## 3. What can still go wrong

- **[conclusion]** A write to a system database while the system runs can in theory race with the system. SQLite locks make this safe at the file level (the system and the payload serialize); a transaction is a few milliseconds.
- **[conclusion]** Putting a whole old copy of `app.db` back (not something the payload does) removes whatever was installed after the copy was made; users of other tools reported lost shortcuts of PS4 packages that way. Undo by running the file again.
- **[conclusion]** If the system rebuilds its database (safe mode, "Rebuild database", a crash), the hidden tiles can come back; run the file again (it hides them if they are shown). Users of other tools reported "locked" game icons and lost play time after a rebuild; this payload does not cause a rebuild.
- **[not verified]** Behaviour on firmware other than 11.20: the schema of `tbl_iconinfo_*` may differ; the program refuses to run if the columns `titleId` and `visible` are missing.
- The notification text and `last-run.log` are not secret: they hold tile ids and names only.
