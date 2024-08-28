#!/bin/bash
###########################################################################
# COPYRIGHT Ericsson 2015
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
###########################################################################

if [ -z "$DATA_SHARE_DIR" ]; then
        DATA_SHARE_DIR=/ericsson/tor/data
fi

if [ -z "$GLOBAL_CONFIG" ]; then
        GLOBAL_CONFIG="$DATA_SHARE_DIR/global.properties"
fi

if [ -z "$ROOTCACERT_FILE" ]; then
        ROOTCACERT_FILE="$DATA_SHARE_DIR/certificates/rootCA.pem"
fi
BASENAME=/bin/basename
SCRIPT_NAME="${BASENAME} ${0}"
LOG_TAG="SMRS_SFTP_CONFIGURATION"
CP="/bin/cp -f"
CAT="/bin/cat"
ECHO="/bin/echo"
GREP="/bin/grep"
SHELLS="/etc/shells"
SED="/usr/bin/sed"
PERL="/usr/bin/perl"
MKDIR="/bin/mkdir -p"
SERVICE="/sbin/service"
SYSCTRL="/usr/bin/systemctl"
SETSEBOOL="/usr/sbin/setsebool"
CERT_FILE="/tmp/opendj_cert.pem"
SSSD_CONF="/etc/sssd/sssd.conf"
AUTHCONFIG_CERT_DIR="/etc/openldap/cacerts/"
AUTHCONFIG_CERT_FILE="$AUTHCONFIG_CERT_DIR/authconfig_downloaded.pem"
MAX_CRON_SLEEP_INTERVAL=3
POST_INSTALL_SCRIPT_DIR="/ericsson/3pp/jboss/bin/post-start/"
SSSD_HEALTH_CHECK_MONITOR_NAME="sssd_health_check_monitor.sh"
SSSD_HEALTH_CHECK_MONITOR_PATH=$POST_INSTALL_SCRIPT_DIR$SSSD_HEALTH_CHECK_MONITOR_NAME

COMMON_AUTH="/etc/pam.d/common-auth"
PAM_SSS_SO="pam_sss.so"
TRY_FIRST_PASS="nullok try_first_pass"
FORWARD_PASS="forward_pass"
PAM_UNIX_SO="pam_unix.so"
REPLACE_COUNT=1
SUFFICIENT_CONTROL_FLAG="sufficient"
AUTH_CONTROL_FLAG="auth"
REQUIRED_CONTROL_FLAG="required"
PAM_DENY_SO="pam_deny.so"
PAM_ENV_SO="pam_env.so"

#############################################################
#
# Logger Functions
#
#############################################################
info()
{
    logger -t "${LOG_TAG}" -p user.notice "INFORMATION (${SCRIPT_NAME} ): $1"
}

error()
{
    logger -t "${LOG_TAG}" -p user.err "ERROR (${SCRIPT_NAME} ): $1"
}

__execute_sssdconfig() {

#. $GLOBAL_CONFIG
info "Enabling pam ldap"
#$AUTHCONFIG --enablecache --enableldap --enableldapauth --ldaploadcacert=file://"$CERT_FILE" --ldapserver="ldaps://ldap-local:$COM_INF_LDAP_PORT ldaps://ldap-remote:$COM_INF_LDAP_PORT" --ldapbasedn="$COM_INF_LDAP_ROOT_SUFFIX" --update
   $SED -i "/^ldap_id_use_start_tls/c\ldap_id_use_start_tls = true" "$SSSD_CONF"
   $SED -i "/^ldap_tls_reqcert/c\ldap_tls_reqcert = demand" "$SSSD_CONF"
   $ECHO "ldap_tls_cacert = $CERT_FILE" >> "$SSSD_CONF"
#  $SYSCTRL restart sssd.service
}

#######################################
# Action :
#   __acquire_cert
#  Copy opendj cert and make available locally
# Globals :
#   None
# Arguments:
#   None
# Returns:
#
#######################################
__acquire_cert() {

info "Storing ROOTCA cert locally"
if ! [[ -d $AUTHCONFIG_CERT_DIR ]]; then
    $MKDIR $AUTHCONFIG_CERT_DIR
fi

$CP "$ROOTCACERT_FILE" "$CERT_FILE"
$CAT "$CERT_FILE" > "$AUTHCONFIG_CERT_FILE"
}

#############################################################
# This function overides the default configuration of pam to
# authenticate using pam_ldap first instead of pam_unix.
# SubString is replaced only on the very first occurence.
# Refer TORF-259812 for more info.
# Arguments:
#        none
#############################################################
__update_common_auth_rules()
{
    if [ ! -f "$COMMON_AUTH" ]; then
        error "$COMMON_AUTH file is unavailable. Skipping the common auth  rules update."
        return 1
    fi

    info "Updating and re-arranging the common auth  rules for  authentication in the sequence PAM_LDAP and PAM_UNIX."

    sed -i "/$PAM_SSS_SO\|$PAM_DENY_SO\|$PAM_UNIX_SO/d" $COMMON_AUTH
    if [ $? -ne 0 ];then
       error "failed to remove lines containing $PAM_SSS_SO or $PAM_UNIX_SO or $PAM_DENY_SO in $COMMON_AUTH"
    fi

    sed -i "/$AUTH_CONTROL_FLAG\t$REQUIRED_CONTROL_FLAG\t$PAM_ENV_SO/a $AUTH_CONTROL_FLAG\t$SUFFICIENT_CONTROL_FLAG\t$PAM_SSS_SO\t$FORWARD_PASS" $COMMON_AUTH
    if [ $? -ne 0 ];then
       error "failed to add $PAM_SSS_SO $FORWARD_PASS in $COMMON_AUTH"
    fi

    sed -i "/$AUTH_CONTROL_FLAG\t$SUFFICIENT_CONTROL_FLAG\t$PAM_SSS_SO\t$FORWARD_PASS/a $AUTH_CONTROL_FLAG\t$SUFFICIENT_CONTROL_FLAG\t$PAM_UNIX_SO\t$TRY_FIRST_PASS\n$AUTH_CONTROL_FLAG\t$REQUIRED_CONTROL_FLAG\t$PAM_DENY_SO" $COMMON_AUTH
    if [ $? -ne 0 ];then
       error "failed to add $AUTH_CONTROL_FLAG $SUFFICIENT_CONTROL_FLAG $PAM_UNIX_SO $TRY_FIRST_PASS and $AUTH_CONTROL_FLAG $REQUIRED_CONTROL_FLAG  $PAM_DENY_SO  in $COMMON_AUTH"
    fi
}

__update_shells_with_nologin()
{
     info "Checking if nologin shell is present in /etc/shells"
     $CAT ${SHELLS} | $GREP "nologin"
     if [ $? -ne 0 ]; then
         info "Updating /etc/shells with /sbin/nologin"
         $ECHO '/sbin/nologin' >> ${SHELLS}
     fi
}

#//////////////////////////////////////////////////////////////
# Main Part of Script
#/////////////////////////////////////////////////////////////

__acquire_cert

__execute_sssdconfig

__update_shells_with_nologin

__update_common_auth_rules

exit 0
