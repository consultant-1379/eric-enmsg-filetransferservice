#!/bin/bash

###########################################################################
# COPYRIGHT Ericsson 2021
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
###########################################################################

# Variables for certificates handling
_certs_data_dir="/ericsson/cert/data/certs"
_certs_source_dir="/ericsson/enm/conf"
_certs_dest_dir="/ericsson/credm/data/xmlfiles"

_ftpes_cert_dir_vsftpd="/ericsson/cert/data/certs/vsftpd"
_ftpes_cert_dir_CA="/ericsson/cert/data/certs/CA"
_ftpes_req_file="Vsftpd_CertRequest.xml"

# UTILITIES
BASENAME=/bin/basename
CHMOD=/bin/chmod
CHOWN=/bin/chown
CP=/bin/cp
ECHO=/bin/echo
GREP=/bin/grep
SERVICE=/sbin/service
SETSEBOOL=/usr/sbin/setsebool

# GLOBAL VARIABLES
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="FILE_TRANSFER_SERVICE_POST_INSTALL"
FILE_TRANSFER_SERVICE_RESOURCES_PATH="/opt/ericsson/ERICenmsgfiletransferservice_CXP9041680/resources"
FILE_TRANSFER_SERVICE_SSH_CONFIG_LOCATION="/ericsson/enm/etc"
SYSTEMCTL="/bin/systemctl"
PIDOF=/sbin/pidof
CHKCONFIG=/sbin/chkconfig
GLOBAL_PROPERTIES_FILE=/ericsson/tor/data/global.properties

# ChrootDirectory Variables
PM_PUSH_1_DIR="/home/smrs/MINI-LINK/pm_push_1/dev"
PM_PUSH_2_DIR="/home/smrs/MINI-LINK/pm_push_2/dev"
ML_INDOOR_DIR="/home/smrs/MINI-LINK/MINI-LINK-Indoor/dev"
ORADIO_DIR="/home/smrs/3ppsoftware/dev"
SMRS_USER_DIR="/home/smrs/dev"
SU_READ_DIR="/home/smrs/3ppsoftware/support_unit/dev"

PM_PUSH_1_SOCKET="/home/smrs/MINI-LINK/pm_push_1/dev/log"
PM_PUSH_2_SOCKET="/home/smrs/MINI-LINK/pm_push_2/dev/log"
ML_INDOOR_SOCKET="/home/smrs/MINI-LINK/MINI-LINK-Indoor/dev/log"
ORADIO_SOCKET="/home/smrs/3ppsoftware/dev/log"
SMRS_SOCKET="/home/smrs/dev/log"
SU_SOCKET="/home/smrs/3ppsoftware/support_unit/dev/log"

#///////////////////////////////////////////////////////////////
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
error()
{
    logger -s -t ${LOG_TAG} -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

#///////////////////////////////////////////////////////////////
# This function will print a warning message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#//////////////////////////////////////////////////////////////
warning()
{
    logger -s -t ${LOG_TAG} -p user.warning "WARNING ( ${SCRIPT_NAME} ): $1"
}

#//////////////////////////////////////////////////////////////
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
#/////////////////////////////////////////////////////////////
info()
{
    logger -s -t ${LOG_TAG} -p user.notice "INFORMATION ( ${SCRIPT_NAME} ): $1"
}

info "Running filetransferservice postinstall."

#//////////////////////////////////////////////////////////////
# Resolves the CM VIPs for IPv4 and IPv6 from
# /ericsson/tor/data/global.properties file and replaces them
# in the file SmrsWeb_CertRequest.xml to make subject
# alternative names available in the certificate request.
#
# The inputs from global.properties are formatted with cut to
# handle the following scenarios:
#     1) Multiple values in the properties 'svc_CM_vip_ipaddress'
#        and 'svc_CM_vip_ipv6address'. In this case, only the
#        first value will be considered significant (multiple
#        values are assumed to be comma-separated and containing
#        no blanks)
#     2) IP addresses in CIDR notation to specify the subnet
#        mask
#//////////////////////////////////////////////////////////////
function resolve_cm_vip_and_copy_cert_for_smrsweb() {

    if [ -f $GLOBAL_PROPERTIES_FILE ]
    then
        info "global.properties found. Extracting CM VIP for IPv4 and IPv6 VIP"
            CM_VIP_IPV4=$(grep svc_CM_vip_ipaddress $GLOBAL_PROPERTIES_FILE | cut -d '=' -f2)
            CM_VIP_IPV6=$(grep svc_CM_vip_ipv6address $GLOBAL_PROPERTIES_FILE | cut -d '=' -f2)
            cm_VIP=$(echo ${CM_VIP_IPV4} | cut -d ',' -f1 | cut -d '/' -f1 | xargs echo -n)
            cm_ipv6_VIP=$(echo ${CM_VIP_IPV6} | cut -d ',' -f1 | cut -d '/' -f1 | xargs echo -n)
    else
        error "global.properties file not found. Could not replace IPv4 or IPv6"
    fi
}

#//////////////////////////////////////////////////////////////
# This function will update the SELinux properties to allow
# SFTP upload
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
update_selinux_permissions()
{

    isCENM=$(printenv CLOUD_NATIVE_DEPLOYMENT);

    if [[ "${isCENM,,}" != "true" ]]; then
        info "Configuring SELinux for SFTP chroot upload..."

        ${SETSEBOOL} -P ssh_chroot_rw_homedirs 1

        if [ $? -eq 0 ]; then
            info "Configuration of SELinux for SFTP ssh_chroot_rw_homedirs was successful"
        else
            error "Configuration of SELinux for SFTP ssh_chroot_rw_homedirs failed"
        fi
    fi
}

#//////////////////////////////////////////////////////////////
# This function will copy the sshd_config delivered with
# filetransferservice to /etc/ssh/sshd_config with correct
# owners, group owners and permissions.
# It will also restart the sshd service. This is allow jailing
# of users (nodes) that login over sftp to download certificates
# from filetransferservice filesystem
# Arguments:
#       None
# Return: 0
#/////////////////////////////////////////////////////////////
copy_sshd_config()
{
    info "Copying the sshd_config from ${FILE_TRANSFER_SERVICE_SSH_CONFIG_LOCATION} to /etc/ssh/sshd_config..."

    sed -i.bak "s/blowfish-cbc,// ; s/cast128-cbc,// ; s/hmac-ripemd160,// ; s/hmac-ripemd160@openssh.com,//" ${FILE_TRANSFER_SERVICE_SSH_CONFIG_LOCATION}/sshd_config

    ${CP} -f ${FILE_TRANSFER_SERVICE_SSH_CONFIG_LOCATION}/sshd_config /etc/ssh/sshd_config

    ${CHOWN} root:root /etc/ssh/sshd_config

    ${CHMOD} 0600 /etc/ssh/sshd_config

    info "Copy of the sshd_config was successful"

    ${SERVICE} sshd restart

    if [ $? -eq 0 ]; then
        info "Restart of sshd service was successful"
    else
        error "Restart of sshd service failed"
    fi
}

#//////////////////////////////////////////////////////////////
# This function will copy the ssh_config delivered with
# FILE_TRANSFER_SERVICE to /etc/ssh/ssh_config with correct
# owners, group owners and permissions.
# No need to restart for the client file ssh_config
#/////////////////////////////////////////////////////////////
copy_ssh_config()
{
    info "Copying the ssh_config from ${FILE_TRANSFER_SERVICE_SSH_CONFIG_LOCATION} to /etc/ssh/ssh_config..."

    ${CP} -f ${FILE_TRANSFER_SERVICE_SSH_CONFIG_LOCATION}/ssh_config /etc/ssh/ssh_config

    ${CHOWN} root:root /etc/ssh/ssh_config

    ${CHMOD} 0600 /etc/ssh/ssh_config

    info "Copy of the ssh_config was successful"
}

executePostStartScripts()
{
    echo -n "Starting poststartscripts: "
    info "post start scripts start"
    sudo sh /ericsson/enm/apply_sftp_match_rules.sh
    evaluateScriptExecutionStatus "apply_sftp_match_rules.sh" $?
    sudo sh /ericsson/enm/bind-mount-smrs-filesystem.sh
    evaluateScriptExecutionStatus "bind-mount-smrs-filesystem" $?
    sudo sh /ericsson/enm/configCronForFtpes.sh
    evaluateScriptExecutionStatus "configCronForFtpes.sh" $?
    sudo sh /ericsson/enm/configTlsPropForFtpes.sh
    evaluateScriptExecutionStatus "configTlsPropForFtpes.sh" $?
    sudo sh /ericsson/enm/copy_smrsserv_host_keys.sh
    evaluateScriptExecutionStatus "copy_smrsserv_host_keys.sh" $?
    sudo sh /ericsson/enm/ftpes-config.sh
    evaluateScriptExecutionStatus "ftpes-config.sh" $?
    sudo sh /ericsson/enm/ftpunsecure-config.sh
    evaluateScriptExecutionStatus "ftpunsecure-config.sh" $?
    sudo sh /ericsson/enm/gc_threshold3_config.sh
    evaluateScriptExecutionStatus "gc_threshold3_config.sh" $?
    sudo sh /ericsson/enm/reconfig_sshd.sh
    evaluateScriptExecutionStatus "reconfig_sshd.sh" $?
    sudo sh /ericsson/enm/sftp_ddc_data_collector_config.sh
    evaluateScriptExecutionStatus "sftp_ddc_data_collector_config.sh" $?
    sudo sh /ericsson/enm/smrs_configuration_checker_config.sh
    evaluateScriptExecutionStatus "smrs_configuration_checker_config.sh" $?
    sudo sh /ericsson/enm/smrs_sftp_config.sh
    evaluateScriptExecutionStatus "smrs_sftp_config.sh" $?
    sudo sh /ericsson/enm/configCiphersForSshd.sh
    evaluateScriptExecutionStatus "configCiphersForSshd.sh" $?
    sudo sh /ericsson/enm/vsftpd_ddc_data_collector_config.sh
    evaluateScriptExecutionStatus "vsftpd_ddc_data_collector_config.sh" $?
    info "post start scripts end"
    sudo sh /ericsson/enm/configure-smrs-filesystem.sh
    evaluateScriptExecutionStatus "configure-smrs-filesystem.sh" $?
    info "Post start scripts including configure-smrs-filesystem.sh script execution completed"
}

evaluateScriptExecutionStatus()
{
exitCode=$2
if [[ "${exitCode}" != "0" ]]; then
    echo  "Script $1 executed with failures ${exitCode}"
else
    echo "Script $1 executed successfully"
fi

}

function rsyslog_config_file_update() {

    info "Updating 20_rsys_server.conf file on filetransferservice Service Group"

    sed -i '/^:msg, regex, ".*DHCP.*" stop.*/a if ($msg contains "postauth" and ($msg contains "close " or $msg contains "written " or $msg contains "open " or $msg contains "mode")) then /var/log/secure\n:msg, regex, "postauth" stop' /etc/rsyslog.d/20_rsys_server.conf

    info "restarting rsyslog service"
    systemctl restart rsyslog
    info "Sleeping 5 secs to allow the rsyslog to restart"
    sleep 5
    rsyslog_status=$(systemctl status rsyslog | grep "Active: active (running)")
    rsyslog_error=$(systemctl status rsyslog | grep "rsyslogd: error" )

    if [[ "${rsyslog_status}" =~ "Active: active (running)" && "${rsyslog_error}" != *"rsyslogd: error"* ]]; then
        info "rsyslog has been started successfully"
    elif [[ "${rsyslog_status}" =~ "Active: active (running)" && "${rsyslog_error}" =~ "rsyslogd: error" ]]; then
        info "rsylogv service started but rsyslogd errors detected"
    elif [[ "${rsyslog_status}" != *"Active: active (running)"* ]]; then
        info "rsyslog has not started."
    fi
}

function rsyslog_configuration_file_update () {

    info "Updating rsyslog.conf file on filetransferservice service group"

    sed -i "/$ModLoad imuxsock.so/a\$AddUnixListenSocket $PM_PUSH_1_SOCKET \n\$AddUnixListenSocket $PM_PUSH_2_SOCKET \n\$AddUnixListenSocket $ML_INDOOR_SOCKET \n\$AddUnixListenSocket $ORADIO_SOCKET \n\$AddUnixListenSocket $SMRS_SOCKET \n\$AddUnixListenSocket $SU_SOCKET" /etc/rsyslog.conf

}

#############
# MAIN PROGRAM
#############

rsyslog_configuration_file_update
info "Create directory for ChrootDirectory /home/smrs/MINI-LINK/pm_push_1"
if [ ! -e "$PM_PUSH_1_DIR" ]; then
    mkdir -p "$PM_PUSH_1_DIR"
fi

info "Create directory for ChrootDirectory /home/smrs/MINI-LINK/pm_push_2"
if [ ! -e "$PM_PUSH_2_DIR" ]; then
    mkdir -p "$PM_PUSH_2_DIR"
fi

info "Create directory for ChrootDirectory /home/smrs/MINI-LINK/MINI-LINK-Indoor"
if [ ! -e "$ML_INDOOR_DIR" ]; then
    mkdir -p "$ML_INDOOR_DIR"
fi

info "Create directory for ChrootDirectory /home/smrs/3ppsoftware"
if [ ! -e "$ORADIO_DIR" ]; then
    mkdir -p "$ORADIO_DIR"
fi

info "Create directory for ChrootDirectory /home/smrs"
if [ ! -e "$SMRS_USER_DIR" ]; then
    mkdir -p "$SMRS_USER_DIR"
fi

info "Create directory for ChrootDirectory /home/smrs/3ppsoftware/support_unit"
if [ ! -e "$SU_READ_DIR" ]; then
    mkdir -p "$SU_READ_DIR"
fi


rsyslog_config_file_update
info "Create directory '$_certs_dest_dir' for storing xml files."
if [ ! -e "$_certs_dest_dir" ]; then
    mkdir -p "$_certs_dest_dir"
fi

info "Create directory '$_certs_data_dir' for storing certificates."
if [ ! -e "$_certs_data_dir" ]; then
    mkdir -p "$_certs_data_dir"
fi

info "Create directories for ftpes for storing certificates."
if [ ! -e "$_ftpes_cert_dir_vsftpd" ]; then
    mkdir -p "$_ftpes_cert_dir_vsftpd"
fi

if [ ! -e "$_ftpes_cert_dir_CA" ]; then
    mkdir -p "$_ftpes_cert_dir_CA"
fi

info "Copy xml files to created directory: $_certs_dest_dir"
cp $_certs_source_dir/$_ftpes_req_file $_certs_dest_dir

update_selinux_permissions
copy_sshd_config
copy_ssh_config
executePostStartScripts


resolve_cm_vip_and_copy_cert_for_smrsweb
$SYSTEMCTL daemon-reload
info "Filetransferservice postinstall completed."

exit 0
