#!/bin/bash

set -e

# import settings from .env
CWD=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
source $CWD/.env

IMPORTLIST_PATH=$(realpath $CWD/importlist.txt)

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

# Create download directory if it doesn't exist
if [ ! -d "$DOWNLOAD_DIR" ]; then
    mkdir -p $DOWNLOAD_DIR
fi

function run_clickhouse_query() {
    clickhouse-client -h $CLICKHOUSE_HOST --port $CLICKHOUSE_PORT --user $CLICKHOUSE_USER --password $CLICKHOUSE_PASSWORD -q "$1"
}

# Use an associative array to check the existence of a timestamp in clickhouse in O(1)
declare -A TIMESTAMP_CHECK=()

function is_timestamp_exists() {
    return ${TIMESTAMP_CHECK["${1}"]+1}
}

ALL_TIMESTAMPS=$(run_clickhouse_query "SELECT DISTINCT(file_time) FROM $DB_NAME.$TABLE_NAME")
printf "%d dumps in Clickhouse\n" $(wc -l <<< "$ALL_TIMESTAMPS")

# import all timestamps to TIMESTAMP_CHECK
while read -r TIMESTAMP; do
    TIMESTAMP_CHECK["${TIMESTAMP}"]=1
done <<< "$ALL_TIMESTAMPS"

if [ -f $IMPORTLIST_PATH ]; then
    mv $IMPORTLIST_PATH $IMPORTLIST_PATH.bak
fi

for file in $(ls $DOWNLOAD_DIR/*.json.gz); do
    # get timestamp from filename %Y-%m-%d %H:%M:%S
    TIMESTAMP=$(basename $file | sed 's/\.json\.gz//' | sed 's/\(.*\)\(\-\)/\1 /' | date -f - +"%Y-%m-%d %H:%M:%S")
    # check if timestamp exists in TIMESTAMP_CHECK
    if [ ! ${TIMESTAMP_CHECK["${TIMESTAMP}"]+1} ]; then
        echo "Adding" $file "@" $TIMESTAMP
        # if not exists, add to filelist.txt
        printf "${file}\n" >> $IMPORTLIST_PATH
    else
        if [ ! -z $CLEANUP ]; then
            echo "Removing" $file "@" $TIMESTAMP
            # if exists, remove the file
            rm $file
        fi
    fi
done

# remove the \n at the end of the file
truncate -s -1 $IMPORTLIST_PATH

echo "Importing $(cat $IMPORTLIST_PATH | wc -l) files on $NPROC workers, first is $(cat $IMPORTLIST_PATH | head -n1)"

PREV_N_RECORDS=$(run_clickhouse_query "SELECT count() FROM $DB_NAME.$TABLE_NAME")

cat $IMPORTLIST_PATH | xargs -P${NPROC} -I{} bash -c "
gzip -cd {} | jq -c '
[
    (\"{}\" | scan(\"[0-9]+-[0-9]+-[0-9]+-[0-9]+\")),
    .type,
    .actor.login? // .actor_attributes.login? // (.actor | strings) // null,
    .repo.name? // (.repository.owner? + \"/\" + .repository.name?) // null,
    .created_at,
    .payload.updated_at? // .payload.comment?.updated_at? // .payload.issue?.updated_at? // .payload.pull_request?.updated_at? // null,
    .payload.action,
    .payload.comment.id,
    .payload.review.body // .payload.comment.body // .payload.issue.body? // .payload.pull_request.body? // .payload.release.body? // null,
    .payload.comment?.path? // null,
    .payload.comment?.position? // null,
    .payload.comment?.line? // null,
    .payload.ref? // null,
    .payload.ref_type? // null,
    .payload.comment.user?.login? // .payload.issue.user?.login? // .payload.pull_request.user?.login? // null,
    .payload.issue.number? // .payload.pull_request.number? // .payload.number? // null,
    .payload.issue.title? // .payload.pull_request.title? // null,
    [.payload.issue.labels?[]?.name // .payload.pull_request.labels?[]?.name],
    .payload.issue.state? // .payload.pull_request.state? // null,
    .payload.issue.locked? // .payload.pull_request.locked? // null,
    .payload.issue.assignee?.login? // .payload.pull_request.assignee?.login? // null,
    [.payload.issue.assignees?[]?.login? // .payload.pull_request.assignees?[]?.login?],
    .payload.issue.comments? // .payload.pull_request.comments? // null,
    .payload.review.author_association // .payload.issue.author_association? // .payload.pull_request.author_association? // null,
    .payload.issue.closed_at? // .payload.pull_request.closed_at? // null,
    .payload.pull_request.merged_at? // null,
    .payload.pull_request.merge_commit_sha? // null,
    [.payload.pull_request.requested_reviewers?[]?.login],
    [.payload.pull_request.requested_teams?[]?.name],
    .payload.pull_request.head?.ref? // null,
    .payload.pull_request.head?.sha? // null,
    .payload.pull_request.base?.ref? // null,
    .payload.pull_request.base?.sha? // null,
    .payload.pull_request.merged? // null,
    .payload.pull_request.mergeable? // null,
    .payload.pull_request.rebaseable? // null,
    .payload.pull_request.mergeable_state? // null,
    .payload.pull_request.merged_by?.login? // null,
    .payload.pull_request.review_comments? // null,
    .payload.pull_request.maintainer_can_modify? // null,
    .payload.pull_request.commits? // null,
    .payload.pull_request.additions? // null,
    .payload.pull_request.deletions? // null,
    .payload.pull_request.changed_files? // null,
    .payload.comment.diff_hunk? // null,
    .payload.comment.original_position? // null,
    .payload.comment.commit_id? // null,
    .payload.comment.original_commit_id? // null,
    .payload.size? // null,
    .payload.distinct_size? // null,
    .payload.member.login? // .payload.member? // null,
    .payload.release?.tag_name? // null,
    .payload.release?.name? // null,
    .payload.review?.state? // null
]' | clickhouse-client -h $CLICKHOUSE_HOST --port $CLICKHOUSE_PORT --user $CLICKHOUSE_USER --password $CLICKHOUSE_PASSWORD \
                        --input_format_null_as_default 1 --date_time_input_format best_effort \
                        --query 'INSERT INTO $DB_NAME.$TABLE_NAME FORMAT JSONCompactEachRow' \
                        || echo 'File {} failed to import'
"

NEW_N_RECORDS=$(run_clickhouse_query "SELECT count() FROM $DB_NAME.$TABLE_NAME")

echo "Imported $(($NEW_N_RECORDS - $PREV_N_RECORDS)) records, total $NEW_N_RECORDS records"