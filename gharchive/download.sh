#!/bin/bash

set -e

# import settings from .env
CWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
source $CWD/.env

FILELIST_PATH=$(realpath $CWD/filelist.txt)

# Set the timezone to UTC
export TZ=UTC

function date_to_gha(){
    # convert %Y-%m-%d %H:%M:%S to %Y-%m-%d-%-H
    echo $(date -d "$1" +"%Y-%m-%d-%-H")
}

function date_from_gha(){
    # convert %Y-%m-%d-%-H to %Y-%m-%d %H:%M:%S
    echo $(date -d "$(echo ${1} | sed 's/\(.*\)\(\-\)/\1 /')" +"%Y-%m-%d %H:%M:%S")
}

function usage(){
    echo "Downloads GHArchive Dumps from $BASE_URL"
    echo "Usage: $0 [start_time] [end_time]"
    echo "Example: $0 \"2011-02-11 00:00:00\" \"2022-02-11 01:00:00\""
    exit 1
}

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    usage
fi

# first argument

# START_TIME in format that GNU date accepts
START_TIME=${1}

# END_TIME in format that GUU date accepts
END_TIME=${2:-$(date +"%Y-%m-%d %H:%M:%S")} # current time

echo "Downloading archives from $START_TIME to $END_TIME"

# Create download directory if it doesn't exist
if [ ! -d "$DOWNLOAD_DIR" ]; then
    mkdir -p $DOWNLOAD_DIR
fi

# if filelist.txt already exists, remove
if [ -f "${FILELIST_PATH}" ]; then
    mv "${FILELIST_PATH}" "${FILELIST_PATH}".bak
fi

# START -> %Y-%m-%d-%-H to %Y-%m-%d %-H:00:00 to %s
START=$(date -d "$START_TIME" "+%s")
END=$(date -d "$END_TIME" "+%s")

for ((i=$START;i<=$END;i+=3600)); do
    HOUR=$(date -d "@${i}" "+%Y-%m-%d-%-H")
    # skip download if file exists and aria2c control file not exists
    if [ -f "$DOWNLOAD_DIR/$HOUR.json.gz" ] && [ ! -f "$DOWNLOAD_DIR/$HOUR.json.gz.aria2" ]; then
        continue
    fi
    printf "\n${BASE_URL}${HOUR}.json.gz" >> ${FILELIST_PATH}
done

printf "Downloading %s files, first is %s\n" $(wc -l ${FILELIST_PATH}) $(cat ${FILELIST_PATH} | head -n1)


# ignore download errors
set +e
# Download the archives using aria2c
# Try with best effort; write files
aria2c -i "${FILELIST_PATH}" -d $DOWNLOAD_DIR --continue=true \
    --auto-file-renaming=false \
    --min-split-size=1M --split=10 \
    --summary-interval=0 \
    --timeout=600 \
    --connect-timeout=60 \
    --max-tries=5 \
    --retry-wait=10 \
    --check-certificate=false \
    --user-agent="Mozilla/5.0 (Windows NT 10.0; rv:78.0) Gecko/20100101 Firefox/78.0" \
    --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
    --header="Accept-Language: en-US,en;q=0.5"

# restore exit on error
set -e

echo "Downloaded archives to $DOWNLOAD_DIR"