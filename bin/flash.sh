#!/bin/sh
#

. /lib/upgrade/common.sh
. /bin/boardupgrade.sh

hndmsg() {
	if [ -n "$msg" ]; then
		echo "$msg" >> /dev/kmsg 2>/dev/null
		if [ `pwd` = "/tmp" ]; then
			rm -rf $filename 2>/dev/null
		fi
		exit 1
	fi
}

upgrade_param_check() {
	if [ -z "$1" -o ! -f "$1" ]; then
		klogger "USAGE: $0 input.bin [1:restore defaults, 0:don't] [1:don't reboot, 0:reboot]"
		exit 1
	fi

	flg_ota=`nvram get flag_ota_reboot`
	if [ "$flg_ota" = "1" ]; then
		klogger "flag_ota_reboot is set ?"
		exit 1
	fi

	cur_ver=`cat /usr/share/xiaoqiang/xiaoqiang_version`
	klogger "Begin Ugrading..., current version: $cur_ver"
	sync
	model=`cat /proc/xiaoqiang/model`
	[ "$model" != "R4A" -a "$model" != "R3GV2" ] && echo 3 > /proc/sys/vm/drop_caches
}

upgrade_prepare_dir() {
	absolute_path=`echo "$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"`
	mount -o remount,size=100% /tmp
	rm -rf /tmp/system_upgrade
	mkdir -p /tmp/system_upgrade

	if [ ${absolute_path:0:4} = "/tmp" ]; then
		file_in_tmp=1
		mv $absolute_path /tmp/system_upgrade/
	else
		file_in_tmp=0
		cp $absolute_path /tmp/system_upgrade/
	fi
}

upgrade_done_set_flags() {
	# update nvram setting when upgrading
	if [ "$2" = "1" ]; then
		nvram set restore_defaults=1
		klogger "Restore defaults is set."
	else
		nvram set restore_defaults=2
	fi
	[ "$upkernel" = "true" ] && nvram set flag_ota_reboot=1
	nvram set flag_upgrade_push=1
	nvram commit

	if [ "$3" = "1" ]; then
		klogger "Skip rebooting..."
	else
		klogger "Rebooting..."
		reboot
	fi
}

uploadUpgrade() {
    [ "1" = "`cat /proc/xiaoqiang/ft_mode`" ] && return 0
    [ "YES" != "`uci -q get xiaoqiang.common.INITTED`" ] && return 0

    serv_addr=`/sbin/uci get /etc/config/miwifi.server.API`
    lanip=`uci -q get network.lan.ipaddr | awk -F"." '{print $1,$2}' OFS="."`
    if [ "$serv_addr" != "" ];then
        res=`nslookup $serv_addr | grep "$lanip"`
        [ "$res" != "" ] && return
		logger stat_points_none upgrade=start
		[ -f /usr/sbin/StatPoints ] && /usr/sbin/StatPoints
	fi
}


#check pid exist
pid_file="/tmp/pid_xxxx"
if [ -f $pid_file ]; then
	exist_pid=`cat $pid_file`
	if [ -n $exist_pid ]; then
		kill -0 $exist_pid 2>/dev/null
		if [ $? -eq 0 ]; then
			klogger "Upgrading, exit... $?"
			exit 1
		else
			echo $$ > $pid_file
		fi
	else
		echo $$ > $pid_file
	fi
else
	echo $$ > $pid_file
fi

upgrade_param_check $1

# image verification...
klogger -n "Verify Image: $1..."
mkxqimage -v "$1"
if [ "$?" = "0" ]; then
	klogger "Checksum O.K."
	uploadUpgrade
else
	msg="Check Failed!!!"
	hndmsg
fi

board_start_upgrade_led

netmode="`uci -q get xiaoqiang.common.NETMODE`"
if [ "$netmode" = "whc_cap" -o "$netmode" = "whc_re" ]; then
	sleep 10
fi

# stop services
board_prepare_upgrade

# prepare to extract file
filename=`basename $1`
upgrade_prepare_dir $1
cd /tmp/system_upgrade

# start board-specific upgrading...
klogger "Begin Upgrading and Rebooting..."
board_system_upgrade $filename $2 $3

# some board may reset after system upgrade and not reach here
# clean up
cd /
upkernel=true
if [ -d /tmp/system_upgrade/ ];then
    cap=700
    curcap=`du -sk /tmp/system_upgrade/|awk '{print $1}'`
    if [[ 0"$curcap" -lt "$cap" ]] ; then
	    upkernel=false
    fi
fi    

rm -rf /tmp/system_upgrade

upgrade_done_set_flags $1 $2 $3
