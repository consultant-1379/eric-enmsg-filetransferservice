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
# Purpose: Looking for all mounted secrets and create the related links (if
#          required) to follow the Credential Manager behaviour.
#          Only when all the required secrets will be mounted this script will
#          complete.
#
#********************************************************************************
#
# Last revision: 2022-03-01
#
# Update list:
#  1 Issue on run as not root
#  2 LOG management
#  3 Readability of the script
#  4 indentation
#  5 readonly variables
#  6 removed leading blanks at end of lines
#
#********************************************************************************

if [ -d /var/tmp ]; then
  LOG_DIR=/var/tmp
else
  LOG_DIR=/tmp
fi
readonly LOG=${LOG_DIR}/createCertificatesLinks.log

my_logger() {
  echo "$1" | tee -a ${LOG}
}
#
readonly script_name=$0
readonly release=$(grep '^# Last revision:' $script_name | sed 's/^# Last revision://')
readonly version=$(grep '^# Version' $script_name | sed 's/^# Version//')
my_logger "Starting $script_name release: $release version: $version"
my_logger "init service, SERVICE_NAME='$SERVICE_NAME'"
my_logger "TLS_MOUNT_PATH='$TLS_MOUNT_PATH'"
#
readonly DEFAULT_TLS_MOUNT_PATH='/ericsson/credm/tlsMount'
if [ -z "$TLS_MOUNT_PATH" ]; then
  my_logger "TLS_MOUNT_PATH not defined, using default value: $DEFAULT_TLS_MOUNT_PATH"
  readonly TLS_MOUNT_PATH="$DEFAULT_TLS_MOUNT_PATH"
fi
#
if [ ! -d "$TLS_MOUNT_PATH" ]; then
  my_logger "NOTE: no TLS_MOUNT_PATH directory found nothing to do."
  exit 0
fi
#
#
# from deployment.yaml
readonly TLS_DIR=$TLS_MOUNT_PATH
readonly TLS_LOCATION=tlsStoreLocation
readonly TLS_DATA=tlsStoreData
readonly TLS_NONE=none
readonly SLEEP_TIME=5

my_logger "STARTUP $SERVICE_NAME service: looking for secrets"

scan_tlslocation () {

  # counters for directory and ready state
  tlsSecretCounter=0
  tlsLocationCounter=0

  # loop in TLS_MOUNT_PATH directory to find all mounted secrets
  # to create links where requested
  my_logger "loop in ${TLS_DIR}"
  for _secret_mount_ in ${TLS_DIR}/*
  do
    my_logger "${_secret_mount_} found"
    if [ -d ${_secret_mount_} ]; then
      my_logger "${_secret_mount_} is a mount point directory"
      tlsSecretCounter=$((tlsSecretCounter+1))

      # loop inside the folder
      for _tls_store_ in ${_secret_mount_}/*
      do
        my_logger "${_tls_store_} found"
        if [[ ${_tls_store_} == *"${TLS_LOCATION}"* ]]; then
          # check contents
          my_logger "content of ${_tls_store_} is $(< ${_tls_store_})"
          if [[ $(< ${_tls_store_}) != "${TLS_NONE}" ]]; then
            my_logger "valid LOCATION found"
            # increment ready state counter
            tlsLocationCounter=$((tlsLocationCounter+1))
          fi
        fi
      done
    fi
  done

  # check result
  my_logger "tlsSecretCounter = $tlsSecretCounter"
  my_logger "tlsLocationCounter = $tlsLocationCounter"

  if [ $tlsLocationCounter -gt 0 ]; then
    if [ $tlsSecretCounter == $tlsLocationCounter ]; then
      return 0
    fi
  fi
  return -1
}

while true
do
  my_logger "----"
  scan_tlslocation
  res=$?
  my_logger "res = $res"
  if [  $res == 0 ]; then
    my_logger "all locations found for $SERVICE_NAME service: OK"
    break
  fi
  sleep $SLEEP_TIME
done

# make links to keystores
for  _secret_mount_ in ${TLS_DIR}/*
do
  if [ -d ${_secret_mount_} ]
  then
    tlsFilename=$(cat ${_secret_mount_}/${TLS_LOCATION})
    my_logger "MAKE LINKS"
    my_logger ${tlsFilename}
    if echo ${tlsFilename} | grep -q "/cacerts" ; then
      if [ -f ${tlsFilename} ]; then
        ln -s ${_secret_mount_}/${TLS_DATA} ${tlsFilename}.from_credm
        cp ${tlsFilename}  ${tlsFilename}.from_image
        if grep -q BEGIN ${tlsFilename} ; then
          echo "" >> ${tlsFilename}
          cat ${tlsFilename}.from_credm >> ${tlsFilename}
        else
          keytool -importkeystore -srckeystore ${tlsFilename}.from_credm -destkeystore ${tlsFilename} -srcstoretype JKS -deststoretype JKS -srcstorepass changeit -deststorepass changeit -v -noprompt
        fi
      else
        ln -s ${_secret_mount_}/${TLS_DATA} ${tlsFilename}
      fi
    else
      ln -s ${_secret_mount_}/${TLS_DATA} ${tlsFilename}
    fi
  fi
done

# random delay to extend over time the startup of the replicas of the service
my_logger "wait to terminate"
sleep $[ ( $RANDOM % 10 )  + 1 ]s
my_logger "------------ end of createCertificatesLinks"

exit 0

