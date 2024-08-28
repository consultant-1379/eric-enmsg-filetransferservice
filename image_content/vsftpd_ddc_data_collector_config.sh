#!/bin/bash

###########################################################################
# COPYRIGHT Ericsson 2022
#
# The copyright to the computer program(s) herein is the property of
# Ericsson Inc. The programs may be used and/or copied only with written
# permission from Ericsson Inc. or in accordance with the terms and
# conditions stipulated in the agreement/contract under which the
# program(s) have been supplied.
###########################################################################

###########################################################################
# standard linux commands and script properties
#
###########################################################################
BASENAME=/bin/basename
SCRIPT_NAME="${BASENAME} ${0}"

PERL="/usr/bin/perl"
MAX_CRON_SLEEP_INTERVAL=3
SCRIPT_DIR="/ericsson/enm/"
VSFTPD_INSTRUMENTATION_DATA_COLLECTOR_NAME="vsftpd_instrumentation_data_collector.sh"
VSFTPD_INSTRUMENTATION_DATA_COLLECTOR_PATH=$SCRIPT_DIR$VSFTPD_INSTRUMENTATION_DATA_COLLECTOR_NAME

############################################################################
# This function will print an error message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
############################################################################
error() {
    logger -t ${LOG_TAG} -p user.err "ERROR ( ${SCRIPT_NAME} ): $1"
}

############################################################################
# This function will print an info message to /var/log/messages
# Arguments:
#       $1 - Message
# Return: 0
############################################################################
info() {
    logger -t ${LOG_TAG} -p user.notice "INFO ( ${SCRIPT_NAME} ): $1"
}


###################################################################
#Add a new cron task, to check vsftpd instrumentation data collector
# [scheduled for every 1 minute,[change this cron expression in case schedule differs]
###################################################################

_insert_vsftp_instrumentation_data_collector_entry_in_cron() {

check=`crontab -l | $PERL -nle 'print if m{vsftpd_instrumentation_data_collector.sh >/dev/null}'`
if [ -z "${check}" ]
then
     chmod +x ${VSFTPD_INSTRUMENTATION_DATA_COLLECTOR_PATH}
     (crontab -l 2>/dev/null; echo "*/1 * * * * ${VSFTPD_INSTRUMENTATION_DATA_COLLECTOR_PATH} >/dev/null 2>&1") | crontab - >/dev/null 2>&1
     info "vsftpd instrumentation data collector is added in cron cENM Repo"
else
     info "vsftpd instrumentation data collector is already being monitored in cron cENM Repo"
fi

}

#########################
# Main script starts here
#########################

_insert_vsftp_instrumentation_data_collector_entry_in_cron
exit 0