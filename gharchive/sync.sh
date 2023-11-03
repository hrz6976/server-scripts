#!/bin/bash

### Add this file to cron.d to run it every day ###
# 0 0 * * * user test -x /home/user/gharchive/sync.sh && bash /home/user/gharchive/sync.sh 2>&1 | tee -a /home/user/gharchive/sync.log

#!/bin/bash

set -e

# import settings from .env
CWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
source $CWD/.env

# Set the timezone to UTC
export TZ=UTC

function run_clickhouse_query() {
    clickhouse-client -h $CLICKHOUSE_HOST --port $CLICKHOUSE_PORT --user $CLICKHOUSE_USER --password $CLICKHOUSE_PASSWORD -q "$1"
}

# find max(file_time) in clickhouse, add 1 hour, convert it to gha format
# if there is no data in clickhouse, set it to 2011-02-11
MAX_TIMESTAMP=$(run_clickhouse_query "SELECT max(file_time) FROM $DB_NAME.$TABLE_NAME")
if [ -z "$MAX_TIMESTAMP" ]; then
    MAX_TIMESTAMP="2011-02-11 00:00:00"
fi
MAX_TIMESTAMP=$(date -d "$MAX_TIMESTAMP 1 hour" +"%Y-%m-%d %H:%M:%S")

NOW_TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

printf "From %s to %s\n" "$MAX_TIMESTAMP" "$NOW_TIMESTAMP"

# run download.sh in the same directory
bash $CWD/download.sh "$MAX_TIMESTAMP" "$NOW_TIMESTAMP"

# run import.sh in the same directory
bash $CWD/import.sh