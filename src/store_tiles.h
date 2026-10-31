/* Store Tile Hider: the code of StoreTileHider.elf. License: GPL-3.0-or-later. */
#ifndef STH_STORE_TILES_H
#define STH_STORE_TILES_H

/* One toggle of the "PlayStation Store" (NPXS40047) and "All Apps" (NPXS40056) tiles of the home screen: if any of them is shown, they are hidden; if all of them are
 * hidden, they are shown again. It sets the column `visible` in every table tbl_iconinfo_<user> of /system_data/priv/mms/app.db, in one transaction; nothing else is changed.
 * Before the change the database is copied to /data/StoreTileHider/backup; after it the database is checked and the result is read back.
 * What was done goes to a notification on the console and to /data/StoreTileHider/last-run.log. Returns 0 on success, otherwise 1. */
int sth_run(void);

#endif
