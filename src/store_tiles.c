/* Store Tile Hider: hide the "PlayStation Store" and "All Apps" tiles of the PS5 home screen, or show them again if they are hidden.
 *
 * The tiles live in /system_data/priv/mms/app.db, one table tbl_iconinfo_<user> per user; the column `visible` is 1 for a shown tile and 0 for
 * a hidden one. Changing only this column was tried on a console (firmware 11.20): the tiles disappear and stay hidden after reboots and sleep.
 *
 * One run is one toggle: if any of the tiles is shown, they are hidden; if all of them are hidden, they are shown again. The notification says which.
 *
 * Order of work: 1) a copy of the database (the SQLite backup API) in /data/StoreTileHider/backup, without it nothing is changed;
 * 2) one transaction (BEGIN IMMEDIATE, waits up to 5 s for the system), any error rolls everything back; 3) COMMIT, PRAGMA quick_check and
 * a read-back of the result; 4) a one-line notification on the console ("tiles hidden" or "tiles shown") and the details in the file /data/StoreTileHider/last-run.log.
 * journal_mode and other settings of the system database are never touched.
 *
 * License: GPL-3.0-or-later. */

#include <dirent.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "sqlite3.h"
#include "store_tiles.h"

#ifndef STH_VERSION
#define STH_VERSION "dev"
#endif
#ifndef STH_SDK_VERSION
#define STH_SDK_VERSION "unknown"
#endif

#ifdef STH_HOST_TEST
static const char *APP_DB = "/tmp/sth_app.db";
static const char *BACKUP_DIR = "/tmp/sth_backup";
static const char *LOG_FILE = "/tmp/sth_last-run.log";
#else
extern int sceKernelSendNotificationRequest(int device, void *request, size_t size, int blocking);
static const char *APP_DB = "/system_data/priv/mms/app.db";
static const char *BACKUP_DIR = "/data/StoreTileHider/backup";
static const char *LOG_FILE = "/data/StoreTileHider/last-run.log";
#endif

#define MAX_USERS 16
#define UID_LEN 48
#define KEEP_BACKUPS 10 /* time-stamped copies to keep; app.db.first.bak is never deleted */

typedef struct {
    const char *id;
    const char *name; /* used when the database has no name for the tile */
} tile_t;

static const tile_t TILES[] = {
    { "NPXS40047", "PlayStation Store" }, /* Games tab, the first tile from the left */
    { "NPXS40056", "All Apps" },          /* Media tab, the first tile from the left */
};
#define NTILES ((int)(sizeof(TILES) / sizeof(TILES[0])))

static void host_paths(void)
{
#ifdef STH_HOST_TEST
    if (getenv("STH_APP_DB")) APP_DB = getenv("STH_APP_DB");
    if (getenv("STH_BACKUP")) BACKUP_DIR = getenv("STH_BACKUP");
    if (getenv("STH_LOG")) LOG_FILE = getenv("STH_LOG");
#endif
}

/* ---------- messages, log and notification ---------- */

static int g_log = -1; /* the log file: open/write/close only, the other stdio calls are not on the list of imports verified on a console */

static void ensure_dir(const char *path)
{
    char tmp[200];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *q = tmp + 1; *q; q++) {
        if (*q == '/') {
            *q = 0;
            mkdir(tmp, 0755);
            *q = '/';
        }
    }
    mkdir(tmp, 0755);
}

static void say(const char *fmt, ...)
{
    char line[300];
    va_list ap;
    va_start(ap, fmt);
    int len = vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    if (len >= (int)sizeof(line)) { /* cut at a UTF-8 character boundary */
        len = (int)sizeof(line) - 1;
        while (len > 0 && ((unsigned char)line[len] & 0xC0) == 0x80)
            len--;
        line[len] = 0;
    }
    fprintf(stderr, "%s\n", line);
    if (g_log < 0) {
        char dir[200], head[160];
        snprintf(dir, sizeof(dir), "%s", LOG_FILE);
        char *sl = strrchr(dir, '/');
        if (sl && sl != dir) {
            *sl = 0;
            ensure_dir(dir);
        }
        g_log = open(LOG_FILE, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (g_log >= 0) {
            int hl = snprintf(head, sizeof(head), "Store Tile Hider %s (SDK %s)\n", STH_VERSION, STH_SDK_VERSION);
            if (write(g_log, head, (size_t)hl) < 0)
                g_log = -1;
        }
    }
    if (g_log >= 0) {
        char out[320];
        int ol = snprintf(out, sizeof(out), "%s\n", line);
        if (write(g_log, out, (size_t)ol) < 0) {
            close(g_log);
            g_log = -1;
        }
    }
}

static void notify(const char *text)
{
#ifdef STH_HOST_TEST
    fprintf(stderr, "NOTIFY: %s\n", text);
#else
    unsigned char request[3120];
    memset(request, 0, sizeof(request));
    snprintf((char *)request + 45, sizeof(request) - 45, "%s", text);
    sceKernelSendNotificationRequest(0, request, sizeof(request), 0);
#endif
}

/* The notification is one short line, in English and Russian: "tiles hidden" or "tiles shown" (or why nothing was changed). Everything else is in the log. */
static void finish(const char *en, const char *ru)
{
    char text[200];
    snprintf(text, sizeof(text), "Store Tile Hider: %s / %s", en, ru);
    notify(text);
    if (g_log >= 0) {
        close(g_log);
        g_log = -1;
    }
}

/* ---------- copies of the database ---------- */

/* A copy through the backup API of SQLite (a consistent snapshot, even while the system writes to the database). 0, or -1 with the reason in err. */
static int db_copy(const char *from, const char *to, char *err, size_t cap)
{
    sqlite3 *src = NULL, *dst = NULL;
    int rc = sqlite3_open_v2(from, &src, SQLITE_OPEN_READONLY, NULL);
    if (rc != SQLITE_OK) {
        snprintf(err, cap, "cannot open %s: %s", from, src ? sqlite3_errmsg(src) : "out of memory");
        sqlite3_close(src);
        return -1;
    }
    sqlite3_busy_timeout(src, 4000);
    rc = sqlite3_open_v2(to, &dst, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
    if (rc != SQLITE_OK) {
        snprintf(err, cap, "cannot open %s: %s", to, dst ? sqlite3_errmsg(dst) : "out of memory");
        sqlite3_close(src);
        sqlite3_close(dst);
        return -1;
    }
    sqlite3_busy_timeout(dst, 5000);
    sqlite3_backup *b = sqlite3_backup_init(dst, "main", src, "main");
    if (!b) {
        snprintf(err, cap, "the copy did not start: %s", sqlite3_errmsg(dst));
        sqlite3_close(src);
        sqlite3_close(dst);
        return -1;
    }
    rc = sqlite3_backup_step(b, -1);
    int rc2 = sqlite3_backup_finish(b);
    if (rc != SQLITE_DONE || rc2 != SQLITE_OK)
        snprintf(err, cap, "the copy failed (code %d/%d): %s", rc, rc2, sqlite3_errmsg(dst));
    sqlite3_close(src);
    sqlite3_close(dst);
    return (rc != SQLITE_DONE || rc2 != SQLITE_OK) ? -1 : 0;
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp((const char *)a, (const char *)b);
}

/* Keeps only the KEEP_BACKUPS newest copies app.db.<time>.bak (app.db.first.bak does not match: after the dot it has no digit). */
static void prune_backups(void)
{
    static char names[256][80];
    int n = 0;
    DIR *d = opendir(BACKUP_DIR);
    if (!d)
        return;
    struct dirent *e;
    while ((e = readdir(d)) != NULL && n < 256) {
        size_t l = strlen(e->d_name);
        if (strncmp(e->d_name, "app.db.2", 8) == 0 && l > 4 && l < 80 && strcmp(e->d_name + l - 4, ".bak") == 0)
            snprintf(names[n++], sizeof(names[0]), "%s", e->d_name);
    }
    closedir(d);
    qsort(names, (size_t)n, sizeof(names[0]), cmp_str);
    for (int i = 0; i < n - KEEP_BACKUPS; i++) {
        char p[300];
        snprintf(p, sizeof(p), "%s/%s", BACKUP_DIR, names[i]);
        unlink(p);
    }
}

/* The very first copy (app.db.first.bak, never overwritten) and one with a time stamp. 0 or -1. */
static int backup_db(void)
{
    char first[220], tmp[230], path[220], err[200] = "", ts[32];
    ensure_dir(BACKUP_DIR);
    snprintf(first, sizeof(first), "%s/app.db.first.bak", BACKUP_DIR);
    if (access(first, F_OK) != 0) {
        snprintf(tmp, sizeof(tmp), "%s.tmp", first);
        unlink(tmp);
        if (db_copy(APP_DB, tmp, err, sizeof(err)) != 0 || rename(tmp, first) != 0) {
            say("backup failed: %s", err[0] ? err : "cannot rename the file");
            unlink(tmp);
            return -1;
        }
        say("the first backup is made (it is never overwritten)");
    }
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    strftime(ts, sizeof(ts), "%Y%m%d-%H%M%S", &tmv);
    snprintf(path, sizeof(path), "%s/app.db.%s.bak", BACKUP_DIR, ts);
    err[0] = 0;
    if (db_copy(APP_DB, path, err, sizeof(err)) != 0) {
        say("backup failed: %s", err);
        unlink(path);
        return -1;
    }
    prune_backups();
    return 0;
}

/* ---------- the database ---------- */

static int has_col(sqlite3 *db, const char *table, const char *col)
{
    sqlite3_stmt *st = NULL;
    int yes = 0;
    if (sqlite3_prepare_v2(db, "SELECT 1 FROM pragma_table_info(?1) WHERE name=?2", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, table, -1, SQLITE_STATIC);
        sqlite3_bind_text(st, 2, col, -1, SQLITE_STATIC);
        yes = sqlite3_step(st) == SQLITE_ROW;
    }
    sqlite3_finalize(st);
    return yes;
}

static int name_ok(const char *s)
{
    if (!*s || strlen(s) >= UID_LEN)
        return 0;
    for (; *s; s++)
        if (!((*s >= '0' && *s <= '9') || (*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z') || *s == '_'))
            return 0;
    return 1;
}

/* The users: the suffixes of the tables tbl_iconinfo_<uid>. Returns how many. */
static int user_ids(sqlite3 *db, char uids[][UID_LEN], int max)
{
    sqlite3_stmt *st = NULL;
    int n = 0;
    if (sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'tbl_iconinfo_%' ORDER BY name", -1, &st, NULL) == SQLITE_OK) {
        while (sqlite3_step(st) == SQLITE_ROW && n < max) {
            const char *nm = (const char *)sqlite3_column_text(st, 0);
            if (nm && strncmp(nm, "tbl_iconinfo_", 13) == 0 && name_ok(nm + 13))
                snprintf(uids[n++], UID_LEN, "%s", nm + 13);
        }
    }
    sqlite3_finalize(st);
    return n;
}

static void quick_check(char *out, size_t cap)
{
    sqlite3 *db = NULL;
    snprintf(out, cap, "not done");
    if (sqlite3_open_v2(APP_DB, &db, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        sqlite3_close(db);
        return;
    }
    sqlite3_busy_timeout(db, 3000);
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &st, NULL) == SQLITE_OK && sqlite3_step(st) == SQLITE_ROW)
        snprintf(out, cap, "%s", (const char *)sqlite3_column_text(st, 0));
    sqlite3_finalize(st);
    sqlite3_close(db);
}

/* A number from a query with parameters (?1 text, ?2 number); def when there is no row. */
static int query_int(sqlite3 *db, const char *sql, const char *b1, int b2, int def)
{
    sqlite3_stmt *st = NULL;
    int v = def;
    if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, b1, -1, SQLITE_STATIC);
        sqlite3_bind_int(st, 2, b2);
        if (sqlite3_step(st) == SQLITE_ROW)
            v = sqlite3_column_int(st, 0);
    }
    sqlite3_finalize(st);
    return v;
}

static void tile_name(sqlite3 *db, const char *id, char *out, size_t cap)
{
    sqlite3_stmt *st = NULL;
    out[0] = 0;
    if (sqlite3_prepare_v2(db, "SELECT titleName FROM tbl_contentinfo WHERE titleId=?1", -1, &st, NULL) == SQLITE_OK) {
        sqlite3_bind_text(st, 1, id, -1, SQLITE_STATIC);
        if (sqlite3_step(st) == SQLITE_ROW && sqlite3_column_text(st, 0))
            snprintf(out, cap, "%s", (const char *)sqlite3_column_text(st, 0));
    }
    sqlite3_finalize(st);
}

int sth_run(void)
{
    char uids[MAX_USERS][UID_LEN], chk[80];
    host_paths();
    say("tiles: %s, %s", TILES[0].id, TILES[1].id);
    if (backup_db() != 0) {
        finish("nothing was changed (no backup)", "ничего не менял (нет копии базы)");
        return 1;
    }
    sqlite3 *db = NULL;
    if (sqlite3_open_v2(APP_DB, &db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK) {
        say("cannot open %s for writing: %s", APP_DB, db ? sqlite3_errmsg(db) : "out of memory");
        sqlite3_close(db);
        finish("nothing was changed (database not opened)", "ничего не менял (база не открылась)");
        return 1;
    }
    sqlite3_busy_timeout(db, 5000);
    int nu = user_ids(db, uids, MAX_USERS);
    if (nu <= 0) {
        say("no tables tbl_iconinfo_* in the database");
        sqlite3_close(db);
        finish("nothing was changed (unexpected database)", "ничего не менял (неожиданная база)");
        return 1;
    }
    for (int u = 0; u < nu; u++) {
        char tbl[80];
        snprintf(tbl, sizeof(tbl), "tbl_iconinfo_%s", uids[u]);
        if (!has_col(db, tbl, "visible") || !has_col(db, tbl, "titleId")) {
            say("%s has no columns titleId/visible", tbl);
            sqlite3_close(db);
            finish("nothing was changed (unexpected database)", "ничего не менял (неожиданная база)");
            return 1;
        }
    }
    if (sqlite3_exec(db, "BEGIN IMMEDIATE", NULL, NULL, NULL) != SQLITE_OK) {
        say("the system keeps the database busy: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        finish("nothing was changed (database busy)", "ничего не менял (база занята)");
        return 1;
    }
    /* what to do depends on the state read inside the transaction: any tile shown means hide, all hidden means show */
    int total = 0, shown = 0;
    for (int u = 0; u < nu; u++)
        for (int i = 0; i < NTILES; i++) {
            char sql[200];
            snprintf(sql, sizeof(sql), "SELECT count(*) FROM \"tbl_iconinfo_%s\" WHERE titleId=?1", uids[u]);
            total += query_int(db, sql, TILES[i].id, 0, 0);
            snprintf(sql, sizeof(sql), "SELECT count(*) FROM \"tbl_iconinfo_%s\" WHERE titleId=?1 AND visible IS NOT ?2", uids[u]);
            shown += query_int(db, sql, TILES[i].id, 0, 0);
        }
    if (total == 0) {
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        sqlite3_close(db);
        say("none of the tiles is in the database");
        finish("nothing was changed (tiles not found)", "ничего не изменено (плиток нет в базе)");
        return 1;
    }
    int visible = shown == 0;
    if (visible)
        say("The tiles were hidden, so they are shown again. / Плитки были скрыты, поэтому возвращаю их.");
    else if (shown == total)
        say("The tiles were shown, so they are hidden. / Плитки были видны, поэтому скрываю их.");
    else
        say("Some tiles were shown and some hidden, so all are hidden. / Часть плиток видна, часть скрыта: скрываю все.");
    int found = 0, fail = 0;
    for (int i = 0; i < NTILES && !fail; i++) {
        int hit = 0;
        char name[96];
        tile_name(db, TILES[i].id, name, sizeof(name));
        for (int u = 0; u < nu; u++) {
            char sql[200];
            snprintf(sql, sizeof(sql), "UPDATE \"tbl_iconinfo_%s\" SET visible=?1 WHERE titleId=?2", uids[u]);
            sqlite3_stmt *st = NULL;
            int rc = sqlite3_prepare_v2(db, sql, -1, &st, NULL);
            if (rc == SQLITE_OK) {
                sqlite3_bind_int(st, 1, visible);
                sqlite3_bind_text(st, 2, TILES[i].id, -1, SQLITE_STATIC);
                rc = sqlite3_step(st);
            }
            if (rc != SQLITE_DONE) {
                say("write error for %s: %s", TILES[i].id, sqlite3_errmsg(db));
                fail = 1;
            } else {
                hit += sqlite3_changes(db);
            }
            sqlite3_finalize(st);
        }
        if (hit) {
            found++;
            say("%s %s: visible=%d (rows: %d)", TILES[i].id, name[0] ? name : TILES[i].name, visible, hit);
        } else if (!fail) {
            say("%s %s: not in the database, skipped", TILES[i].id, TILES[i].name);
        }
    }
    if (fail || !found) {
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        sqlite3_close(db);
        if (!fail)
            say("none of the tiles is in the database");
        finish("nothing was changed (rolled back)", "ничего не изменено (откат)");
        return 1;
    }
    if (sqlite3_exec(db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK) {
        say("COMMIT failed: %s", sqlite3_errmsg(db));
        sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
        sqlite3_close(db);
        finish("nothing was changed", "ничего не изменено");
        return 1;
    }
    sqlite3_close(db);
    quick_check(chk, sizeof(chk));
    int bad = 0;
    sqlite3 *rb = NULL;
    if (sqlite3_open_v2(APP_DB, &rb, SQLITE_OPEN_READONLY, NULL) != SQLITE_OK) {
        sqlite3_close(rb);
        rb = NULL;
    }
    if (rb) {
        sqlite3_busy_timeout(rb, 3000);
        for (int u = 0; u < nu; u++)
            for (int i = 0; i < NTILES; i++) {
                char sql[200];
                snprintf(sql, sizeof(sql), "SELECT count(*) FROM \"tbl_iconinfo_%s\" WHERE titleId=?1 AND visible<>?2", uids[u]);
                bad += query_int(rb, sql, TILES[i].id, visible, 0);
            }
        sqlite3_close(rb);
    } else {
        bad = -1;
    }
    say("database check: %s; read back: %s", chk, bad == 0 ? "matches" : "DOES NOT MATCH");
    say("If a tile is still on the screen, enter a game and come back, or reboot the console.");
    say("Если плитка осталась на экране, зайдите в игру и вернитесь или перезагрузите консоль.");
    int ok = bad == 0 && strcmp(chk, "ok") == 0;
    if (visible)
        finish(ok ? "tiles shown" : "CHECK FAILED", ok ? "плитки показаны" : "ПРОВЕРКА НЕ ПРОШЛА");
    else
        finish(ok ? "tiles hidden" : "CHECK FAILED", ok ? "плитки скрыты" : "ПРОВЕРКА НЕ ПРОШЛА");
    return ok ? 0 : 1;
}
