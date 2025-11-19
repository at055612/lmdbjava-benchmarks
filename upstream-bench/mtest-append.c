/* mtest-append.c - Howard Chu's benchmark from ITS#10406 */
/*
 * Copyright 2011-2021 Howard Chu, Symas Corp.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted only as authorized by the OpenLDAP
 * Public License.
 *
 * A copy of this license is available in the file LICENSE in the
 * top-level directory of the distribution or, alternatively, at
 * <http://www.OpenLDAP.org/license.html>.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>

#include "lmdb.h"

#define E(expr) CHECK((rc = (expr)) == MDB_SUCCESS, #expr)
#define RES(err, expr) ((rc = expr) == (err) || (CHECK(!rc, #expr), 0))
#define CHECK(test, msg) ((test) ? (void)0 : ((void)fprintf(stderr, \
	"%s:%d: %s: %s\n", __FILE__, __LINE__, msg, mdb_strerror(rc)), abort()))

int main(int argc,char * argv[])
{
	int i = 0, j = 0, rc;
	MDB_env *env;
	MDB_dbi dbi;
	MDB_val key, data;
	MDB_txn *txn;
	MDB_cursor *cursor = NULL;
	int count = 1000000;
	char sval[100] = "";
	struct timeval beg, end;

		E(mdb_env_create(&env));
		E(mdb_env_set_mapsize(env, 1048576000));
		E(mdb_env_open(env, "./testdb", MDB_NOSYNC, 0664));

		E(mdb_txn_begin(env, NULL, 0, &txn));
		E(mdb_dbi_open(txn, NULL, MDB_INTEGERKEY, &dbi));

		key.mv_size = sizeof(int);
		key.mv_data = &i;

		data.mv_size = sizeof(sval);
		data.mv_data = sval;
		printf("Adding %d values\n", count);
		gettimeofday(&beg, NULL);
	    for (i=0;i<count;i++) {
			if (!cursor)
				E(mdb_cursor_open(txn, dbi, &cursor));
			E(mdb_cursor_put(cursor, &key, &data, MDB_APPEND));
			j++;
			if (j == 1000) {
				mdb_cursor_close(cursor);
				cursor = NULL;
				E(mdb_txn_commit(txn));
				E(mdb_txn_begin(env, NULL, 0, &txn));
				j = 0;
			}
	    }
		if (cursor)
			mdb_cursor_close(cursor);
		E(mdb_txn_commit(txn));
		gettimeofday(&end, NULL);

		mdb_dbi_close(env, dbi);
		mdb_env_close(env);

		end.tv_usec -= beg.tv_usec;
		if (end.tv_usec < 0) {
			end.tv_usec += 1000000;
			end.tv_sec--;
		}
		end.tv_sec -= beg.tv_sec;
		printf("Added %d values in %ld.%06ldsec\n", count, end.tv_sec, end.tv_usec);

	return 0;
}
