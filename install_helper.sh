#!/bin/bash

set -x

if [ $# -lt 4 ];
then 
	echo "USAGE : $0 <tag> <tardis_instance_number> <app_name> <is upgrade> [<old tag>]"
	exit 1
fi

REL_VERSION=$1
HEADEND_CODE=$2
APP_NAME=$3
IS_UPGRADE=$4
OLD_VERSION=""
if [ $# -eq 5 ]; then
    OLD_VERSION=$5
fi
INSTANCE_NUMBER=100
BACKUP_CONFIG="tmp"

function setconf ()
{
    sed /"^$1[ ]*="/c$1=$2 $TMPFILE -i
}

function getconf () 
{
    grep "^$1[ ]*=[ ]*" $REFFILE | awk -F "=" '{print $2}'
}

function restore_configs ()
{
    INFILE=$1
    REFFILE=$2
    OUTFILE=$1
    TMPFILE=/tmp/tmp.conf

    sudo chmod 666 $INFILE $REFFILE
    
    cp $INFILE $TMPFILE

    cat $INFILE | 
    while read line
    do
        if [[ -z $line ]] || [[ "${line:0:1}" == "#" ]]; then
            continue
        else
            field=`echo $line | awk -F"=" '{print $1}'`
            value=`getconf $field`

            #echo Field in board.conf.in:    $field
            #echo Value in board.conf:       $value
            if [[ -z $value ]]; then
                continue
            else
                setconf $field $value
            fi
        fi
    done

    sudo cp $TMPFILE $OUTFILE
}

if [[ $HEADEND_CODE =~ ^-?[0-9]+$ ]];
then
    echo $HEADEND_CODE
    echo $((10#$HEADEND_CODE+0))
    INSTANCE_NUMBER=$((10#$HEADEND_CODE+0))
else
    echo "tardis_instance_number must an integer."
    exit 1
fi


docker login -u amagidevops -p beefed0108
docker pull amagidevops/tardis:${REL_VERSION}

if [ $IS_UPGRADE -eq 1 ];then
    if [ -e $OLD_VERSION ];
    then
	    echo "Old release tag is mandatory to upgrade docker."
	exit 1
   fi
    BACKUP_CONFIG=/tmp/backup_tardis_${INSTANCE_NUMBER}_${APP_NAME}_v${OLD_VERSION}.ini
    sudo cp tardis_${INSTANCE_NUMBER}_${APP_NAME}/${OLD_VERSION}/config.ini $BACKUP_CONFIG
    #sudo -E env "PATH=$PATH" ./upgrade_tardis.sh tardis_${HEADEND_CODE}_${APP_NAME} $4 ${REL_VERSION}
    docker stop tardis_${INSTANCE_NUMBER}_${APP_NAME}_v${OLD_VERSION}
    docker rm tardis_${INSTANCE_NUMBER}_${APP_NAME}_v${OLD_VERSION}
    docker rmi amagidevops/tardis:${OLD_VERSION}
fi

sudo mkdir -p tardis/${REL_VERSION}; cd tardis/${REL_VERSION}; sudo docker run --rm -v `pwd`/:/cp amagidevops/tardis:${REL_VERSION} cp -r /home/root/docker_mgmt /cp; cd docker_mgmt
if [ $IS_UPGRADE -eq 1 ];then
    restore_configs ./config.ini $BACKUP_CONFIG
    sudo rm $BACKUP_CONFIG
else
    PORT=$((51050+INSTANCE_NUMBER))
    sudo su -c "sed s/"grpc_server_port.*"/"grpc_server_port=$PORT"/ -i ./config.ini"
    sudo su -c "sed s/"instance_num.*"/"instance_num=$INSTANCE_NUMBER"/ -i ./config.ini"
    sudo su -c "sed s/"app_name.*"/"app_name=$APP_NAME"/ -i ./config.ini"
fi

sudo -E env "PATH=$PATH:/usr/local/bin/" ./install_tardis.sh ./config.ini ${APP_NAME} /mnt/tardis_${INSTANCE_NUMBER}_${APP_NAME}/logs tardis_${INSTANCE_NUMBER}_${APP_NAME} ${REL_VERSION}
