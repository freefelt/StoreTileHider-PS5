import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))
from harness import *
import glob
# Optional: runs on a copy of the database of a real console (private, never committed). Put app.db (or any copy such as app.db.first.bak) into dbs/
# or into the folder named in STH_REAL_DIR.
d = os.environ.get("STH_REAL_DIR") or os.path.join(REPO, "dbs")
cands = [p for n in ("app.db", "app.db.first.bak", "before_app.db") for p in glob.glob(os.path.join(d, n))]
if not cands:
    print(f"SKIP: no copy of a real app.db in {d} (copy /system_data/priv/mms/app.db there to run this suite)"); print("\n0/0 checks passed"); sys.exit(0)
src = cands[0]; print(f"== a real database: {src}")
EXP = "/tmp/sth_expected.db"
def expected(visible):            # the original with exactly the change the program promises: visible of the two tiles, in every user table
    shutil.copy(src, EXP); c = sqlite3.connect(EXP)
    for t, in c.execute("select name from sqlite_master where type='table' and name like 'tbl_iconinfo_%'").fetchall():
        c.execute(f"update {t} set visible=? where titleId in (?, ?)", (visible, *TILES))
    c.commit(); c.close(); return dump(EXP)
import sqlite3
shutil.rmtree(BACKUP, ignore_errors=True)
for p in (APP, LOG):
    if os.path.exists(p): os.remove(p)
shutil.copy(src, APP)
tbls = [t for t, in q("select name from sqlite_master where type='table' and name like 'tbl_iconinfo_%'")]
check("the copy has user tables tbl_iconinfo_*", tbls, tbls)
shown_rows = sum(q(f"select count(*) from {t} where titleId in (?, ?) and visible is not 0", *TILES)[0][0] for t in tbls)
first = 0 if shown_rows else 1     # any tile shown: the run hides; all hidden: the run shows
rc, err = run()
check(f"first run: exit code 0, the tiles are {'hidden' if first == 0 else 'shown'}; only visible of the two tiles changed, nothing else", rc == 0 and dump() == expected(first), err[-300:])
rc, err = run()
check("second run: the opposite, exit code 0, again only visible of the two tiles changed", rc == 0 and dump() == expected(1 - first), err[-300:])
check("the integrity check of the database is ok", q("pragma quick_check") == [("ok",)])
sys.exit(summary())
