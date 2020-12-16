#!/bin/sh
# shellcheck disable=SC1091
#
# This file will apply a Declarative Onboarding JSON file pulled from metadata,
# if the DO extension is installed and a DO file is in metadata.

if [ -f /config/cloud/gce/setupUtils.sh ]; then
    . /config/cloud/gce/setupUtils.sh
else
    echo "${GCE_LOG_TS:+"$(date +%Y-%m-%dT%H:%M:%S.%03N%z): "}$0: ERROR: unable to source /config/cloud/gce/setupUtils.sh" >&2
    [ -e /dev/ttyS0 ] && \
        echo "$(date +%Y-%m-%dT%H:%M:%S.%03N%z): $0: ERROR: unable to source /config/cloud/gce/setupUtils.sh" >/dev/ttyS0
    exit 1
fi

[ -f /config/cloud/gce/network.config ] && . /config/cloud/gce/network.config

if [ -z "${1}" ]; then
    info "Declarative Onboarding payload was not supplied"
    exit 0
fi

ADMIN_PASSWORD="$(get_secret admin_password_key)"
[ -z "${ADMIN_PASSWORD}" ] && \
    error "Couldn't retrieve admin password from Secrets Manager"

retry=0
while [ ${retry} -lt 10 ]; do
    curl -skf --retry 20 -u "admin:${ADMIN_PASSWORD}" --max-time 60 \
        -H "Content-Type: application/json" \
        -d '{"maxMessageBodySize":134217728}' \
        "https://${MGMT_ADDRESS:-localhost}:8100/mgmt/shared/server/messaging/settings/8100" && break
    info "Setting shared message size failed, sleeping before retest: curl exit code $?"
    sleep 5
    retry=$((retry+1))
done
[ ${retry} -ge 10 ] && \
    info "Failed to set shared message size; continuing anyway"

retry=0
while [ ${retry} -lt 10 ]; do
    curl -skf --retry 20 -u "admin:${ADMIN_PASSWORD}" --max-time 60 \
        -H "Content-Type: application/json;charset=UTF-8" \
        -H "Origin: https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}" \
        -o /dev/null \
        "https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}/mgmt/shared/declarative-onboarding/info" && break
    info "Check for DO installation failed, sleeping before retest: curl exit code $?"
    sleep 5
    retry=$((retry+1))
done
[ ${retry} -ge 10 ] && \
    error "Declarative Onboarding extension is not installed"

# Extracting payload to file to avoid any escaping or interpolation issues
raw="$(mktemp -p /var/tmp)"
extract_payload "${1}" > "${raw}" || \
    error "Unable to extract encoded payload: $?"

if [ -f /config/cloud/gce/do_filter.jq ]; then
    # Execute the raw JSON through a jq filter; allows run-time substitutions to
    # update ip addresses, MTUs, admin passwords, etc.
    payload="$(mktemp -p /var/tmp)"
    curl -sf --retry 20  -H 'Metadata-Flavor: Google' \
            'http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/?recursive=true' | \
        jq --arg password "${ADMIN_PASSWORD}" \
            --from-file /config/cloud/gce/do_filter.jq \
            --slurp - "${raw}" > "${payload}" || \
        error "Unable to process raw DO file ${raw} through jq: $?"
    rm -f "${raw}" || info "Unable to delete ${raw}"
else
    payload="${raw}"
fi

info "Applying Declarative Onboarding payload"
# Issue #79 - adding a charset to Content-Type when POSTing results in 400 response
# https://github.com/F5Networks/f5-declarative-onboarding/issues/79
id="$(curl -sk -u "admin:${ADMIN_PASSWORD}" --max-time 60 \
        -H "Content-Type: application/json" \
        -H "Origin: https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}" \
        -d @"${payload}" \
        "https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}/mgmt/shared/declarative-onboarding" | jq -r '.id')" || \
    error "Error applying Declarative Onboarding payload from ${payload}: curl exit code $?"
rm -f "${payload}" || info "Unable to delete ${payload}"

while true; do
    response="$(curl -sk -u "admin:${ADMIN_PASSWORD}" --max-time 60 \
                -H "Content-Type: application/json;charset=UTF-8" \
                -H "Origin: https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}" \
                "https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}/mgmt/shared/declarative-onboarding/task/${id}")" || \
        error "Failed to get status for task ${id}: curl exit code: $?"
    code="$(echo "${response}" | jq -r 'if .result then .result.code else .code end')"
    case "${code}" in
        200)
                info "Declarative Onboarding is complete"
                break
                ;;
        202)
                info "Declarative Onboarding is in process"
                ;;
        4*|5*)
                error "Declarative Onboarding payload failed to install with error(s): message is $(echo "${response}" | jq -r '.message + " " + (.errors // [] | tostring)')"
                ;;
        *)
                info "Declarative Onboarding has code ${code}: ${response}"
                ;;
    esac
    info "Sleeping before rechecking Declarative Onboarding tasks"
    sleep 5
done
