#!/bin/bash

#################################################
#	SCRIPT TRANSCODE API - mAloTV
#################################################
###Description
#Input: $transcode_id: is transcode process number. The main process count number of transcode process to generate a/some new transcode process(es)
#Ouptput: log_files: include
#			- duplicate.log				: store infor about error file which be duplicated with a previous raw
#			- error_trans_process.log	: store general error information of all transcode fuctions. It is useful to troubleshoot
#			- check_duplicate.log		: store hash code of raw files. It is used to check duplicate file
###

###Configuration parameters
cms='transcode.tvod.vn' #IP CMS
cms_type='all'	#(cdn,tvod)
cms_port='80'
sleep_time=180
disk_id='disk8'
file_dir="/opt/transcode/file/$disk_id"
log_dir='/opt/transcode/logs'
error_dir="$log_dir/error"
logo_path='/path/to/Logo-TVOD-1280.png'
#fix ratio
fix_ratio=1.55

#temp folder store subtitle srt & ass
tmp_dir='/opt/temp'
temp_srt="$tmp_dir/temp$1.srt"
temp_ass="$tmp_dir/temp$1.ass"
###########################
#check & make folder
mkdir -p $error_dir
mkdir -p $file_dir
mkdir -p $tmp_dir

###FUNCTION
###########################

#function check_mount
#Desc: check mount connection
#input: $raw_path
#0 is ok, 1 is nok
function check_mount {
	mount_point=`echo $raw_path | awk -F'/' '{print$1,$2,$3}' | tr ' ' '/'`
	if mount | grep $mount_point > /dev/null; then
		return 0
	else
		echo -e "$(date)		Error: Can't mount to Origin.....Check immediately,plz " >> $error_dir/error_trans_process.log
		return 1
	fi	
}

#function check cms connection
#input $cms $cms_port
function check_cms {
	nc -z -w2 $1 $2 
	if [ $? -ne 0 ]; then
		echo -e "$(date)		FATAL Error: Oooop.....connection to cms $cms error\n" >> $error_dir/error_trans_process.log
		sleep $sleep_time && continue
	fi	
}

#function call_api
#Input: $api 
#Output: $temp1, $temp2, $temp3
function call_api {
	local output=`curl -m 5 "$1" | sed 's/\({\|"\|}\)//g'`
	echo -e "$(date)		Info: Getting url result: $output \n" >> $error_dir/error_trans_process.log
	temp1=`echo $output | awk -F';' '{print$1}'`
	temp2=`echo $output | awk -F';' '{print$2}'`
	temp3=`echo $output | awk -F';' '{print$3}'`
}

#function fault_func
#Desc: This function will be called when process be fail
#Input: $1
#		1: update cms to inform that raw is error (can not transcode) and set this file to inactive status
#		2: update cms to inform that transcode process is error while raw file still transcode normally and resume status to active
function fault_func {
	if [ $1 -eq 1 ]; then
		err_link="http://${cms}:${cms_port}/data/setFileStatus?id=$id&message_error=$2"
		echo -e "$(date)		Error: This raw $temp_path is error: $2" >> $error_dir/error_trans_process.log
	else
		err_link="http://${cms}:${cms_port}/data/resetRawFile?id=$id"
		echo -e "$(date)		Error: The transcode process is error with $temp_path" >> $error_dir/error_trans_process.log
	fi
	mv "$temp_path" "$raw_path" 2>/dev/null
# Remove hash in check_duplicate file
	local hash=`cat $log_dir/hash.tmp | grep $id | awk -F' ' '{print$1}'`
	sed -i "/$hash/ s/^.*$//;/^\s*$/d" $log_dir/check_duplicate.log
	call_api $err_link
	sleep $sleep_time && continue		
}


#function standardize_name
#Input: $raw_path (video's name, subtitle's name)
#Output: $temp_path
function standardize_name {
	raw_dir=`dirname "$1"`
	old_name=`basename "$1"`
	stand_name=`echo ${old_name%.*} | tr '[:upper:]' '[:lower:]' | tr -c [:alnum:][:cntrl:] - |tr -s - - | sed 's/^-//' | sed 's/-$//'`
	ext=`echo ${old_name##*.}`
	temp_path="$raw_dir/$stand_name.$ext"
	mv "$1" "$temp_path" 2>/dev/null
}


#function check_raw
#	- check_raw
#	- check_format
#	- check_duplicate

#Check existence and duration video raw
#input: $raw_path
#output: 0 is ok, 1 is nok

function check_raw {
	if [ -f $1 ]; then
		local duration_raw=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries format=duration $1 | cut -d '.' -f1`
		if [ $duration_raw -ne 0 ]; then
			return 0
		else
			echo -e "$(date)		Error: video raw $raw_path is not a video" >> $error_dir/error_trans_process.log
			echo 1
			fault_func 1 'The raw is not a video'
		fi
	else
		echo 1
		fault_func 1 'The raw is not existed'
	fi
}

function check_format {
	local list="mp4 wav avi mkv flv mp3 3gp wmv m4v ts mov vob mpg divx webm tp mpeg"
	local file=$(basename $1)
	local ext=`echo ${file##*.}`
	if [[ $list =~ $ext ]]; then
		echo 0
	else
		echo "$(date)		Error: This extension is not support for $raw_path" >> $error_dir/error_trans_process.log
		echo 1
		fault_func 1 'This extension is not support'
	fi
}

function check_duplicate {
#Module hash file MD5
	local filesize=`stat -c %s "$1"`
	local skipamount="$((${filesize} / 2048))"
	local MD5FILE=`dd if="$1" bs=1024 count=2 skip=$skipamount 2>/dev/null |md5sum |cut -d ' ' -f1`
#Check in check_duplicate.log; if existed, skip and write to duplicate.log. Otherise, add hash code to check_duplicate.log file
	grep -m 1 $MD5FILE $log_dir/check_duplicate.log >/dev/null
	if [ $? -eq 0 ]; then
			echo -e "$(date)		$id - $raw_path - $MD5FILE" >> $error_dir/duplicate.log
			echo -e "$(date)		Error: $raw_path is duplicate video, check again,plz" >> $error_dir/error_trans_process.log
			echo -e "					If you still want to transcode this video, you should remove $MD5FILE in $log_dir/check_duplicate.log" >> $error_dir/error_trans_process.log
			echo 1
			fault_func 1 'Duplicated video'
	else
			echo "$MD5FILE" >> $log_dir/check_duplicate.log
			echo "$MD5FILE $id" >> $log_dir/hash.tmp
			echo 0
	fi
}

#function check_sub
#input: $raw_path $temp_srt $temp_ass
#output: 0 is ok, 1 is no subtitle
function check_sub {
	sub_path=`echo $1 | sed 's/\..*$/\.srt/'`
	if [ -f $sub_path ]; then
		check_sub=$(file -bi $sub_path |grep -i utf-16)
            if [ $? == 0 ]; then
                iconv -f UTF-16 -t UTF-8 $sub_path > $2
            else
                cp -f $sub_path $2
            fi
        ffmpeg -f srt -i $2 -f ass -y $3 >/dev/null 2>&1
#		rm -rf $sub_path
		return 0;
	else
		echo '' > $3
		echo -e "$(date)		Warning: No subtitle for $1" >> $error_dir/error_trans_process.log
		return 1;
	fi
}

###########################
# FUNCTIONS BUILD VIDEO FILTER, VIDEO OPTION AND AUDIO OPTION 
###########################

#Build video filter
#Input: $raw_path $width_max $height_max $temp_ass
function build_vf {
    file_width=$(ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=width $1 | head -n 1)
    file_height=$(ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=height $1 | head -n 1)
    file_ratio=$(echo "scale=2;$file_width/$file_height"|bc)
    compare_ratio=$(echo "$file_ratio > $fix_ratio"|bc)
    if [ $compare_ratio -eq 1 ]; then
        vf="scale=$2:trunc'(ow/a/2)'*2"
    else
        vf="scale=trunc'(oh/a/2)'*2:$3"
    fi
	if [ "$2" == "176" ]; then
		vf="scale=176x144"
	fi
    if [ "$4" != "" ]; then
        vf="ass=$4,$vf"
    fi
    echo $vf
}

#Build video option (codec, bitrate, filter, preset)
#Input: $codec $bitrate $vf $preset
function build_video {
    if [ "$4" == "" ]; then
        echo -c:v $1 -b:v $2 -vf $3 -vsync -1
    else
        echo -c:v $1 -b:v $2 -vf $3 -vpre $4 -vsync -1
    fi
}

#Build_audio (codec, bitrate, channel, rate, volume)
#Input: $codec $bitrate $channel $rate $volume
function build_audio {
    echo -c:a $1 -b:a $2 -ac $3 -ar $4 -af volume=$5
}


#Build output
#Input: $temp_path $video_version
function output {
	raw_name=$(basename $1)
    raw_name_no_ext=$(echo ${raw_name%.*})
	#output
	mkdir -p "$destination_folder/${raw_name_no_ext}_$2.ssm"
#output format for Feature Phone is 3GP, the other is ISMV
	if [ $2 == 'FP' ]; then
		echo "$destination_folder/${raw_name_no_ext}_$2.ssm/${raw_name_no_ext}_$2.3gp"
	else
		echo "$destination_folder/${raw_name_no_ext}_$2.ssm/${raw_name_no_ext}_$2.ismv"
	fi
}

#Build file m3u8
#Input: $output_version ($output_SU, $output_SD,...)
function build_m3u8 {
	mp4split -o `echo $1 | sed 's/ismv/ism/'` $1
	mp4split -o `echo $1 | sed 's/ismv/m3u8/'` `echo $1 | sed 's/ismv/ism/'`
}

#Function check ouput file
#file after transcode completely should compare duration with raw file to know whether transcode successful or not
#Input: $transcoded_file 
#Output: 0 is ok, 1 not ok
function check_output {
	duration_file=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries format=duration $1 | cut -d '.' -f1`
	if [ `expr $duration_file \* 100 / $duration_raw` -lt 95 ]; then
		echo "$(date)		Error: File after transcode has too short duration than original raw file. Check raw $raw_path, plz" >> $error_dir/error_trans_process.log
		return 1
	else
		return 0
	fi
}


######################################################
#MAIN BODY - TRANSCODE PROCESS
######################################################

while [ 1 ]; do

#get & process raw infor
	check_cms $cms $cms_port
	get_link="http://${cms}:${cms_port}/data/getWaitingFile"
	call_api $get_link
	id=$temp1
	raw_path=$temp2
#	raw_path='/opt/raw/est @#$#@$phongnh 123$%^&.mkv'
#	raw_path='/opt/transcode/raw/Phim/Transcode_27_03_2015/Horrible_Bosses_2_2014/Horrible_Bosses_2_2014.mkv'
	result=$temp3
	if [ "$result" -ne 1 ]; then
		echo "$(date)		Warning: no raw file .....go to bed...zzz...zzz" >> $error_dir/error_trans_process.log
		sleep $sleep_time && continue
	else
		check_mount $raw_path
		if [ $? -eq 1 ]; then
			sleep $sleep_time && continue
		fi
	
		SAVEIFS=$IFS
		IFS=$'\n'
			standardize_name  "$raw_path"
			check_sub $raw_path $temp_srt $temp_ass
			if [ $? -eq 1 ]; then
				sub=''
			else
				sub=$temp_ass
			fi
		IFS=$SAVEIFS	
		
		if [[ $(check_raw $temp_path) -eq 0 && $(check_format $temp_path) -eq 0 && $(check_duplicate $temp_path) -eq 0 ]]; then		
#Check vs cut folder destination
			if [ `ls $file_dir | grep video-file- | wc -l` -eq 0 ]; then
				mkdir -p $file_dir/video-file-0
			fi
			exist_num=`ls -dt $file_dir/video-file-* | head -n 1 | cut -d '-' -f3`
			destination_folder="$file_dir/video-file-$exist_num"
			file_total=`ls $destination_folder | wc -l`
			
			if [ "$file_total" -ge 1000 ]; then
					next_num=$[exist_num + 1]
					destination_folder=$file_dir/video-file-$next_num
					mkdir -p $destination_folder				
			fi
#/opt/transcode/file/$disk_id/video-file-$number/$stand_name_HD.ssm/$stand_name_HD.ismv
			base_dir=`echo $destination_folder | awk -F'/' '{print$NF,$(NF-1)}' | sed 's# #\/#'`

			main_opt="-loglevel warning -i $temp_path -i $logo_path -y -map_chapters -1 -filter_complex overlay=main_w-overlay_w-10:10,split=4[out1][out2][out3][out4]"
			filter_output1="-map [out1]"
			filter_output2="-map [out2]"
			filter_output3="-map [out1]"
			filter_output4="-map [out2]"
			filter_output5="-map [out1]"
			video_SU=$(-map "[out1]" build_video libx264 3000k $(build_vf $temp_path 1280 720))
			audio_SU=$(build_audio libfaac 128k 2 44100 2)
			output_SU=$(output $temp_path SU)
			
			video_HD=$(-map "[out2]" build_video libx264 1300k $(build_vf $temp_path 1280 720))
			audio_HD=$(build_audio libfaac 128k 2 44100 2)
			output_HD=$(output $temp_path HD)
			
			video_SD=$(-map "[out3]" build_video libx264 800k $(build_vf $temp_path 640 480))
			audio_SD=$(build_audio libfaac 96k 2 44100 2)
			output_SD=$(output $temp_path SD)
			
			video_MB=$(-map "[out4]" build_video libx264 300k $(build_vf $temp_path 320 240 ) ipod640) 
			audio_MB=$(build_audio libfaac 64k 2 44100 2)
			output_MB=$(output $temp_path MB)
			
			video_FP=$(-map "[out5]" build_video h263 96k $(build_vf $temp_path 176 144 $sub))
			audio_FP=$(build_audio libopencore_amrnb 12.20k 1 8000 2)
			output_FP=$(output $temp_path FP)
			echo "ffmpeg $main_opt $video_SU $audio_SU $output_SU $video_HD $audio_HD $output_HD $video_SD $audio_SD $output_SD $video_MB $audio_MB $output_MB" >> $error_dir/error_trans_process.log
			ffmpeg $main_opt $filter_output1 $video_SU $audio_SU $output_SU $filter_output2 $video_HD $audio_HD $output_HD $filter_output3 $video_SD $audio_SD $output_SD $filter_output4 $video_MB $audio_MB $output_MB 
			if [ $? -ne 0 ]; then
#if transcode fail, log && recover raw_path
				echo "$(date)		Error: Detected raw_file has been corrupted with $raw_path" >> $error_dir/error_trans_process.log
				fault_func 2
			fi
			
#check file video after transcode with SU version
			duration_raw=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries format=duration $temp_path | cut -d '.' -f1`
			check_output $output_SU
			if [ $? -eq 1 ]; then
				fault_func 1 'File after transcode has too short duration than original raw file'
			fi	
#Remove raw file
#			rm -rf $temp_path
#			rm -rf $sub_path

#build m3u8 file for each video version		
			build_m3u8 $output_SU
			build_m3u8 $output_HD
			build_m3u8 $output_SD
			build_m3u8 $output_MB
		
###Process && update file infor after transcode for multiple version
			./transcode_update_cms.sh $cms_type $id $output_SU >> $error_dir/error_trans_process.log
			./transcode_update_cms.sh $cms_type $id $output_HD >> $error_dir/error_trans_process.log
			./transcode_update_cms.sh $cms_type $id $output_SD >> $error_dir/error_trans_process.log
			./transcode_update_cms.sh $cms_type $id $output_MB >> $error_dir/error_trans_process.log
#Remove hash in hash.tmp
			sed -i "/$id/ s/^.*$//;/^\s*$/d" $log_dir/hash.tmp
		fi
	fi
done
