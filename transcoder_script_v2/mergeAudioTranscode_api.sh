#!/bin/bash

#################################################
#	SCRIPT TRANSCODE API - MSP
#################################################
###Description
#Input: $transcode_id: is transcode process number. The main process count number of transcode process to generate a/some new transcode process(es)
#Ouptput: log_files: include
#			- duplicate.log				: store infor about error file which be duplicated with a previous raw
#			- error_trans_process.log	: store general error information of all transcode fuctions. It is useful to troubleshoot
#			- check_duplicate.log		: store hash code of raw files. It is used to check duplicate file
###

###Configuration parameters
cms='10.84.85.137'
cms_port='81'
disk_id='disk01'    ###if change this, must also change $file_path of update_cms function##
raw_dir="/storage/$disk_id/raw"
file_dir="/storage/$disk_id/file"
log_dir='/opt/logs'
error_dir="$log_dir/error"
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
#	mount_point=`echo $raw_path | awk -F'/' '{print$1,$2,$3}' | tr ' ' '/'`
	if mount | grep "$file_dir" > /dev/null; then
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

#function fault_func
#Desc: This function will be called when process be fail
#Input: $1
#		1: update cms to inform that raw is error (can not transcode) and set this file to inactive status
#		2: update cms to inform that transcode process is error while raw file still transcode normally and resume status to active
function fault_func {
	if [ $1 -eq 1 ]; then
		status_code=7
	else
		status_code=6
	fi
	mv "$temp_path" "$raw_path" 2>/dev/null
# Remove hash in check_duplicate file
	local hash=`cat $log_dir/hash.tmp | grep $profile_id | awk -F' ' '{print$1}'`
	sed -i "/$hash/ s/^.*$//;/^\s*$/d" $log_dir/check_duplicate.log
	curl --data "profile_id=$profile_id&status=$status_code" "http://$cms:$cms_port/index.php/converter/update-status-content"
	#curl --data "profile_id=$profile_id&status=$status_code" "http://$cms/index.php/converter/unlock-content"
	sleep $sleep_time && continue		
}

#function megre_audio
#input: $temp_path $audio_path
#output: 0 is ok, 1 is no subtitle
function merge_audio {
	raw1_dir=`dirname "$1"`
	newfile_name=`basename "$1"`
	if [ -f $2 ]; then
		echo -e "$(date)  there is extra audio to megre with $1" >> $error_dir/error_trans_process.log
		mkdir -p $raw1_dir/temp/
	echo -e "ffmpeg -i $1 -i $2 -codec:v copy -codec:a aac -b:a 192k -strict experimental -filter_complex "amerge,pan=stereo:c0<c0+c2:c1<c1+c3" $raw1_dir/temp/$newfile_name " >> $error_dir/error_trans_process.log
	ffmpeg -i $1 -i $2 -codec:v copy -codec:a aac -b:a 192k -strict experimental -filter_complex "amerge,pan=stereo:c0<c0+c2:c1<c1+c3" $raw1_dir/temp/$newfile_name 
	
		return 0;
	else
		echo -e "$(date)  No extra audio to megre with $1" >> $error_dir/error_trans_process.log
		return 1;
	fi
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
	merge_audio $temp_path $audio_path
	if [ $? -eq 0 ]; then
				temp_path="$raw_dir/temp/$stand_name.$ext"
			fi
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
			echo 0
		else
			echo -e "$(date)		Error: video raw $raw_path is not a video" >> $error_dir/error_trans_process.log
			echo 1
		fi
	else
		echo -e "$(date)		Error: video raw $raw_path is not existed" >> $error_dir/error_trans_process.log
		echo 1
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
			echo -e "$(date)		$profile_id - $raw_path - $MD5FILE" >> $error_dir/duplicate.log
			echo -e "$(date)		Error: $raw_path is duplicate video, check again,plz" >> $error_dir/error_trans_process.log
			echo -e "					If you still want to transcode this video, you should remove $MD5FILE in $log_dir/check_duplicate.log" >> $error_dir/error_trans_process.log
			echo 1
	else
			echo "$MD5FILE" >> $log_dir/check_duplicate.log
			echo "$MD5FILE $profile_id" >> $log_dir/hash.tmp
			echo 0
	fi
}



#function check_sub
#input: $raw_path $temp_srt $temp_ass
#output: 0 is ok, 1 is no subtitle
function check_sub {
	if [ -z $sub_path ]; then
		sub_path=`echo $1 | sed 's/\..*$/\.srt/'`
	fi
	if [ -f $sub_path ]; then
		file -bi $sub_path |grep -i utf-16 >/dev/null 2>&1
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
#Input: $widthmax $heightmax $temp_ass
function build_vf {
    if [ $compare_ratio -eq 1 ]; then
        vf="scale=$1:trunc'(ow/a/2)'*2"
    else
        vf="scale=trunc'(oh/a/2)'*2:$2"
    fi
    if [ "$3" != "" ]; then
        vf="ass=$3,$vf"
    fi
    echo $vf
}

#Build video option (codec, bitrate, filter, preset)
#Input: $codec $bitrate $vf $preset
function build_video {
    if [ "$4" == "" ]; then
        echo -c:v $1 -b:v $2 -vf $3
    else
        echo -c:v $1 -b:v $2 -vf $3 -vpre $4
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
	mkdir -p "$destination_folder/${raw_name_no_ext}"
	echo "$destination_folder/${raw_name_no_ext}/${raw_name_no_ext}_$2.mp4"
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
		fault_func 1
	fi

}

#Function update_cms
#Update outputs info to cms
#Input: $profile_id $content_id $output_SU
#Output: update_success.log update_fail.log
function update_cms {
	echo "##Start Update CMS##" >> $error_dir/error_trans_process.log 
	local profile_id=$1
    	local content_id=$2
	local file_path=`echo $3 | awk -F '/opt/transcode/disk1/file/' '{print$2}'`
  	local bitrate=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries format=bit_rate $3`
    	local width=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=width $3`
	local height=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=height $3`
	local duration=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries format=duration $3 | cut -d '.' -f1` 
	local output=`curl --data "profile_id=$profile_id&content_id=$content_id&content_type=$content_type&url=$file_path&bitrate=$bitrate&width=$width&height=$height&duration=$duration" "http://$cms:$cms_port/index.php/converter/content-converted" | sed 's/\({\|"\|}\)//g'`
	local result=`echo $output | awk -F',' '{print$1}' | awk -F':' '{print$2}'`
	local content_type=$4
	if [ "$result" != 'true' ]; then
		echo "curl --data \"profile_id=$profile_id&content_id=$content_id&content_type=$content_type&url=$file_path&bitrate=$bitrate&width=$width&height=$height\" \"http://$cms:$cms_port/index.php/converter/content-converted\"" >> $error_dir/update_fail.log
		echo "$(date)		Error: Video $file_path update fail: $output" >> $error_dir/error_trans_process.log
		return 1
	else
		echo  "curl --data \"profile_id=$profile_id&content_id=$content_id&content_type=$content_type&url=$file_path&bitrate=$bitrate&width=$width&height=$height\" \"http://$cms:$cms_port/index.php/converter/content-converted\"" >> $error_dir/update_success.log
		return 0
	fi
	echo "##Done\n##" >> $error_dir/error_trans_process.log
}

#function update status content
#Input:  $content_id 
#status_code:
#    const STATUS_ACTIVE = 1;
#    const STATUS_INACTIVE = 0;
#    const STATUS_TEST = 3;
#    const STATUS_TRANCODED = 4; // DA TRANSCOE
#    const STATUS_TRANCODE_PENDING = 5; // DANG TRANSCOE, Khoa
#    const STATUS_RAW=6; // raw chua transcode
#    const STATUS_RAW_ERROR=7; // raw error
#    const STATUS_UPLOADING=8; // raw error
function update_status {
	local profile_id=$1
	curl --data "profile_id=$profile_id&status=4" "http://$cms:$cms_port/index.php/converter/update-status-content" >> $error_dir/error_trans_process.log
}

#Function: perform transcoding
function transcode {
	for i in "$@"; do 
		case "$i" in
			SU)
				video_SU=$(build_video libx264 2000k $(build_vf 1280 720 $sub))
				audio_SU=$(build_audio libfaac 128k 2 44100 2)
				output_SU=$(output $temp_path $i)
			 ;;
			HD)
				video_HD=$(build_video libx264 1200k $(build_vf 1280 720 $sub))
				audio_HD=$(build_audio libfaac 128k 2 44100 2)
				output_HD=$(output $temp_path $i)
			 ;;
			SD)
				video_SD=$(build_video libx264 800k $(build_vf 848 480 $sub))
				audio_SD=$(build_audio libfaac 64k 2 44100 2)
				output_SD=$(output $temp_path $i)
			 ;;
			MB)
				video_MB=$(build_video libx264 500k $(build_vf 640 360 $sub))
				audio_MB=$(build_audio libfaac 64k 2 44100 2)
				output_MB=$(output $temp_path $i)
			 ;;
			FP)
				video_FP=$(build_video libx264 300k $(build_vf 424 240 $sub))
				audio_FP=$(build_audio libfaac 64k 2 44100 2)
				output_FP=$(output $temp_path $i)
			 ;;	
		esac
	done
	case "$#" in
		1)
			echo "ffmpeg $main_opt $video_FP $audio_FP $output_FP" >> $error_dir/error_trans_process.log
			ffmpeg $main_opt $video_FP $audio_FP $output_FP
		 ;;
		2)
			echo "ffmpeg $main_opt $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP" >> $error_dir/error_trans_process.log
			ffmpeg $main_opt $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP
		 ;;
		3)
			echo "ffmpeg $main_opt $video_SD $audio_SD $output_SD $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP" >> $error_dir/error_trans_process.log
			ffmpeg $main_opt $video_SD $audio_SD $output_SD $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP
		 ;;
		4)
			echo "ffmpeg $main_opt $video_HD $audio_HD $output_HD $video_SD $audio_SD $output_SD $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP" >> $error_dir/error_trans_process.log
			ffmpeg $main_opt $video_HD $audio_HD $output_HD $video_SD $audio_SD $output_SD $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP
		 ;;
		5)
			echo "ffmpeg $main_opt $video_SU $audio_SU $output_SU $video_HD $audio_HD $output_HD $video_SD $audio_SD $output_SD $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP" >> $error_dir/error_trans_process.log
			ffmpeg $main_opt $video_SU $audio_SU $output_SU $video_HD $audio_HD $output_HD $video_SD $audio_SD $output_SD $video_MB $audio_MB $output_MB $video_FP $audio_FP $output_FP
		 ;;
	esac
	if [ $? ne 0 ]; then
#if transcode fail, log && recover raw_path
		echo "$(date)		Error: Transcode process fail with $raw_path" >> $error_dir/error_trans_process.log
		fault_func 2
	fi	
	check_output $output_FP
#Remove raw file
#	rm -rf $temp_path
#	rm -rf $sub_path
	sed -i "/$profile_id/ s/^.*$//;/^\s*$/d" $log_dir/hash.tmp	
}		

######################################################
#MAIN BODY - TRANSCODE PROCESS
######################################################

while [ 1 ]; do
	sleep_time=`awk -vmin=60 -vmax=100 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'`
	
#get & process raw infor
	check_cms $cms $cms_port
	get_link="http://$cms:$cms_port/converter/contents-raw"
	output=`curl -m 5 "$get_link" | sed 's/\({\|"\|}\)//g'`
	echo "$(date)		Info: Get link result: $output" >> $error_dir/error_trans_process.log
	result=`echo $output | awk -F',' '{print$1}' | awk -F':' '{print$2}'`
#	raw_path='/opt/transcode/raw/test.mkv'
	if [ "$result" != 'true' ]; then
		echo "$(date)		Warning: no raw file .....go to bed...zzz...zzz" >> $error_dir/error_trans_process.log
		sleep $sleep_time && continue
	else
		profile_id=`echo $output | awk -F',' '{print$3}' | awk -F':' '{print$3}'`
		content_id=`echo $output | awk -F',' '{print$4}' | awk -F':' '{print$2}'`
		
		cp_id=`echo $output | awk -F',' '{print$5}' | awk -F':' '{print$2}'`
		raw_path=`echo $output | awk -F',' '{print$6}' | awk -F':' '{print$2}'`
		sub_path=`echo $output | awk -F',' '{print$7}' | awk -F':' '{print$2}'`
		content_type=`echo $output | awk -F',' '{print$8}' | awk -F':' '{print$2}'`
		audio_path=`/root/test/example.m4a`
#		check_mount $raw_path
#		if [ $? -eq 1 ]; then
#			sleep $sleep_time && continue
#		fi
	
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
		echo $temp_path >> $error_dir/error_trans_process.log
#		if [[ $(check_raw $temp_path) -eq 0 && $(check_format $temp_path) -eq 0 && $(check_duplicate $temp_path) -eq 0 ]]; then		
                if [[ $(check_raw $temp_path) -eq 0 && $(check_format $temp_path) -eq 0 ]]; then
#Check vs cut folder destination
			if [ `ls $file_dir/$cp_id | grep video-file- | wc -l` -eq 0 ]; then
				mkdir -p $file_dir/$cp_id/video-file-0
			fi
			exist_num=`ls -dt $file_dir/$cp_id/video-file-* | head -n 1 | cut -d '-' -f3`
			destination_folder="$file_dir/$cp_id/video-file-$exist_num"
			file_total=`ls $destination_folder | wc -l`
			
			if [ "$file_total" -ge 1000 ]; then
					next_num=$[exist_num + 1]
					destination_folder=$file_dir/$cp_id/video-file-$next_num
					mkdir -p $destination_folder				
			fi
#/opt/transcode/file/$disk_id/video-file-$number/$stand_name_HD.ssm/$stand_name_HD.ismv
			main_opt="-loglevel warning -i $temp_path -y -map_chapters -1"			
#Check raw quality: revolution of video is base on height of video. 
#So we'll check height of raw video to decide the number of output versions
#For example:
#240p (424x240, 0.10 megapixels)
#360p (640x360, 0.23 megapixels)
#480p (848x480, 0.41 megapixels, "SD" or "NTSC widescreen")
#720p (1280x720, 0.92 megapixels, "HD")
#1080p (1920x1080, 2.07 megapixels, "Full HD")	
			duration_raw=`ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries format=duration $temp_path | cut -d '.' -f1`
			raw_width=$(ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=width $temp_path | head -n 1)
			raw_height=$(ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=height $temp_path | head -n 1)
			raw_ratio=$(echo "scale=2;$raw_width/$raw_height"|bc)
			compare_ratio=$(echo "$raw_ratio > $fix_ratio"|bc)
			if (( 0 <= $raw_height && $raw_height <= 240 )); then
					transcode FP
					update_cms $profile_id $content_id $output_FP $content_type
					update_status $profile_id
			elif (( 241 <= $raw_height && $raw_height <= 360 )); then
					transcode FP MB
					update_cms $profile_id $content_id $output_MB $content_type
					update_cms $profile_id $content_id $output_FP $content_type
					update_status $profile_id
			elif (( 361 <= $raw_height && $raw_height <= 480)); then
					transcode FP MB SD
					update_cms $profile_id $content_id $output_SD $content_type
					update_cms $profile_id $content_id $output_MB $content_type
					update_cms $profile_id $content_id $output_FP $content_type
					update_status $profile_id
			elif (( 481 <= $raw_height && $raw_height <= 720 )); then
					transcode FP MB SD HD
					update_cms $profile_id $content_id $output_HD $content_type
					update_cms $profile_id $content_id $output_SD $content_type
					update_cms $profile_id $content_id $output_MB $content_type
					update_cms $profile_id $content_id $output_FP $content_type
					update_status $profile_id
			else
					transcode FP MB SD HD SU
					update_cms $profile_id $content_id $output_SU $content_type
					update_cms $profile_id $content_id $output_HD $content_type
					update_cms $profile_id $content_id $output_SD $content_type
					update_cms $profile_id $content_id $output_MB $content_type
					update_cms $profile_id $content_id $output_FP $content_type
					update_status $profile_id
			fi	
		else
			fault_func 1
		fi
	fi
done
