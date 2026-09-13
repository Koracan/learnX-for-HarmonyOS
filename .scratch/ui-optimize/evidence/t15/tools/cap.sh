#!/bin/sh
# 在设备侧连拍：先开连拍循环，再在指定延迟后注入点击 —— 这样点击落在连拍窗口内部。
# 用法: cap.sh <tag> <x> <y> <frames> <pre_sleep> <click_sleep>
TAG=$1; X=$2; Y=$3; N=$4; PRE=$5; CLK=$6
DEV=/data/local/tmp/t15
rm -f $DEV/$TAG-*.jpeg $DEV/$TAG-tl.txt
sleep $PRE
( i=0
  while [ $i -lt $N ]; do
    printf 'SNAP %s\n' "$(date +%s%3N)" >> $DEV/$TAG-tl.txt
    snapshot_display -f $DEV/$TAG-$i.jpeg >/dev/null 2>&1
    i=$((i+1))
  done ) &
CAP=$!
sleep $CLK
printf 'CLICK %s\n' "$(date +%s%3N)" >> $DEV/$TAG-tl.txt
uitest uiInput click $X $Y >/dev/null 2>&1
printf 'CLICKED %s\n' "$(date +%s%3N)" >> $DEV/$TAG-tl.txt
wait $CAP
printf 'DONE %s\n' "$(date +%s%3N)" >> $DEV/$TAG-tl.txt
