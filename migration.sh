#!/usr/bin/env bash

## MAKE SURE THAT YOUR CONFIGS HAVE ADMIN PRIVILEGES!!!
#colors
red='\033[1;31m'
grn='\033[1;32m'
yel='\033[1;33m'
nc='\033[0m'
yel_bg='\033[1;96m'

grn_ok="[-${grn} OK ${nc}-]"
grn_done="[-${grn} DONE ${nc}-]"
red_fail="[-${red} FAIL ${nc}-]"
yel_warn="[-${yel} WARN ${nc}-]"
yel_jail="${yel_bg}##${nc}"

#### FUNCTION DEF ##################################
function helper() {
  echo -e "############################## USAGE #################################"
  echo -e "${0} <ORIG CONF FILE> <DEST CONF FILE> <CINDER_TYPE> <CINDER_POOL_DESTINATION> <VM_NAME>"
  echo -e "If one is missing program will fail"
  echo -e "There has to be admin privileges for the accounts in configs!!!"
  echo -e "$yel_warn - Names of networks and subnets HAS to be exactly the same on each cluster otherwise the creation will fail or partly fail!!! - $yel_warn"
  echo -e "######################################################################"
}

function sleeper() {
  time=$1
  for i in $(seq 1 $time)
  do
    if [ $i -eq $time ];
    then
      echo -ne "# $grn_ok\n"
    else
      echo -n "#"
      sleep 1
    fi
  done
}

function dest_cluster() {
  source $DEST_OPENSTACK
  DEST_OPENSTACK_URL=$OS_AUTH_URL
  [ -z "$DEST_OPENSTACK_URL" ] && echo -e "!! PLEASE PROVIDE DEST CONFIG | VARIABLE IS EMPTY : $DEST_OPENSTACK_URL - $red_fail" && exit 1
  echo -e "I'm at $OS_AUTH_URL  -  $grn_ok"
}

function orig_cluster() {
  source $ORIG_OPENSTACK
  ORIG_OPENSTACK_URL=$OS_AUTH_URL
  [ -z "$ORIG_OPENSTACK_URL" ] && echo -e "!! PLEASE PROVIDE ORIG CONFIG | VARIABLE IS EMPTY: $ORIG_OPENSTACK_URL - $red_fail"&& exit 1
  echo -e "I'm at $OS_AUTH_URL  -  $grn_ok"
}

function create_output_script() {
  echo "For instance creating, you should use 'bash $INSTANCE-create.sh'"
  # create bash script to create instance
  [ ! -f ./create-template.sh ] && echo "Template file is missing !!! Please provide template file." && exit 1
  cp ./create-template.sh $INSTANCE-create.sh
  # fill create file
  echo "# Create VM with mined parameters" >> $INSTANCE-create.sh
  echo "source $DEST_OPENSTACK" >> $INSTANCE-create.sh

  echo "$openstack_cmd server create --port ${PORT_IDS[0]} --volume ${NEW_VOLUME_IDS[@]: -1} --availability-zone nova --flavor $NEW_INSTANCE_FLAVOR $INSTANCE" >> $INSTANCE-create.sh
  echo "sleep 1" >> $INSTANCE-create.sh
  # check if instance is already up!
  echo "test=\$($openstack_cmd server list --sort-column Status |grep $INSTANCE |awk '{print \$6}')" >> $INSTANCE-create.sh
  echo "until [ \"\$test\" = \"ACTIVE\" ]; do echo \"\$test\"; test=\$($openstack_cmd server list --sort-column Status |grep $INSTANCE |awk '{print \$6}'); sleep 1;done" >> $INSTANCE-create.sh

  for nvol in ${NEW_VOLUME_IDS[@]}
  do
    if [ "$nvol" = "${NEW_VOLUME_IDS[@]: -1}" ]
    then
      # skip the last one cause that is bootable one and it's been already taken care of
      continue
    fi
    echo "$openstack_cmd server add volume $INSTANCE $nvol" >> $INSTANCE-create.sh
  done

  for port_id in ${PORT_IDS[@]}
  do
    if [ "$port_id" = "${PORT_IDS[0]}" ]
    then
      continue
    fi
    echo "$openstack_cmd server add port $INSTANCE $port_id" >> $INSTANCE-create.sh
  done
  echo "sleep 1" >> $INSTANCE-create.sh
  for prop in $properties
  do
    echo "$openstack_cmd server set --property $prop $INSTANCE" >> $INSTANCE-create.sh
  done
  echo -e "$grn_ok  -  script for instance createion created: $PWD/$INSTANCE-create.sh"
  echo -e "$grn_ok  -  DO NOT FORGET MOVE VOLUMES by volume-migration.sh in CINDER-VOLUME-MIGRATION pod"
  echo -e "$grn_ok  -  DO NOT FORGET ALSO FIX AZ AND FLAVOR"
  for nvol in ${NEW_VOLUME_IDS[@]}
  do
    echo "You should run:"
    echo "./volume-migration-rbd.sh $nvol $CINDER_TYPE $CINDER_POOL"
  done
  echo "Waiting for 10 seconds before enabling console for another migration again."
  sleeper 5
}

###################################################

####### input variables #############################
ORIG_OPENSTACK=$1
DEST_OPENSTACK=$2
INSTANCE=$5
# NET_NAME=$5
# SUBNET_NAME=$6
CINDER_POOL=$4
#ssd-2000iops
CINDER_TYPE=$3
openstack_cmd=$(which openstack)
cinder_cmd=$(which cinder)
grepcidr_cmd=$(which grepcidr)
###################################################

##### sanity checks ###############################
[ -z "$ORIG_OPENSTACK" ] && helper && exit 1
[ -z "$DEST_OPENSTACK" ] && helper && exit 1
[ -z "$INSTANCE" ] && helper && exit 1
[ -z "$CINDER_POOL" ] && helper && exit 1
[ -z "$CINDER_TYPE" ] && helper && exit 1
[ -z "$openstack_cmd" ] && echo -e "Missing openstack binary, install python tool for OS-cli - $red_fail" && exit 1
[ -z "$cinder_cmd" ] && echo -e "Missing cinder binary, install python tool for OS-cli - $red_fail" && exit 1
[ -z "$grepcidr_cmd" ] && echo -e "Missing grepcidr binary, instalation depends on your OS! (homebrew/package-manager) - $red_fail" && exit 1
####################################################


#### MAIN ##########################################
orig_cluster
echo "##############################"
echo "   Instance mining"


declare -a OLD_VOLUME_IDS=()
declare -a INSTANCE_IPS=()

##### Input parameters #####
METADATA=$($openstack_cmd server show $INSTANCE |grep properties |awk -F'|' '{print $3}')
#changed to be a list of IPs
# INSTANCE_IP=$(openstack port list --long --server $INSTANCE -c "Fixed IP Addresses" -f yaml |grep ip_address | awk -F':' '{print $2}' |sed 's/^ //g')
INSTANCE_IPS=($($openstack_cmd port list --long --server $INSTANCE -c "Fixed IP Addresses" -f yaml |grep ip_address | awk -F':' '{print $2}' |sed 's/^ //g'))

# INSTANCE_NETWORKS=($($openstack_cmd server show $INSTANCE |grep addresses | awk -F'|' '{print $3}'|awk -F';' '{print $1" "$2}' |awk -F',' '{print $1}'))
# this is cause of the public IP

# INSTANCE_NETWORKS=($($openstack_cmd server show $INSTANCE |grep addresses | awk -F'|' '{print $3}'| sed 's/,.*;//g'))
INSTANCE_NETWORKS=($($openstack_cmd server show $INSTANCE |grep addresses | awk -F'|' '{print $3}'| sed 's/,.*;//g' | sed 's/;//g'))
# OLD_VOLUME_IDS=($($openstack_cmd volume list --sort-column Attached | grep "$INSTANCE" | awk '{print $2}')) # should be bootable last ID but it is not for some reason
# new order of the list, bootable is last!!
OLD_VOLUME_IDS=($($openstack_cmd volume list --long --sort-column Bootable |grep -w "Attached to $INSTANCE" | awk '{print $2}')) #last ID in this order is root image!!
OLD_INSTANCE_FLAVOR=$($openstack_cmd server show $INSTANCE | grep flavor | awk '{print $4}')

case $OLD_INSTANCE_FLAVOR in
    amphora_flavor | amphora_flavor )
        NEW_INSTANCE_FLAVOR="c2r2" ;;
    m1.large )
        NEW_INSTANCE_FLAVOR="m1.large" ;;
    m1.medium )
        NEW_INSTANCE_FLAVOR="m1.medium" ;;
    m1.small )
        NEW_INSTANCE_FLAVOR="m1.small" ;;
    m1.tiny )
        NEW_INSTANCE_FLAVOR="m1.tiny" ;;
    nothing )
        NEW_INSTANCE_FLAVOR="c32m32" ;;
    *)
        NEW_INSTANCE_FLAVOR=$OLD_INSTANCE_FLAVOR;;
esac

# modify metadata to be usable in for cyckle (no other way to add them)
#detect shell:
current_shell=$(lsof -p $$ | awk '(NR==2) {print $1}')
# modify the string with metadata properties to array so we can cycle trought them
declare -a properties=()
case  "$current_shell" in
  zsh)
    IFS=',' read -r -A properties <<< $METADATA
    ;;
  bash)
    IFS=',' read -r -a properties <<< $METADATA
    ;;
  *)
    echo -ne "Well sorry for that but for this shell: $current_shell there is no modification, contact script maintainer to add this feature - $red_fail"
    exit 1
    ;;
esac
# check if the array has some values, does not have to have any!
if [ ${#properties[@]} -eq 0 ];
then
  read -p "Metadata properties are empty, check if there are any. To continue hit enter, to exit Ctrl+C"
fi


# read -p "WARN - Check if networks and subnets have exactly same name on each of clusters. Otherwise it will not work WARN.  Continue with any key."
echo -e "   Instance mining  -  $grn_done"
sleep 1
echo -e "------------------------------"
echo -e "IP: ${INSTANCE_IPS[@]}"
echo -e "NETWORKS: ${INSTANCE_NETWORKS[@]}"
echo -e "VOLUME_ID: ${OLD_VOLUME_IDS[@]}"
echo -e "INST_FLAVOR: $OLD_INSTANCE_FLAVOR"
echo -e "##############################"

echo -e "##############################"
echo -e "   Migrating part"
# switch to orig cloud, mining info about volumes + manage volumes
orig_cluster
declare -a NEW_VOLUME_IDS=()
declare -a PORT_IDS=()
### 1. get the id of volumes (already did) = OLD_VOLUME_IDS
echo -e "Volumes to migration on $OS_AUTH_URL: \n ${OLD_VOLUME_IDS[@]}"
### 2. check if the instance is running
server_status=$($openstack_cmd server show $INSTANCE | grep status | awk '{print $4}')
case "$server_status" in
  SHUTOFF)
    # check if instance is running on destination
    echo -e " - $yel_jail Instance is not running - not a bad thing  -  $yel_warn"
    echo -e " - $yel_jail Checking if instance is running in destination cloud"
    dest_cluster
    server_status_dest=$($openstack_cmd server show $INSTANCE | grep status | awk '{print $4}')
    if [ "$server_status_dest" = "ACTIVE" ];
    then
      echo -e " - $yel_jail Instance is running on destination cloud!  -  $grn_ok"
      echo "##############################"
      exit 0
    else
      echo -e " - $yel_jail Instance $INSTANCE is not running on either of clusters"
      echo -e " - $yel_jail Checking destination managed volumes"
      vol_ex_dest=$($cinder_cmd list |grep $INSTANCE |awk -F'|' '{print $2}' | sed 's/^ //g')
      if [ -z $vol_ex_dest ];
      then
        echo -e " - $yel_jail Volumes haven't been migrated to destination cluster, means the instance is shutoff or something is wrong  -  $yel_warn"
        echo -e " - $yel_jail Will try now to migrate the volumes to dest cluster - fingers crossed."
        orig_cluster
        # Notify about next steps
        echo -e " - $yel_jail detach volumes"
        for VOL in ${OLD_VOLUME_IDS[@]}
        do
          echo "Starting with detaching!"
          #$cinder_cmd reset-state --state available $VOL 2> /dev/null
          echo -e "$VOL state changed  -  $grn_ok"
          #$cinder_cmd reset-state --attach-status detached $VOL 2> /dev/null
          echo -e "$VOL attach-status changed  -  $grn_ok"
          NEW_VOLUME_IDS+=($VOL)
        done
        echo -e " - $yel_jail Manage volumes on dest cloud  -  $grn_done"
        echo -e "   Migrationg part  -  $grn_done"
        ### 6. you can move on! it is done
        echo -e "------------------------------"
        echo -e "These volumes were detached on orig side:"
        echo -e ${OLD_VOLUME_IDS[@]}
        echo -e "DO NOT FORGET TO MANAGE THEM ON DEST CLOUD :"
        echo -e ${NEW_VOLUME_IDS[@]}
        echo -e "Root volume is:"
        echo -e ${NEW_VOLUME_IDS[@]: -1}
        echo -e "##############################"
        # read -p "Press enter to continue"
        echo -e "$grn_ok"
        echo -e "NETWORKS: ${INSTANCE_NETWORKS[@]}"
        # creates ports for all ips and networks of the instance + loads new port ids to list
        for network in ${INSTANCE_NETWORKS[@]}
        do
          for ip in ${INSTANCE_IPS[@]}
          do
            source $ORIG_OPENSTACK
            ORIG_OPENSTACK_URL=$OS_AUTH_URL
            network_name=$(echo $network | awk -F'=' '{print $1}')
            network_id=$($openstack_cmd network show $network_name |grep -w id |awk -F'|' '{print $3}'|sed 's/ //g')
            subnet_name=$($openstack_cmd subnet list |grep $network_id |awk -F'|' '{print $3}'|sed 's/ //g')
            sub_cidr=$($openstack_cmd subnet list |grep "$subnet_name" |awk -F'|' '{print $5}'|sed 's/ //g')
            if [ $($grepcidr_cmd "$sub_cidr" <(echo "$ip") > /dev/null && echo $? || echo $?) -eq 0 ];
            then
              subnet_id=$($openstack_cmd subnet show $subnet_name|grep -w id |awk -F'|' '{print $3}' |sed 's/ //g')
              mac=$($openstack_cmd port list --long --server $INSTANCE |grep $subnet_id |grep "$ip" |awk -F'|' '{print $4}' |sed 's/ //g')
              source $DEST_OPENSTACK
              DEST_OPENSTACK_URL=$OS_AUTH_URL
              mac_in_use=$($openstack_cmd port list |grep $mac | awk -F'|' '{print $2}')
              if [ -z "$mac_in_use" ];
              then
              # variable is empty = we can use this mac
                $openstack_cmd port create --network $network_name --fixed-ip subnet=$subnet_name,ip-address=$ip --mac-address $mac $INSTANCE
                sleep 1
                PORT_IDS+=($($openstack_cmd port list --mac-address $mac -c ID -f value))
                echo -e "PORT_IDS: ${PORT_IDS[@]}"
              else
              # end the program probably some leftovers from previous migrations
                echo -e " Mac address $mac with ip: $ip already in use, please fix. Port not created!  -  $red_fail"
                PORT_ID=$($openstack_cmd port list --mac-address $INSTANCE_MAC -c ID -f value)
                # disabled exit cause it will ruin the whole script
                # exit 1
              fi
            fi
          done
        done
        echo -e "Instance name is:"
        echo -e $INSTANCE
        echo -e "Port IDs are:"
        echo -e ${PORT_IDS[@]}
        echo -e "Root volume is:"
        echo -e ${NEW_VOLUME_IDS[0]}
        source $DEST_OPENSTACK

        create_output_script
        #jumps at the end

        #check if mac is in use
        # creates ports for all ips and networks of the instance + loads new port ids to list
        for network in ${INSTANCE_NETWORKS[@]}
        do
          for ip in ${INSTANCE_IPS[@]}
          do
            source $ORIG_OPENSTACK
            ORIG_OPENSTACK_URL=$OS_AUTH_URL
            network_name=$(echo $network | awk -F'=' '{print $1}')
            network_id=$($openstack_cmd network show $network_name |grep -w id |awk -F'|' '{print $3}'|sed 's/ //g')
            subnet_name=$($openstack_cmd subnet list |grep $network_id |awk -F'|' '{print $3}'|sed 's/ //g')
            sub_cidr=$($openstack_cmd subnet list |grep "$subnet_name" |awk -F'|' '{print $5}'|sed 's/ //g')
            if [ $($grepcidr_cmd "$sub_cidr" <(echo "$ip") > /dev/null && echo $? || echo $?) -eq 0 ];
            then
              subnet_id=$($openstack_cmd subnet show $subnet_name|grep -w id |awk -F'|' '{print $3}' |sed 's/ //g')
              mac=$($openstack_cmd port list --long --server $INSTANCE |grep $subnet_id |grep "$ip" |awk -F'|' '{print $4}' |sed 's/ //g')
              source $DEST_OPENSTACK
              DEST_OPENSTACK_URL=$OS_AUTH_URL
              mac_in_use=$($openstack_cmd port list |grep $mac | awk -F'|' '{print $2}')
              if [ -z "$mac_in_use" ];
              then
              # variable is empty = we can use this mac
                $openstack_cmd port create --network $network_name --fixed-ip subnet=$subnet_name,ip-address=$ip --mac-address $mac $INSTANCE
                sleep 1
                PORT_IDS+=($($openstack_cmd port list --mac-address $mac -c ID -f value))
                echo -e "PORT_IDS: ${PORT_IDS[@]}"
              else
                # mac in use but server is not runing !!
                echo -e " - $yel_jail Mac address $mac already in use but the server is not created!  -  $grn_ok"
                PORT_ID=$($openstack_cmd port list --mac-address $INSTANCE_MAC -c ID -f value)
              fi
            fi
          done
        done
        echo -e " - $yel_jail Please run or create the instance in destination cloud with created script"

        create_output_script
        #jumps at the end
      fi
    fi
    ;;

  ACTIVE)
    # Instance is running, great
    # Lets stop it and unmanage the volumes
    # Notify admin that we have found the instance
    orig_cluster
    echo -e " - $yel_jail Server is active  -  $grn_ok"
    # Notify about next steps
    echo -e " - $yel_jail Instance shutdown"
    read -p "Will stop the $INSTANCE instance now! Type Y/N [y/n]" decision
    if [ "$decision" = "y" ] || [ "$decision" = "Y" ];
    then
      echo "Stopping now..."
      $openstack_cmd server stop $INSTANCE
      sleeper 10
      echo -e " - $yel_jail Instance $INSTANCE stopped, moving on with next procedure"
      echo -e " - $yel_jail Instance shutdown  -  $grn_done"
      echo -e " - $yel_jail Setup and unmanage volumes"
      for VOL in ${OLD_VOLUME_IDS[@]}
      do
        echo "Starting with detaching process!"
        $cinder_cmd reset-state --state available $VOL 2> /dev/null
        echo -e "$VOL state changed  -  $grn_ok"
        $cinder_cmd reset-state --attach-status detached $VOL 2> /dev/null
        echo -e "$VOL attach-status changed  -  $grn_ok"
        NEW_VOLUME_IDS+=($VOL)
      done
      echo -e "   Migrating part  -  $grn_done"
      ### 6. you can move on! it is done
      echo -e "------------------------------"
      echo -e "These volumes were unmanaged on orig side:"
      echo -e ${OLD_VOLUME_IDS[@]}
      echo -e "IDs of manage volumes on dest side:"
      echo -e ${NEW_VOLUME_IDS[@]}
      echo -e "Root volume is:"
      echo -e ${NEW_VOLUME_IDS[0]}
      echo -e "##############################"
      read -p "Press enter to continue"
      echo -e "$grn_ok"
      echo -e "NETWORKS: ${INSTANCE_NETWORKS[@]}"

# creates ports for all ips and networks of the instance + loads new port ids to list
      for network in ${INSTANCE_NETWORKS[@]}
      do
        for ip in ${INSTANCE_IPS[@]}
        do
          source $ORIG_OPENSTACK
          ORIG_OPENSTACK_URL=$OS_AUTH_URL
          network_name=$(echo $network | awk -F'=' '{print $1}')
          network_id=$($openstack_cmd network show $network_name |grep -w id |awk -F'|' '{print $3}'|sed 's/ //g')
          subnet_name=$($openstack_cmd subnet list |grep $network_id |awk -F'|' '{print $3}'|sed 's/ //g')
          sub_cidr=$($openstack_cmd subnet list |grep "$subnet_name" |awk -F'|' '{print $5}'|sed 's/ //g')
          if [ $($grepcidr_cmd "$sub_cidr" <(echo "$ip") > /dev/null && echo $? || echo $?) -eq 0 ];
          then
            subnet_id=$($openstack_cmd subnet show $subnet_name|grep -w id |awk -F'|' '{print $3}' |sed 's/ //g')
            mac=$($openstack_cmd port list --long --server $INSTANCE |grep $subnet_id |grep "$ip" |awk -F'|' '{print $4}' |sed 's/ //g')
            source $DEST_OPENSTACK
            DEST_OPENSTACK_URL=$OS_AUTH_URL
            mac_in_use=$($openstack_cmd port list |grep $mac | awk -F'|' '{print $2}')
            if [ -z "$mac_in_use" ];
            then
            # variable is empty = we can use this mac
              $openstack_cmd port create --network $network_name --fixed-ip subnet=$subnet_name,ip-address=$ip --mac-address $mac $INSTANCE
              sleep 1
              PORT_IDS+=($($openstack_cmd port list --mac-address $mac -c ID -f value))
              echo -e "PORT_IDS: ${PORT_IDS[@]}"
            else
              # end the program probably some leftovers from previous migrations
              echo -e " Mac address $mac with ip: $ip already in use, please fix. Port not created!  -  $red_fail"
              PORT_ID=$($openstack_cmd port list --mac-address $INSTANCE_MAC -c ID -f value)
              # echo -e " Mac address $mac already in use, please fix and run again!  -  $red_fail"
              # exit 1
            fi
          fi
        done
      done

      echo -e "Instance name is:"
      echo -e $INSTANCE
      echo -e "Port IDs are:"
      echo -e ${PORT_IDS[@]}
      echo -e "Root volume is:"
      echo -e ${NEW_VOLUME_IDS[0]}
      source $DEST_OPENSTACK

      create_output_script
      exit 0
    else
      echo -e "You have chosen to exit: $decision  -  $grn_ok"
    fi
    ;;
  *)
    echo -e "Well i dont know anything about this state, exiting since there is something wrong  -  $red_fail"
    echo -e " - $yel_jail Please consider searching for the volume in manageable volumes in ceph"
    echo "VOL_ORIG_CLOUD: ${OLD_VOLUME_IDS[@]}"
    echo "VOL_DEST_CLOUD: ${NEW_VOLUME_IDS[@]}"
    echo "IP_ADDRESS: $INSTANCE_IP:"
    exit 1
  ;;
esac

echo "##############################"
echo $ORIG_OPENSTACK_URL
echo $DEST_OPENSTACK_URL
echo $INSTANCE
echo "##############################"
exit 0
