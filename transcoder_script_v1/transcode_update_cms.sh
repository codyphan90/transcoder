#!/bin/bash

### Script to add video version to CMS

tvod_cms=10.84.79.203
tvod_api=transcode_server_api/insertNewVideoVersion
##tvod2
tvod2_cms=10.84.85.137
tvod2_api=transcode/add-file-transcoded
###alotv
alotv_cms=10.84.73.37
alotv_api=transcode_server_api/insertNewVideoVersion
malotv_cms=10.84.73.51
malotv_api=data/insertTranscodedProfile
error_log=/opt/transcode/logs/error/error_update_cms.log
#CDN
cdn=api.cdn.tvod.com.vn
api_tvod=transcode_server_api/insertNewVideoVersion
api=createContent
origincp=103.31.126.16

port_cdn=80
port_tvod=80
port_origin=8089
#secretkey=aslk02938
### function insert video version to TVOD
function insert_cdn {
    local insert_name=$1
    local insert_dir=$2
    local insert_type=$3
    local insert_duration=$4
    local insert_resolution=$5
	secretkey=aslk02938
	cpname=TVoD
	plantext=`echo $name$cpname$secretkey`
	token=`echo -n "$plantext"|md5sum|cut -d ' ' -f1`
	if [ $insert_type -eq 6 ]; then
		local nameext=$name.3gp
	else
		local nameext=$name.m3u8
	fi
	link="http://$origincp:$port_origin/movies/Video/$base_dir/$name.ssm/$nameext"
#	link="http://$origincp:$port_origin/movies/Video/$base_dir/$name.ssm/$name.m3u8"
	local query_cdn="http://$cdn:$port_cdn/$api?contentName=$name&cpName=$cpname&link=$link&description=$name&contentType=VOD&secretKey=$secretkey&token=$token"
	echo "curl \"$query_cdn\""
  	#output_cdn=$(curl -m 5 "$query_cdn" 2>/dev/null)
	output_cdn=`curl "$query_cdn" 2>/dev/null`
	echo "$output_cdn"
	if [ $? -ne 0 ]; then
        echo -e "$(date) \t Insert CDN failed: Connection Error"
        echo "curl \"$query_cdn\"" >> $error_log
    else
        result=$(echo $output_cdn|cut -d ':' -f2|cut -d '}' -f1)
        if [ "$result" == "true" ]; then
            echo -e "$(date) \t Insert CDN success."
        else
            echo -e "$(date) \t Insert CDN failed: $output"
            echo "curl \"$query_cdn\"" >> $error_log
        fi
    fi
	result_cdn=`echo $output_cdn|cut -d ',' -f4 | cut -d " " -f3`
	cdn_id=`echo $output_cdn|cut -d ',' -f5 | cut -d ' ' -f3`
#	cdn_id=`echo $output_cdn| tail -2 | head -1 | cut -d: -f2`
	echo $result_cdn
	echo "$cdn_id"
	if [[ $result_cdn == true  ]]; then
		echo -e "\tcurl successful"
		insert_tvod $name $base_dir $type $duration $resolution
		insert_tvod2 $name $base_dir $type $duration $resolution
	elif [[ $result == false ]]; then
        	echo -e "\tcurl unsuccessful"
        	echo -e "$1\n$output\n" >> error.log
	else
        	echo -e "\tSomething wrong\n"
	fi	
	}

### function insert video version to TVOD
function insert_tvod {
    local insert_name=$1
    local insert_dir=$2
    local insert_type=$3
    local insert_duration=$4
    local insert_resolution=$5
    local query="http://$tvod_cms/?q=$tvod_api&id=$insert_name&basedir=$insert_dir&title=$insert_name&type=$insert_type&content_id=$cdn_id&picture=picture&duration=$insert_duration&resolution=$insert_resolution"
    echo  \"$query\"
    output=$(curl -m 5 "$query" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "$(date) \t Insert TVOD failed: Connection Error"
        echo "curl \"$query\"" >> $error_log
    else
        result=$(echo $output|cut -d ':' -f2|cut -d '}' -f1)
        if [ "$result" == "true" ]; then
            echo -e "$(date) \t Insert TVOD success."
        else
            echo -e "$(date) \t Insert TVOD failed: $output"
            echo "curl \"$query\"" >> $error_log
        fi
    fi
}
### function insert video version to TVOD2
function insert_tvod2 {
    local insert_name=$1
    local insert_dir=$2
    local insert_type=$3
    local insert_duration=$4
    local insert_resolution=$5
	local query="http://$tvod2_cms/backend/web/index.php?r=$tvod2_api&id=$insert_name&basedir=$insert_dir&title=$insert_name&type=$insert_type&content_id=$cdn_id&picture=$picture&duration=$insert_duration&resolution=$insert_resolution"
	echo  \"$query\"
    output=$(curl -m 5 "$query" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "$(date) \t Insert TVOD2 failed: Connection Error"
        echo "curl \"$query\"" >> $error_log
    else
        result=$(echo $output|cut -d ':' -f2|cut -d '}' -f1)
        if [ "$result" == "true" ]; then
            echo -e "$(date) \t Insert TVOD2 success."
        else
            echo -e "$(date) \t Insert TVOD2 failed: $output"
            echo "curl \"$query\"" >> $error_log
        fi
    fi
}

### function insert video version to ALOTV
function insert_alotv {
    local insert_name=$1
    local insert_dir=$2
    local insert_type=$3
    local insert_duration=$4
    local insert_resolution=$5
    local query="http://$alotv_cms/?q=$alotv_api&id=$insert_name&basedir=$insert_dir&title=$insert_name&type=$insert_type&picture=picture&duration=$insert_duration&resolution=$insert_resolution"
    echo "curl \"$query\""
    output=$(curl -m 5 "$query" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "$(date) \t Insert ALOTV failed: Connection Error"
        echo "curl \"$query\"" >> $error_log
    else
        result=$(echo $output|cut -d ':' -f2|cut -d '}' -f1)
        if [ "$result" == "true" ]; then
            echo -e "$(date) \t Insert ALOTV success."
        else
            echo -e "$(date) \t Insert ALOTV failed: $output"
            echo "curl \"$query\"" >> $error_log
        fi
    fi
}
### function insert video version to MALOTV
function insert_malotv {
    local insert_id=$1
    local insert_name=$2
    local insert_dir=$3
    local insert_type=$4
    local insert_duration=$5
    local insert_width=$6
    local insert_height=$7
    local query="http://$malotv_cms/$malotv_api?profile_id=$insert_id&id=$insert_name&basedir=$insert_dir&title=$insert_name&type=$insert_type&duration=$insert_duration&width=$insert_width&height=$insert_height"
    echo "curl \"$query\""
    output=$(curl -m 5 "$query" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "$(date) \t Insert MALOTV failed: Connection Error"
        echo "curl \"$query\"" >> $error_log
    else
        result=$(echo $output|cut -d ':' -f3|cut -d '}' -f1)
        if [ "$result" == "true" ]; then
            echo -e "$(date) \t Insert MALOTV success."
        else
            echo -e "$(date) \t Insert MALOTV failed: $output"
            echo "curl \"$query\"" >> $error_log
        fi
    fi
}

echo -e "===== START ====="
if [ $# != 3 ]; then echo -e "\tUSAGE: $0 <full/path/to/file/data> <video_id> <cms1,cms2,cms3>" && exit 1; fi

file_path=$3
video_id=$2
list_cms=$1
#echo -e "file_path = $file_path"
#echo -e "list_cms = $list_cms"
#echo -e "video_id = $video_id"

if [ ! -f $file_path ]; then echo -e "\tFile doesn't exist." && exit 2; fi

duration=$(ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries format=duration $file_path|cut -d '.' -f1)
        #echo -e "\tduration= $duration"
if [ -z "$duration" ]; then echo -e "\tIt isn't media file." && exit 3; fi

width=$(ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=width $file_path)
        #echo -e "\twidth = $width"
height=$(ffprobe -loglevel quiet -print_format default=nokey=1:noprint_wrappers=1 -show_entries stream=height $file_path)
        #echo -e "\theight = $height"
if [ -z "$width" ]; then echo -e "\tIt isn't video file." && exit 4; fi
resolution=${width}x${height}
        #echo -e "\tresolution = $resolution"

#prefix="/opt/transcode/file"
diskID="disk6"
#check_prefix=$(echo $file_path|grep $prefix/$diskID|wc -l)
#check_prefix=$(echo $file_path|grep $prefix|wc -l)
#if [ $check_prefix == 0 ]; then echo -e "\tWrong prefix." && exit 5; fi

file_name=$(basename "$file_path")
        #echo -e "\tfile_name = $file_name"
extension="${file_name##*.}"
        #echo -e "\textension = $extension"
name="${file_name%.*}"
        #echo -e "\tname = $name"
#base_dir=$(echo $file_path|cut -d '/' -f5,6)
base_dir=$(dirname "$file_path" | awk -F'/' '{print$(NF-2),$(NF-1)}' | sed 's# #\/#')
        #echo -e "\tbase_dir = $base_dir"

video_type=$(echo $name|cut -d '_' -f2)
        #echo -e "\tvideo_type = $video_type"
case $video_type in
    "SD") type="1" ;;
    "HD") type="2" ;;
    "MB") type="3" ;;
    "AD") type="4" ;;
    "SU") type="5" ;;
    "FP") type="6" ;;
    *) echo -e "\tUnknown version." && exit 6 ;;
esac

if ! [[ $video_id =~ "^[0-9]+$" ]]; then echo -e "\tVideo ID must be integer." && exit 7; fi

while [ "$list_cms" ]; do
    cms=$(echo $list_cms|cut -d ',' -f1)
        #echo -e "\tcms=$cms"
    case $cms in
	"cdn") insert_cdn $name $base_dir $type $duration $resolution ;;
        "tvod") insert_tvod $name $base_dir $type $duration $resolution ;;
        "alotv") insert_alotv $name $base_dir $type $duration $resolution ;;
        "malotv") insert_malotv $video_id $name $base_dir $type $duration $width $height ;;
        "all")
	    insert_cdn $name $base_dir $type $duration $resolution
#            insert_tvod $name $base_dir $type $duration $resolution
            insert_alotv $name $base_dir $type $duration $resolution
            insert_malotv $video_id $name $base_dir $type $duration $width $height;;
        *) echo -e "$(date) \t\t Unknown CMS $cms" ;;
    esac

    list_cms=$(echo $list_cms|sed "s/$cms//")
    if [ "${list_cms:0:1}" == "," ]; then
       list_cms=$(echo $list_cms|sed "s/,//")
    fi
        #echo -e "\tlist_cms = $list_cms"
done

echo -e "===== DONE ====="
