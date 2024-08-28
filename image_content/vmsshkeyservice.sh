#!/bin/bash
### BEGIN INIT INFO
# Provides: vmsshkeyservice
# Default-Start:  3 4 5
# Default-Stop: 0 1 6
# Required-Start: network cloud-final
# Required-Stop:
# Short-Description: Service to preserve SSH host keys on VM
# Description: This is service to preserve SSH host key generate after the VM
#              is first created. When the VM is recreated again the SSH host
#              keys are restored to the VM.
### END INIT INFO
# COPYRIGHT Ericsson AB 2016

# Source function library.
if [ -f /etc/init.d/functions ]; then
  . /etc/init.d/functions
elif [ -f /etc/rc.status ]; then
  . /etc/rc.status
fi


global_properties_file="/ericsson/tor/data/global.properties"
RESTORE_FLAG="YES"
NAS_SHARE="/ericsson/tor/data/vm-host-keys"
SSH_HOST_DIR="/etc/ssh"
VMSSHKEYSERVICE="vmsshkeyservice"
LOCKFILE=/var/lock/subsys/${VMSSHKEYSERVICE}

restore_keys() {
    for key_file in ${SSH_HOST_KEYS} ; do
        waitsec=0
        while [ ! "$waitsec" -gt 10 ]; do
          if [ ! -f "${SSH_HOST_DIR}/${key_file}" ]; then
             logger -t ${VMSSHKEYSERVICE} -p user.info "$key_file doesnt exist sleep for 2 sec"
             sleep 2
             waitsec=$waitsec + 2
          else
            cp -af ${NAS_SHARE}/${SERVICE_NAME}/${key_file} ${SSH_HOST_DIR}/${key_file}
            logger -t ${VMSSHKEYSERVICE} -p user.info "Copying the ssh key ${key_file} from the NAS to VM: `hostname` SSH"
            waitsec=11
          fi
        done
    done
}


get_required_global_properties() {
  while IFS="=" read -r key value; do
    case "$key" in
      "preserve_vm_host_keys") preserve_vm_host_keys=$(echo ${value} | tr -s '[:upper:]' '[:lower:]') ;;
      "ENM_on_Cloud") ENM_on_Cloud=$(echo ${value} | tr -s '[:upper:]' '[:lower:]') ;;
    esac
  done < ${global_properties_file}
}

set_keys_to_preserve() {
  rh_relfile=/etc/redhat-release
  if [ -r $rh_relfile ]; then
    if grep -qi "release 6" $rh_relfile ; then
      SSH_HOST_KEYS="ssh_host_key ssh_host_key.pub ssh_host_dsa_key ssh_host_dsa_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub"
    elif grep -qi "release 7" $rh_relfile ; then
      SSH_HOST_KEYS="ssh_host_rsa_key ssh_host_rsa_key.pub ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_ecdsa_key ssh_host_ecdsa_key.pub"
    fi
  elif [ -r /etc/os-release ]; then
    grep -qw SLES /etc/os-release && SSH_HOST_KEYS="ssh_host_dsa_key ssh_host_dsa_key.pub ssh_host_ecdsa_key ssh_host_ecdsa_key.pub ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub"
  fi
}

set_keys_group() {
  # RHEL7 only
  [ -f /etc/redhat-release ] && grep -qi "release 7" /etc/redhat-release || return 0
  PRIVATE_RHEL7_SSH_HOST_KEYS="ssh_host_rsa_key ssh_host_ed25519_key ssh_host_ecdsa_key"
  for private_key_file in ${PRIVATE_RHEL7_SSH_HOST_KEYS} ; do
      chown "root:ssh_keys" ${SSH_HOST_DIR}/${private_key_file}
      msg="Set key ownership for RHEL7 VM: `hostname`"
      logger -t ${VMSSHKEYSERVICE} -p user.info ${msg}
  done
}

start() {
    echo "Starting vmsshkeyservice ..."
    set_keys_to_preserve
    if [ -f ${global_properties_file} ] ; then
        get_required_global_properties
    else
        msg="The global.properties file doesn't exist"
        logger -t ${VMSSHKEYSERVICE} -p user.error ${msg}
        echo "ERROR: $msg"
        return 3
    fi

    if [ "${ENM_on_Cloud}" == "true" ] ; then
        msg="The vmsshkeyservice is disabled on Cloud deployments"
        logger -t ${VMSSHKEYSERVICE} -p user.info ${msg}
        echo $msg | tee ${LOCKFILE}
        return 0
    fi

    if grep -qs "/ericsson/tor/data" /proc/mounts ; then
        if [ -d ${NAS_SHARE}/${SERVICE_NAME} ] ; then
            for key_file in ${SSH_HOST_KEYS} ; do
                if [ -f ${NAS_SHARE}/${SERVICE_NAME}/${key_file} ] ; then
                    if ! ssh-keygen -lf ${NAS_SHARE}/${SERVICE_NAME}/${key_file} > /dev/null 2>&1 ; then
                        logger -t ${VMSSHKEYSERVICE} -p user.info "The ssh key ${key_file} is invalid on NAS share for VM: `hostname`"
                        RESTORE_FLAG="NO"
                    fi
                else
                    logger -t ${VMSSHKEYSERVICE} -p user.info "The ssh key ${key_file} is missing on NAS share for VM: `hostname`"
                    RESTORE_FLAG="NO"
                fi
            done
        else
            RESTORE_FLAG="NO"
            mkdir -p ${NAS_SHARE}/${SERVICE_NAME}
            if [ $? -ne 0 ]; then
                msg="Can't create ${SERVICE_NAME} directory on ${NAS_SHARE} NAS share"
                logger -t ${VMSSHKEYSERVICE} -p user.error ${msg}
                echo "ERROR: $msg"
                return 1
            else
                msg="Folder '${NAS_SHARE}/${SERVICE_NAME}' created successfully"
                logger -t ${VMSSHKEYSERVICE} -p user.info ${msg}
            fi
        fi
    else
        msg="NAS share enm-data is not mounted on VM: `hostname`"
        logger -t ${VMSSHKEYSERVICE} -p user.error ${msg}
        echo "ERROR: $msg"
        return 2
    fi

    if [[ ${RESTORE_FLAG} == "YES" && "${preserve_vm_host_keys}" != "false" ]] ; then
        restore_keys
        msg="Host ssh keys were restored from NAS share for VM: `hostname`"
        logger -t ${VMSSHKEYSERVICE} -p user.info ${msg}
        echo ${msg} | tee ${LOCKFILE}
    fi
    set_keys_group
    return 0
}

stop() {
    if [ -f ${LOCKFILE} ] ; then
        rm -rf ${LOCKFILE}
    fi
}

# See how we were called.
case "$1" in
    start)
        start || exit $?
        ;;
    stop)
        stop || exit $?
        ;;
    restart)
        stop || exit $?
        start || exit $?
        ;;
    status)
        if [ -f ${LOCKFILE} ] ; then
            cat ${LOCKFILE}
            exit 0
        else
            exit 1
        fi
        ;;
    *)
        echo $"Usage: $0 {start|stop|status|restart}"
        exit 1
esac
exit 0
