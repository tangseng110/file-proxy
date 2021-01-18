#!/usr/bin/env bash

# echo $ts2 |sed "s/\\\/-/g"
# md5sum |awk '{print $1}'

CHECK_FILE=/var/log/nginx/request_json.log.1
CHECK_HOST=https://pd.zwc365.com
CHECK_HOST2=http://pd.zwc365.com

# 一些必须的环境遍历
export LOG_FILENAME=checkhost
TMP_COUNT_KEY="file_proxy_count_check_tmp"
COUNT_SAVE_KEY="file_proxy_count_save_$(echo $CHECK_HOST |md5sum |awk '{print $1}')"
COUNT_YESTERDAY_KEY="file_proxy_count_yesterday_$(echo $CHECK_HOST |md5sum |awk '{print $1}')"
IS_DEBUG=true

if [ "$1"x == "nodebug"x ]; then
    IS_DEBUG=false
fi

function redis-cli(){
    /usr/local/bin/redis-cli -h 127.0.0.1 -p 8888 $@
}

# 重置环境变量
redis_status=`redis-cli set "$TMP_COUNT_KEY" 0`
if [ "$redis_status"x != "OK"x ]; then
    log -o "redis db can not connect"
    exit 0
fi

function checkFile(){
    if [ ! -f "$CHECK_FILE" -o ! -r "$CHECK_FILE" ]; then
        log -o "check file not exists or not read"
        exit 1
    fi
}

function echoItem(){
    echo -E $1 |sed "s/\\\/-/g"
    # echo -E $1
}

function checkLine(){
    host=$1
    if [ "$host"x != "$CHECK_HOST"x -a "$host"x != "$CHECK_HOST2"x ]; then
        return
    fi
    status=$2
    if [ "$status"x != "302"x ]; then
        return
    fi
    url=$4
    # 如果是展示提示页面的情况下，需要减掉 1
    if [[ $url == /showad/* ]]; then
        redis-cli incr "$TMP_COUNT_KEY" -1 >>/dev/null
    fi
    # 下面三种链接前缀都属于使用服务
    if [[ $url == /seturl/* ]]; then
        redis-cli incr "$TMP_COUNT_KEY" 1 >>/dev/null
    fi
    if [[ $url == /cfworker/* ]]; then
        redis-cli incr "$TMP_COUNT_KEY" 1 >>/dev/null
    fi
    if [[ $url == /cfdownload/* ]]; then
        redis-cli incr "$TMP_COUNT_KEY" 1 >>/dev/null
    fi
}

function readFile(){
    cat "$CHECK_FILE" |while read -r line; do
        checkLine `echoItem "$line" |jq -r ".host,.status,.request"`
        # checkLine "aaa"
    done
    lastDayCount=`redis-cli get "$TMP_COUNT_KEY"`
    if [ "$IS_DEBUG"x == "false"x ]; then
        redis-cli set "$COUNT_YESTERDAY_KEY" "$lastDayCount" >>/dev/null
        redis-cli incr "$COUNT_SAVE_KEY" "$lastDayCount" >>/dev/null
    fi
}

function logSave(){
    yesterDayCount=`redis-cli get "$COUNT_YESTERDAY_KEY"`
    fullCount=`redis-cli get "$COUNT_SAVE_KEY"`
    log -o "${CHECK_HOST} save_key: ${COUNT_SAVE_KEY}"
    log -o "${CHECK_HOST} yesterday_key: ${COUNT_YESTERDAY_KEY}"
    log -o "${CHECK_HOST} full request count: ${fullCount}"
    log -o "${CHECK_HOST} yesterday request count: $yesterDayCount"
    log -o "${CHECK_HOST} temp count: $(redis-cli get "$TMP_COUNT_KEY")"
}

start_time=`date +%s`
# 检测文件存在后读取文件
checkFile
readFile

# 使用日志记录一下次数等信息
logSave

# 删除临时的变量
redis-cli del "$TMP_COUNT_KEY" >>/dev/null

cur_time=`date +%s`
has_time=$(($cur_time-$start_time))
echo $has_time


