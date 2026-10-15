#!/bin/bash
psql -h /tmp -p 5499 -U postgres -d postgres -Atc "select 1" >/dev/null 2>&1 && exit 0
B=$(ls -d /usr/lib/postgresql/*/bin | head -1)
rm -f /tmp/pg16data/postmaster.pid
su postgres -c "$B/pg_ctl -D /tmp/pg16data -o '-p 5499 -k /tmp' -l /tmp/pg.log start" >/dev/null 2>&1
sleep 3
psql -h /tmp -p 5499 -U postgres -d postgres -Atc "select 'pg up'"
