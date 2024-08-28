#!/bin/bash
#*******************************************************************************
# Version 1.0
# COPYRIGHT Ericsson 2022
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
#********************************************************************************
#
# Last revision: 2022-02-24
#

if [ -d /var/tmp ]; then
  LOG_DIR=/var/tmp
else
  LOG_DIR=/tmp
fi
LOG=$LOG_DIR/updateCertificatesLinks.log

touch $LOG

my_logger() {
  d=$(date)
  echo "$d $1" | tee -a $LOG
}
#
readonly dt=$(date +%s)
#
readonly script_name=$0
readonly release=$(grep '^# Last revision:' $script_name | sed 's/^# Last revision://')
readonly version=$(grep '^# Version' $script_name | sed 's/^# Version//')
my_logger "Starting $script_name release: $release version: $version"
#
runscript_list=''
#
run_script() {
  cert=$1
  if [ -f $cert ]; then
    for rs in $runscript_list
    do
      my_logger "Processing $rs entry"
      local c=$(echo "$rs" | sed 's/:.*//')
      local s=$(echo "$rs" | sed 's/.*://')
      if [ "$c" == "$cert" ]; then
        if [ -f $s ]; then
          if [ ! -f $cert.run ]; then
            touch $cert.run
          fi
          if grep -q "running $s at time $dt" $LOG; then
            my_logger "skipping $s because already run at time $dt"
          else
            my_logger "running $s at time $dt"
            chmod a+x $s
            $s
          fi
        fi
      fi
    done
  fi
  if grep -q "$s" $cert.run ; then
    sed -i "s,.*$s,$dt $s," $cert.run
  else
    echo "$dt $s" >> $cert.run
  fi
}
#
#
DEFAULT_TLS_MOUNT_PATH='/ericsson/credm/tlsMount'
if [ -z "$TLS_MOUNT_PATH" ]; then
  if ! grep -q "TLS_MOUNT_PATH not defined" $LOG ; then
    my_logger "TLS_MOUNT_PATH not defined, using default value: $DEFAULT_TLS_MOUNT_PATH"
  fi
  TLS_MOUNT_PATH="$DEFAULT_TLS_MOUNT_PATH"
fi
#
# from deployment.yaml
readonly TLS_DIR=$TLS_MOUNT_PATH
readonly TLS_LOCATION=tlsStoreLocation
readonly TLS_DATA=tlsStoreData

# Update links to keystores
readonly d=$(date)

for  _secret_mount_ in ${TLS_DIR}/*
do
    if [ -d ${_secret_mount_} ]
    then
      tlsFilename=$(cat ${_secret_mount_}/${TLS_LOCATION})
      cksumFile=$tlsFilename.cksum
      if [ ! -f ${tlsFilename} ]; then
        my_logger "MAKE MISSING LINK ${tlsFilename}"
        ln -s ${_secret_mount_}/${TLS_DATA} ${tlsFilename}
      fi
      csum=$(cksum $tlsFilename | sed 's/ .*//')
      if [ -f $cksumFile ]; then
        if grep -q "^Checksum:" $cksumFile ; then
          csum_old=$(grep "^Checksum:" $cksumFile | sed 's/Checksum://')
          if [ "$csum" != "$csum_old" ]; then
            my_logger "RENEW LINK ${tlsFilename}"
            mv ${tlsFilename} ${tlsFilename}.old
            ln -s ${_secret_mount_}/${TLS_DATA} ${tlsFilename}
            rm ${tlsFilename}.old
            my_logger "UPDATING CKSUM LINE ON $cksumFile"
            sed -i "s/^Checksum:.*/Checksum:$csum/" $cksumFile
            run_script ${tlsFilename}
          fi
        else
          my_logger "ADDING CKSUM LINE ON $cksumFile"
          echo "" >> $cksumFile
          sed -i "1 i Checksum:$csum" $cksumFile
        fi
      else
        my_logger "CREATING CKSUM FILE $cksumFile"
        echo "Checksum:$csum" > $cksumFile
      fi
    fi
done

exit 0

