#!/bin/bash

##################################
##  Thin Client Connector 2.0   ##
##################################

echo -e "\n MAIN PID: $$ \n"

declare -A chk_host_avail_pids
declare -A host_avails
declare -r tmp_dir="/tmp/tc-conn"
declare -r cfg_file="/etc/tc-conn.cfg"
#declare -r run_vwr_str="xtightvncviewer -quality 9 -nocursorshape -fullscreen -compresslevel 0 -xrm '*grabKeyboard: true' "
declare -r run_vwr_str="xtightvncviewer -quality 9 -nocursorshape -fullscreen -compresslevel 0 "
declare -r vwr_prt="5904"
declare cur_vwr_pid=""
declare cur_hst_ip=""

# Checking of reachable host by ping procedure
chk_host_avail(){
	local is_alive=0

	while :
	do
		local png_res="$(fping -r0 $1 2<&1| grep -icE 'alive')"
		if [[ png_res -ne is_alive ]]; then
			if [[ png_res -eq 0 ]]; then
				# Host unreacheble after reacheble
				echo "0" > /tmp/tc-conn/$1
				echo "host $1 is UNreachable now"
			else
				# Host reachable after unreacheble
				echo "1" > /tmp/tc-conn/$1
				echo "host $1 is reachable now"
			fi
		fi

		is_alive=$png_res
		sleep 1
	done
}

# Before stop scrips commands (delete /tmp directory, kill sub-processes)
stop_handler(){
	echo stop_handler function
	kill ${chk_host_avail_pids[@]}
	if [[ ! -z $cur_vwr_pid ]]; then
		stop_vwr
	fi
	rm -rfd $tmp_dir
	exit 0
}

# Checking tmp connections files 
chk_tmp_files(){
	for filename in $(ls $tmp_dir)
	do
		# Checking files with "1" letter (reachable addresses that were unreachable before)
		if [[ -f ${tmp_dir}/${filename} ]] && [[ $(cat ${tmp_dir}/${filename}) -eq "1" ]] && [[ host_avails[$filename] -eq 0 ]]; then
			echo "on_reachable_handler: host $filename is reachable now (pid ${chk_host_avail_pids[$filename]})"
			host_avails[$filename]=1
			print_host_avails

			# If no viewer running - run viewer
			if [[ -z $cur_vwr_pid ]]; then
				run_vwr $filename
			fi

		# Checking files with "0" letter (UNreachable addresses that were reachable before)
		elif [[ -f ${tmp_dir}/${filename} ]] && [[ $(cat ${tmp_dir}/${filename}) -eq "0" ]] && [[ host_avails[$filename] -eq 1 ]]; then
			echo "on_UNreachable_handler: host $filename is UNreachable now (pid ${chk_host_avail_pids[$filename]})"
			host_avails[$filename]=0
			print_host_avails

			if [[ ! -z $cur_vwr_pid ]] && [[ $cur_hst_ip == $filename ]]; then
				stop_vwr

				# Find available host
				for ip_addr in ${!host_avails[@]}; do
					if [[ ${host_avails[${ip_addr}]} -eq "1" ]]; then
						run_vwr $filename
						break
					fi
				done
			fi
		fi
	done
}

# Print host availables to /tmp/tc-conn-hosts file 
print_host_avails(){
	# Print array of pids and ip addresses
	echo "Hosts:" > /tmp/tc-conn-hosts
	echo >> /tmp/tc-conn-hosts
	for key in ${!host_avails[@]}; do
		echo ${key}  is_available: ${host_avails[${key}]} >> /tmp/tc-conn-hosts
	done
}

# Checking viewer running state
chk_vwr_pid(){
	# Start client (viewer) if it not launched and viewer's PID is not empty
	if [[ ! -z $cur_vwr_pid ]] && [[ -z $(ps -o pid="" $cur_vwr_pid) ]]; then
		cur_vwr_pid=""
		# Find available not previos host to connect
		for ip_addr in ${!host_avails[@]}; do
			if [[ $ip_addr != $cur_hst_ip ]] && [[ ${host_avails[${ip_addr}]} -eq "1" ]]; then
				run_vwr $filename
				break
			fi
		done
		
		# If no another available host's ip addresses was found try connect to previous
		if [[ -z $cur_vwr_pid ]]; then
			run_vwr $filename
		fi
	fi
}

# Run VNC viewer commands
run_vwr(){
	echo DISPLAY=:0 $run_vwr_str $1::$vwr_prt &
	DISPLAY=:0 $run_vwr_str $1::$vwr_prt &
	cur_vwr_pid=$!
	cur_hst_ip=$1
}

# Stop VNC viewer (kill processe)
stop_vwr(){
	kill $cur_vwr_pid
	cur_vwr_pid=""
	cur_hst_ip=""
}

# Create directory in memory /tmp/tc-conn
if [[ -d "$tmp_dir" ]]; then
	# If directory exists - delete files in this directory
	rm -rf ${tmp_dir}/*
else
	mkdir $tmp_dir
fi

# Declare stop trap handler
trap 'stop_handler' SIGINT SIGTERM	# for interrupt signal

# Reading line-by-line host's ip addresses
# and running checking functions
while read cfg_line
do
	if [[ $cfg_line ]]; then
		chk_host_avail $cfg_line &
		chk_host_avail_pids[$cfg_line]=$!
		host_avails[$cfg_line]=0
	fi
done <$cfg_file

# Print array of pids and ip addresses
for key in ${!chk_host_avail_pids[@]}; do
	echo ${key}  pid: ${chk_host_avail_pids[${key}]}
done
echo

# Main loop (checks tmp files of connections, run and control TC-viewer)
while :
do
	chk_tmp_files
	chk_vwr_pid

	sleep 1
done


































