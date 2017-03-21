#!/bin/bash

#######################################################
#		MAIN SCRIPT TRANSCODE API - mAloTV
#######################################################

###Description
# This script to control transcode process. It has some function:
#	- Initialize a/some transcode process(es) if it has not any transcode process before
#	- Add more a/some transcode process(es) if it had some running transcode process
###

echo -e "Ban co muon khoi tao hay them tien trinh transcode?\n"
echo -e "1.Khoi tao\n"
echo -e "2.Them\n"
read answer
base_dir=`pwd`
if [ $answer -eq 2 ];then
	echo -ne "Nhap vao so tien trinh muon them: "
	read m
	num_log=`ps -aux 2>/dev/null | grep '/bin/bash' | grep "$base_dir/transcode_api.sh" | wc -l`
	for (( i = 1; i <= $m; i++ ))
	do
		nohup $base_dir/transcode_api.sh $[$num_log + $i] &
	done
elif [ $answer -eq 1 ]; then
	echo -ne "Nhap vao so tien trinh muon chay: "
	read n
	list_process=`ps aux | grep '/bin/bash' | grep "$base_dir/transcode_api.sh" | awk -F ' ' '{print$2}'`
	for k in $list_process; do
		kill -9 $k
	done
	for (( i = 1; i <= $n; i++ ))
	do
		nohup $base_dir/transcode_api.sh $i &
	done
else
		echo -e "Dech, bam lung tung vai???\n"
fi
