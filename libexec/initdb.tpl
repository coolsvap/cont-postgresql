#!/bin/bash

. {{ m.pkgdatadir }}/cont-postgresql.sh

CONT_PROJECT=postgresql

test -z "$LANG" && export LANG=en_US.utf8

# Already initialized?
test -f "$(pgcont_opt pgdata)/PG_VERSION" && exit 0

cont_source_hooks preinitdb

initdb_cmd=(initdb -D "$(pgcont_opt pgdata)" -U postgres)
admin_method=peer
if test -n "$POSTGRESQL_ADMIN_PASSWORD"; then
    cont_info "setting up admin password"
    "${initdb_cmd[@]}" --pwfile=<(echo "$POSTGRESQL_ADMIN_PASSWORD") || exit 1
    admin_method=md5
else
    "${initdb_cmd[@]}" || exit 1
fi

# Initdb refuses to create pg_hba.conf with md5 auth method without specifying
# administrator password explicitly.  Work-around that fact.
cat > "$(pgcont_opt pghba)" <<EOF
# PostgreSQL Client Authentication Configuration File
# ===================================================
#
# Note that this is auto-generated file by rhel-docker-initdb script.  If you
# wan't to change this file, the quick syntax documentation may be found in
# /usr/share/pgsql/pg_hba.conf.sample file.

# TYPE  DATABASE        USER            ADDRESS                 METHOD
# --------------------------------------------------------------------
local   all             postgres                                $admin_method
local   all             all                                     md5
host    all             all             ::/0                    md5
host    all             all             0.0.0.0/0               md5
EOF

pgcont_config_set_option listen_addresses "'*'"

pgcont_config_use_var POSTGRESQL_CONFIG

if test -n "$POSTGRESQL_DATABASE" \
   && test -n "$POSTGRESQL_USER" \
   && test -n "$POSTGRESQL_PASSWORD"
then
    cont_info "creating simple database '$POSTGRESQL_DATABASE'"
    # We need to setup .pgpass file.  On clean image, no .pgpass exists and we
    # count with that.
    if test -n "$POSTGRESQL_ADMIN_PASSWORD"; then
        cont_debug "temporarily storing admin's password into ~/.pgpass"
        # According to this:
        # http://www.postgresql.org/message-id/1324323646-sup-3128@alvh.no-ip.org
        # We should *not* escape if we run with pre-9.2 psql.
        echo "localhost:*:postgres:postgres:${POSTGRESQL_ADMIN_PASSWORD//:/\\:}" \
            > "{{ m.pghome }}/.pgpass"
        chmod 600 "{{ m.pghome }}/.pgpass"
    fi
    pgcont_server_start_local
    pgcont_create_simple_db "$POSTGRESQL_DATABASE" "$POSTGRESQL_USER" \
                            "$POSTGRESQL_PASSWORD"
    pgcont_server_stop

    rm -rf "{{ m.pghome }}/.pgpass"
fi

cont_source_hooks postinitdb
