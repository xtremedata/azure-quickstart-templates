#!/bin/bash

#
# Usage:  $0 [-v] <headip> <clustername> <number-of-nodes> <this-node-index>
#
set -e

logger -t azure-dbx-san-start "started, args: $*"
echo "dbx-san-start Started: $*. `date`"

[ $1 = '-v' ] && shift || quiet='-q'

headip=$1
clustername=$2
myip="$(ip -4 address show eth0 | sed -rn 's/^[[:space:]]*inet ([[:digit:].]+)[/[:space:]].*$/\1/p')"
login_user="azure-user"

data_nodes=$3
[ "$data_nodes" -ge 1 ] || { echo "bad number of nodes: $data_nodes" && exit 1; }
: $((data_nodes--))

echo $myip `hostname` >> /etc/hosts
umount /mnt/resource || true

rm -f ~xdcrm/tmp/my_config.out
/etc/init.d/dbx_checkin stop || true

su - xdcrm -c "xdcluster setup static --head=$headip --cluster='$clustername' --devices=udev +y +force_config && xdcluster checkin"

echo dbx-san-start config Done. `date`
logger -t azure-dbx-san-start "config Done: success"

[ "$4" -ne 0 ] && exit 0


# copy $login_user's password to dbxdba
adm_pwd="$(getent shadow $login_user | awk -F: '{print $2}')"
[ -n "$adm_pwd" ] && echo -e "dbxdba:$adm_pwd" | chpasswd -e


###### start dbx on head ######

function Exit {
    msg="$1"  # empty = SUCCESS
    echo "dbx-san-start startup Done: ${msg:-SUCCESS} `date`"
    logger -t azure-dbx-san-start "startup Done: ${msg:-SUCCESS}"
    [ -z "$msg" ]; exit
}

echo "*** waiting for $data_nodes nodes *** `date`"
declare -i nn=240
while [ "$(/opt/xdcluster/bin/getnodes.sh | wc -l)" -ne $data_nodes ]; do
  sleep 5
  [ $((--nn)) -gt 0 ] || Exit "TIMEOUT waiting for nodes: have $(/opt/xdcluster/bin/getnodes.sh | wc -l), want $data_nodes"
done
sleep 10 # temp

su - xdcrm -c "xdcluster scan" || Exit "ERROR: xdc scan"
su - xdcrm -c "xdcluster role -a AD && xdcluster role -e AH" || Exit "ERROR: xdc role"
mynodes="$(su - xdcrm -c "xdcluster list +use_work" | grep -w Active | wc -l)"
[ "$mynodes" -eq $((data_nodes+1)) ] || Exit "ERROR: xdc nodes mismatch, have $mynodes expected $((data_nodes+1))"
su - xdcrm -c "xdcluster init storage +hdata -resil +y && xdcluster bootable on" || Exit "ERROR: xdc init"
su - xdcrm -c "xdcluster start" || Exit "ERROR: xdc start"

Exit

# vim: set tabstop=4 sw=4 et:
