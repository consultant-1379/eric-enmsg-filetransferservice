#!/bin/bash
###########################################################################
# COPYRIGHT Ericsson 2021                                                 #
#                                                                         #
# The copyright to the computer program(s) herein is the property of      #
# Ericsson Inc. The programs may be used and/or copied only with written  #
# permission from Ericsson Inc. or in accordance with the terms and       #
# conditions stipulated in the agreement/contract under which the         #
# program(s) have been supplied.                                          #
###########################################################################
PROG="filetransfer_post_startup.sh"

CRON_PAM_CONF=/etc/pam.d/crond
SSHD_PAM_CONF=/etc/pam.d/sshd
SU_PAM_CONF=/etc/pam.d/su
SED=/bin/sed
GREP=/bin/grep

PRE_INSTALL=/ericsson/enm/preinstall.sh
$PRE_INSTALL
if [ $? -eq 0 ]; then
  info "execution of $PRE_INSTALL completed successfully"
else
  error "execution of $PRE_INSTALL failed"
fi

CREATE_CERTIFICATES_LINKS=/certScript/createCertificatesLinks.sh

info "creating linux sym links to locations where app looks for certs"
$CREATE_CERTIFICATES_LINKS
echo "CREATE_CERTIFICATES_LINKS" $CREATE_CERTIFICATES_LINKS
if [ $? -eq 0 ]; then
  info "execution of $CREATE_CERTIFICATES_LINKS completed successfully"
else
  error "execution of $CREATE_CERTIFICATES_LINKS failed"
fi
POST_INSTALL="sudo sh /ericsson/enm/postinstall.sh"
$POST_INSTALL
if [ $? -eq 0 ]; then
  info "execution of $POST_INSTALL completed successfully"
else
  error "execution of $POST_INSTALL failed"
fi


