#!/bin/bash

##################################
##                              ##
##################################

echo
echo MAIN PID: $$
echo

declare -A chk_host_avail_pids
declare -A host_avails
declare -r tmp_dir="/tmp/tc-conn"

# Reacheble checking procedure by ping
chk_host_avail(){

    if [[ -z $2 ]]; then
        local is_alive=0
    else
        local is_alive=$2
    fi

    while :
    do
        local res="$(fping -r0 $1 2<&1| grep -icE 'alive')"
        if [[ res -ne is_alive ]]; then
            if [[ res -eq 0 ]]; then
                # Host unreacheble after reacheble
                kill -s SIGUSR2 $$
                echo "0" > /tmp/tc-conn/$1
                echo "host $1 is UNreachable now"
            else
                # Host reachable after unreacheble
                kill -s SIGUSR1 $$
                echo "1" > /tmp/tc-conn/$1
                echo "host $1 is reachable now"
            fi
        fi

        is_alive=$res
        sleep 1

    done
}

stop_handler(){
    echo stop_handler function
    kill ${chk_host_avail_pids[@]}
    if [[ ! -z $cur_vwr_pid ]]; then
        kill $cur_vwr_pid
    fi
    rm -rfd $tmp_dir
    exit 0
}

connection_handler(){
    while :
    do
        
    done
}

on_reachable_handler(){
    echo "on_reachable_handler: "

    for filename in $(ls $tmp_dir)
    do
        if [[ -f ${tmp_dir}/${filename} ]] && [[ $(cat ${tmp_dir}/${filename}) -eq "1" ]]; then
            echo "on_reachable_handler: host $filename is reachable now (pid ${chk_host_avail_pids[$filename]})"
            rm -f ${tmp_dir}/${filename}
            host_avails[$filename]=1
            print_host_avails

            if [[ -z $cur_vwr_pid ]]; then
                run-tc $filename &
                cur_vwr_pid=$!
                cur_hst_ip=$filename
            fi
        fi
    done

    wait
}

on_unreachable_handler(){
    echo "on_UNreachable_handler"

    for filename in $(ls $tmp_dir)
    do
        if [[ -f ${tmp_dir}/${filename} ]] && [[ $(cat ${tmp_dir}/${filename}) -eq "0" ]]; then
            echo "on_UNreachable_handler: host $filename is UNreachable now (pid ${chk_host_avail_pids[$filename]})"
            rm -f ${tmp_dir}/${filename}
            host_avails[$filename]=0
            print_host_avails

            if [[ ! -z $cur_vwr_pid ]] && [[ $cur_hst_ip == $filename ]]; then
                kill $cur_vwr_pid
                cur_vwr_pid=""
                cur_hst_ip=""

                # Find available host
                for ip_addr in ${!host_avails[@]}; do
                    if [[ ${host_avails[${key}]} -eq "1" ]]; then
                        run-tc $ip_addr &
                        cur_vwr_pid=$!
                        cur_hst_ip=$ip_addr
                        break
                    fi
                done

            fi
        fi
    done

    wait
}

print_host_avails(){
    # Print array of pids and ip addresses
    echo "Hosts:" > /tmp/tc-conn-hosts
    echo >> /tmp/tc-conn-hosts
    for key in ${!host_avails[@]}; do
        echo ${key}  is_available: ${host_avails[${key}]} >> /tmp/tc-conn-hosts
    done
}

# Declare vars: current viewer PID, current viewer ip address connected to
cur_vwr_pid=""
cur_hst_ip=""

# Create directory in memory /tmp/tc-conn
if [[ -d "$tmp_dir" ]]; then
    # If directory exists - delete files in this directory
    rm -rf ${tmp_dir}/*
else
    mkdir $tmp_dir
fi

# Declare trap handlers
trap 'on_reachable_handler' SIGUSR1	# for reach
trap 'on_unreachable_handler' SIGUSR2	# and unreach adresses
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
done <"/bin/tc-conn.cfg"

# Print array of pids and ip addresses
for key in ${!chk_host_avail_pids[@]}; do
    echo ${key}  pid: ${chk_host_avail_pids[${key}]}
done
echo

wait
