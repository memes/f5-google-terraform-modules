#!/bin/sh
# shellcheck disable=SC1091
#
# This file will apply an Application Services3 JSON file pulled from metadata,
# if the AS3 extension is installed and a AS3 file is in metadata.

if [ -f /config/cloud/gce/setupUtils.sh ]; then
    . /config/cloud/gce/setupUtils.sh
else
    echo "${GCE_LOG_TS:+"$(date +%Y-%m-%dT%H:%M:%S.%03N%z): "}$0: ERROR: unable to source /config/cloud/gce/setupUtils.sh" >&2
    exit 1
fi

[ -f /config/cloud/gce/network.config ] && . /config/cloud/gce/network.config

if [ -z "${1}" ]; then
    info "AS3 payload was not supplied"
    exit 0
fi


ADMIN_PASSWORD="$(get_secret admin_password_key)"
[ -z "${ADMIN_PASSWORD}" ] && \
    error "Couldn't retrieve admin password from Secrets Manager"

retry=0
while [ ${retry} -lt 10 ]; do
    curl -skf --retry 20 -u "admin:${ADMIN_PASSWORD}" --max-time 60 \
        -H "Content-Type: application/json;charset=UTF-8" \
        -H "Origin: https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}" \
        -o /dev/null \
        "https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}/mgmt/shared/appsvcs/info" && break
    info "Check for AS3 installation failed, sleeping before retest: exit code $?"
    sleep 5
    retry=$((retry+1))
done
[ ${retry} -ge 10 ] && \
    error "AS3 extension is not installed"

# Extracting payload
tmp="$(mktemp -p /config/cloud/gce)"
extract_payload "${tmp}" "${1}" || \
    error "Unable to extract encoded payload: $?"

info "Applying AS3 payload"
response="$(jq -nrf "${tmp}" | curl -sk -u "admin:${ADMIN_PASSWORD}" --max-time 60 \
        -H "Content-Type: application/json;charset=UTF-8" \
        -H "Origin: https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}" \
        -d @- \
        "https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}/mgmt/shared/appsvcs/declare?async=true")" || \
    error "Error applying AS3 payload from ${tmp}"
id="$(echo "${response}" | jq -r '.id // ""')"
[ -n "${id}" ] || \
    error "Unable to submit AS3 declaration: $(echo "${response}" | jq -r '.code + " " + .message')"
rm -f "${tmp}" || info "Unable to delete ${tmp}"

while true; do
    response="$(curl -sk -u "admin:${ADMIN_PASSWORD}" --max-time 60 \
                -H "Content-Type: application/json;charset=UTF-8" \
                -H "Origin: https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}" \
                "https://${MGMT_ADDRESS:-localhost}${MGMT_GUI_PORT:+":${MGMT_GUI_PORT}"}/mgmt/shared/appsvcs/task/${id}")" || \
        error "Failed to get status for task ${id} with exit code: $?"
    code="$(echo "${response}" | jq -r '.results[0].code // "unspecified"')"
    case "${code}" in
        0)
                info "AS3 payload is being processed"
                ;;
        200)
                info "AS3 payload is installed"
                break
                ;;
        4*|5*)
                error "AS3 payload failed to install with error(s): $(echo "${response}" | jq -r '.results[0].message + " " + (.results[0].errors // [] | tostring)')"
                break
                ;;
        *)
                info "AS3 has code ${code}: ${response}"
                ;;
    esac
    info "Sleeping before reexamining AS3 tasks"
    sleep 5
done
exit 0
