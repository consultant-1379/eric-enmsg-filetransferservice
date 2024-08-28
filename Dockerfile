ARG ERIC_ENM_SLES_BASE_SCRIPTING_IMAGE_NAME=eric-enm-sles-base-scripting
ARG ERIC_ENM_SLES_BASE_SCRIPTING_IMAGE_REPO=armdocker.rnd.ericsson.se/proj-enm
ARG ERIC_ENM_SLES_BASE_SCRIPTING_IMAGE_TAG=1.64.0-33
FROM ${ERIC_ENM_SLES_BASE_SCRIPTING_IMAGE_REPO}/${ERIC_ENM_SLES_BASE_SCRIPTING_IMAGE_NAME}:${ERIC_ENM_SLES_BASE_SCRIPTING_IMAGE_TAG} AS production

ARG BUILD_DATE=unspecified
ARG IMAGE_BUILD_VERSION=unspecified
ARG GIT_COMMIT=unspecified
ARG ISO_VERSION=unspecified
ARG RSTATE=unspecified

LABEL \
com.ericsson.product-number="CXC 174 2129" \
com.ericsson.product-revision=$RSTATE \
enm_iso_version=$ISO_VERSION \
org.label-schema.name="ENM Filetransfer Service Group" \
org.label-schema.build-date=$BUILD_DATE \
org.label-schema.vcs-ref=$GIT_COMMIT \
org.label-schema.vendor="Ericsson" \
org.label-schema.version=$IMAGE_BUILD_VERSION \
org.label-schema.schema-version="1.0.0-rc1"

COPY image_content/services/*.service /usr/lib/systemd/system/

RUN rpm -e --nodeps ERICcredentialmanagercli_CXP9031389 || echo "No ERICcredentialmanagercli_CXP9031389 installed"

# to have linux links to certificates where app looks for certs
RUN mkdir -p /certScript/

COPY image_content/createCertificatesLinks.sh /certScript/createCertificatesLinks.sh
COPY image_content/updateCertificatesLinks.sh /certScript/updateCertificatesLinks.sh

# TORF-537452 : TEMP to remove when script that restarts mediation PODS in CIS-149159 will be fixed
COPY image_content/credentialmanagercliRestartVM.sh /usr/lib/ocf/resource.d/credentialmanagercliRestartVM.sh
RUN mkdir -p -m 777 /opt/ericsson/ERICcredentialmanagercli && chmod 755 /usr/lib/ocf/resource.d/credentialmanagercliRestartVM.sh

RUN /bin/chmod 755 /certScript/createCertificatesLinks.sh && \
    /bin/chmod 755 /certScript/updateCertificatesLinks.sh

RUN zypper install -y \
    ERICpibscripts_CXP9032212 && \
    zypper download ERICenmsgfiletransferservice_CXP9041680 && \
    rpm -ivh /var/cache/zypp/packages/enm_iso_repo/ERICenmsgfiletransferservice_CXP9041680*.rpm --nodeps --noscripts && \
    zypper clean -a

RUN rm -rf /ericsson/enm/postinstall.sh && \
    rm -rf /ericsson/enm/smrs_sftp_config.sh && \
    rm -rf /ericsson/enm/sftp_ddc_data_collector.sh && \
    rm -rf /ericsson/enm/configTlsPropForFtpes.sh && \
    rm -rf /etc/vsftpd/scripts/configTlsPropForFtpes.sh && \
    rm -rf /ericsson/enm/smrs_configuration_checker_config.sh && \
    rm -rf /ericsson/enm/vsftpd_ddc_data_collector_config.sh && \
    rm -rf /ericsson/enm/sftp_instrumentation_data_collector.sh && \
    rm -rf /etc/rsyslog.d/09_config_file.conf

# Old script to enable ipv6 direct routing in pENM (TORF-152795), not needed in CN
RUN rm -f /ericsson/enm/enable_direct_routing.sh

# TD: remove unsupported Ciphers and MACs from SSH config
RUN sed -i.bak "s/blowfish-cbc,// ; s/cast128-cbc,// ; s/hmac-ripemd160,// ; s/hmac-ripemd160@openssh.com,//" /etc/ssh/sshd_config && \
    sed -i.bak "s/blowfish-cbc,// ; s/cast128-cbc,// ; s/hmac-ripemd160,// ; s/hmac-ripemd160@openssh.com,//" /etc/ssh/ssh_config


## disable jboss
RUN systemctl disable jboss.service && rm -rf /usr/lib/ocf/resource.d/jboss_healthcheck.sh

COPY image_content/filetransfer_post_startup.sh /ericsson/sg/filetransfer_post_startup.sh
RUN chmod 750 /ericsson/sg/filetransfer_post_startup.sh && \
    chmod 755 /home

COPY image_content/postinstall.sh /ericsson/enm/
COPY image_content/smrs_sftp_config.sh /ericsson/enm/
COPY image_content/sftp_ddc_data_collector.sh /ericsson/enm/
COPY image_content/configTlsPropForFtpes.sh /ericsson/enm/
COPY image_content/configTlsPropForFtpes.sh /etc/vsftpd/scripts/
COPY image_content/smrs_configuration_checker_config.sh /ericsson/enm/
COPY image_content/vsftpd_ddc_data_collector_config.sh /ericsson/enm/
COPY image_content/sftp_instrumentation_data_collector.sh /ericsson/enm/
COPY image_content/09_config_file.conf /etc/rsyslog.d/
COPY image_content/01_filetransfer_rsyslog.conf /etc/rsyslog.d/

COPY image_content/vmsshkeyservice.sh /etc/init.d/vmsshkeyservice.sh
RUN /bin/chmod 755 /etc/init.d/vmsshkeyservice.sh
RUN /bin/chown root:root /etc/init.d/vmsshkeyservice.sh

RUN /bin/mkdir -p /ericsson/cert/data/certs/vsftpd && \
    /bin/chown -R jboss_user:jboss /ericsson/cert/data/certs/vsftpd && \
    /bin/chmod -R 755 /ericsson/cert/data/certs/vsftpd

RUN /bin/mkdir -p /ericsson/cert/data/certs/CA && \
    /bin/chown -R jboss_user:jboss /ericsson/cert/data/certs/CA && \
    /bin/chmod -R 755 /ericsson/cert/data/certs/CA

RUN systemctl enable filetransfer_post_startup.service

RUN systemctl disable sg-post-startup

ENV GLOBAL_CONFIG="/gp/global.properties" \
    SG_POST_STARTUP_SCRIPT="/ericsson/sg/filetransfer_post_startup.sh" \
    DISABLE_PAM_OPENAM="true" \
    CLOUD_NATIVE_DEPLOYMENT="true"

EXPOSE 21 22 1636 4320 4447 7999 8080 8085 8445 9990 9999 12987

## used only for internal development, created
## temporary change for the development

#FROM production AS development
#RUN zypper install -y vim && zypper clean --all && echo "alias ll='ls -laF'" > /root/.bashrc
