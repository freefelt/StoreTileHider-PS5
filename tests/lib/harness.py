"""Helpers of the suites: the test databases, running the program on the host, checks and the summary.
The program is built for this machine by tests/build/build-test-binaries.sh (.deps/test/out/StoreTileHider_host); it works on files in /tmp, never on a console."""
import hashlib, os, shutil, sqlite3, subprocess, sys, time
HOST_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HOST_DIR))
OUT = os.path.join(REPO, ".deps", "test", "out")
APP, BACKUP, LOG = "/tmp/sth_app.db", "/tmp/sth_backup", "/tmp/sth_last-run.log"
ENV = dict(os.environ, STH_APP_DB=APP, STH_BACKUP=BACKUP, STH_LOG=LOG)
STORE, ALL_APPS, LIBRARY, PLUS, GAME = "NPXS40047", "NPXS40056", "NPXS40139", "NPXS40037", "PPSA00001"
TILES = (STORE, ALL_APPS)
USERS = ("1000", "2000")
res = []
def check(name, ok, extra=""):
    res.append(bool(ok)); print(("PASS " if ok else "FAIL ") + name + (("  -> " + str(extra)) if extra != "" else ""), flush=True)
def summary():
    print(f"\n{sum(res)}/{len(res)} checks passed"); return 0 if all(res) else 1
def run(env=None):                # one toggle; returns (exit code, stderr)
    r = subprocess.run([f"{OUT}/StoreTileHider_host"], env=env or ENV, capture_output=True, text=True)
    return r.returncode, r.stderr
def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()
def q(sql, *a, path=APP):
    c = sqlite3.connect(path); r = c.execute(sql, a).fetchall(); c.close(); return r
def set_vis(value, tiles=TILES, users=USERS):    # the state of the tiles before a run
    c = sqlite3.connect(APP)
    for u in users:
        for t in tiles: c.execute(f"update tbl_iconinfo_{u} set visible=? where titleId=?", (value, t))
    c.commit(); c.close()
def vis(tile, user="1000"):
    return q(f"select visible from tbl_iconinfo_{user} where titleId=?", tile)[0][0]
def dump(path=APP):               # every table with every row: two dumps are equal when the databases hold the same data
    c = sqlite3.connect(f"file:{path}?mode=ro", uri=True); out = []
    for t, in c.execute("select name from sqlite_master where type='table' order by name"):
        out.append((t, sorted(map(repr, c.execute(f"select * from {t}").fetchall()))))
    c.close(); return out
def fresh():
    """A database shaped like the one of a console (firmware 11.20): two users, system tiles with their real codes, a game, other tables."""
    for p in (APP, APP + "-journal", LOG):
        if os.path.exists(p): os.remove(p)
    shutil.rmtree(BACKUP, ignore_errors=True)
    c = sqlite3.connect(APP)
    c.execute("create table tbl_contentinfo (titleId TEXT, titleName TEXT, dispLocation INT, localConceptId TEXT)")
    c.execute("create table tbl_version (key TEXT, value INT)")
    c.executemany("insert into tbl_version values (?,?)", [("access_index", 1233), ("appinfo_sync_index", 797)])
    tiles = [(STORE, "PlayStation Store", 146), (ALL_APPS, "All Apps", 148), (LIBRARY, "App Library", 148), (PLUS, "PlayStation Plus", 147), (GAME, "Some Game", 138)]
    c.executemany("insert into tbl_contentinfo values (?,?,?,?)", [(i, n, d, "cid:local:" + i) for i, n, d in tiles])
    for u in USERS:
        c.execute(f"create table tbl_iconinfo_{u} (titleId TEXT NOT NULL, titleName TEXT, localConceptId TEXT, dispLocation INT, visible INT, pinnedStatus INT, emsPushedFlag INT, emsDeletedFlag INT)")
        c.execute(f"create table tbl_info_{u} (key TEXT PRIMARY KEY, value TEXT)")
        c.executemany(f"insert into tbl_iconinfo_{u} values (?,?,?,?,?,?,?,?)", [(i, n, "cid:local:" + i, d, 1, 2, None, None) for i, n, d in tiles])
        c.execute(f"insert into tbl_info_{u} values ('init_myhome_flag', '1')")
    c.commit(); c.close()
