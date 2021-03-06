#!/bin/bash -e
##-------------------------------------------------------------------
## @copyright 2016 DennyZhang.com
## Licensed under MIT
## https://raw.githubusercontent.com/DennyZhang/devops_public/tag_v1/LICENSE
##
## File : dump_db_summary.sh
## Author : Denny <denny@dennyzhang.com>
## Description :
## Sample:
## --
## Created : <2016-06-04>
## Updated: Time-stamp: <2016-07-12 08:25:45>
##-------------------------------------------------------------------
. /etc/profile

################################################################################
# Plugin Function
function dump_couchbase_summary() {
    local cfg_file=${1?}
    local output_file_prefix=${2?}
    source "$cfg_file"
    tmp_data_file="/tmp/dump_couchbase_$$.log"
    # Get parameters from $cfg_file:
    #    server_ip, tcp_port, cb_username, cb_password
    echo "Call http://${server_ip}:${tcp_port}/pools/default/buckets"
    curl -u "${cb_username}:${cb_passwd}" "http://${server_ip}:${tcp_port}/pools/default/buckets" \
        | python -m json.tool > "$tmp_data_file"

    # parse json to get the summary
    output=$(python -c "import sys,json
list = json.load(sys.stdin)
list = map(lambda x: '%s: %s' % (x['name'], x['basicStats']), list)
print json.dumps(list)" < "$tmp_data_file")
    rm -rf "$tmp_data_file"
    echo "$output" | python -m json.tool > "${output_file_prefix}.out"

    # TODO: key-pair
    # sample output: echo "[11/Jul/2016:14:10:45 +0000] mdm-master CBItemNum 20" >> /var/log/data_report.log
}

function dump_elasticsearch_summary() {
    local cfg_file=${1?}
    local output_file_prefix=${2?}

    stdout_output_file="${output_file_prefix}.out"
    source "$cfg_file"
    # Get parameters from $cfg_file: server_ip, tcp_port
    echo "Call http://${server_ip}:${tcp_port}/_cat/shards?v"
    curl "http://${server_ip}:${tcp_port}/_cat/shards?v" \
         > "$stdout_output_file"

    # output columns: index shard prirep state docs store ip node
    IFS=$'\n'
    for line in $(grep -v "^index " $stdout_output_file | grep "  p  "); do
        unset IFS
        item_name=$(echo $line | awk -F' ' '{print $1}')
        docs=$(echo $line | awk -F' ' '{print $5}')
        # store=$(echo $line | awk -F' ' '{print $6}')
        # TODO: generate disk store data
        insert_elk_entry "$item_name" "ESItemNum" "$docs" "${output_file_prefix}${logstash_postfix}"
    done
}

function insert_elk_entry() {
    local item_name=${1?}
    local property_name=${2?}
    local property_value=${3?}
    local data_file=${4?}

    LANG=en_US
    datetime_utc=$(date -u +['%d/%h/%Y %H:%M:%S +0000'])
    echo "[$datetime_utc] $item_name $property_name $property_value" >> "$data_file"
}

################################################################################
stdout_show_data_out=${1:-"false"}
cfg_dir=${2:-"/opt/devops/dump_db_summary/cfg_dir"}
data_out_dir=${3:-"/opt/devops/dump_db_summary/data_out"}

logstash_postfix="_logstash.txt"
[ -d "$cfg_dir" ] || mkdir -p "$cfg_dir"
[ -d "$data_out_dir" ] || mkdir -p "$data_out_dir"

cd "$cfg_dir"
for f in *.cfg; do
    if [ -f "$f" ]; then
        db_name=${f%%.cfg}
        # Sample: $cfg_dir/mongodb.cfg -> dump_mongodb_summary mongodb.cfg
        fun_name="dump_${db_name}_summary"
        command="$fun_name $f $data_out_dir/${db_name}"
        echo "Run function: $command"
        $command
    fi
done

if [ "$stdout_show_data_out" = "true" ]; then
    cd "$data_out_dir"
    for f in *.out; do
        if [ -f "$f" ]; then
            db_name=${f%%.*}
            echo "Dump $db_name data summary: $data_out_dir/$f"
            cat "$f"
        fi
    done
fi
## File: dump_db_summary.sh ends
