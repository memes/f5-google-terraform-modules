#!/bin/sh
#
# Reusable functions for the BIG-IP setup scripts

error()
{
    echo "${GCE_LOG_TS:+"$(date +%Y-%m-%dT%H:%M:%S.%03N%z): "}$0: Error: $*" >&2
    exit 1
}

info()
{
    echo "${GCE_LOG_TS:+"$(date +%Y-%m-%dT%H:%M:%S.%03N%z): "}$0: Info: $*" >&2
}

# Retrieves a value associated with the supplied key from the instance metadata
# $1 = attribute key to pull
# $2 = optional default value to return if $1 doesn't exist
get_instance_attribute()
{
    attempt=0
    while [ "${attempt:-0}" -lt 10 ]; do
        http_status=$(curl -so /dev/null -w '%{http_code}' -H 'Metadata-Flavor: Google' "http://169.254.169.254/computeMetadata/v1/instance/attributes/${1}")
        retval=$?
        if [ "${retval}" -eq 0 ]; then
            if [ "${http_status}" -eq 200 ]; then
                curl -s --retry 20 -H 'Metadata-Flavor: Google' "http://169.254.169.254/computeMetadata/v1/instance/attributes/${1}?alt=text"
            else
                echo "${2:-""}"
            fi
            break
        fi
        info "Curl failed with exit code ${retval}; sleeping before retry"
        sleep 10
        attempt=$((attempt+1))
    done
    [ "${attempt}" -ge 10 ] && \
        info "Failed to get a result for ${1} from metadata server"
    return ${retval}
}

# Returns an OAuth token for active service account
get_auth_token()
{
    attempt=0
    while [ "${attempt:-0}" -lt 10 ]; do
        auth_token="$(curl -sf -H 'Metadata-Flavor: Google' 'http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token' | jq -r '.access_token')"
        retval=$?
        if [ "${retval}" -eq 0 ]; then
            echo "${auth_token}"
            break
        fi
        info "Curl failed with exit code $?; sleeping before retry"
        sleep 10
        attempt=$((attempt+1))
    done
    [ "${attempt}" -ge 10 ] && \
        info "Failed to get an auth token from metadata server"
    return ${retval}
}

# Return the contents of a secret from GCP Secret Manager, using a metadata key
# as the indirection layer. E.g. get_secret "foo" will lookup the instance
# metadata value for "foo", and use that as the key for Secret Manager value
# lookup.
#
# $1 = metadata attribute key that should hold the Secret Manager key to
# retrieve, defaults to 'admin_password_key'.
get_secret()
{
    secret_key="$(get_instance_attribute "${1:-"admin_password_key"}")"
    if [ -n "${secret_key}" ]; then
        auth_token="$(get_auth_token)" || error "Unable to get auth token: $?"
        project_id="$(curl -sf -H 'Metadata-Flavor: Google' 'http://169.254.169.254/computeMetadata/v1/project/project-id')" || \
            error "Unable to get project id from metadata: $?"
        curl -s -H "Authorization: Bearer ${auth_token}" "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${secret_key}/versions/latest:access" 2>/dev/null | \
            jq -r '.payload.data' 2>/dev/null | base64 -d 2>/dev/null
    else
        echo ""
    fi
    return 0
}

# Extract the contents of the supplied value and write to given file
# $1 = filepath that will bo overwritten with the payload
# $2 = payload contents must be a URL or base64 encoded and gzipped string
extract_payload()
{
    [ -n "${1}" ] || \
        error "file to receive payload must be given"
    [ -w "${1}" ] || \
        error "refusing to extract payload to non-existent file"
    [ -n "${2}" ] || \
        error "payload content is required"
    case "${2}" in
        https://storage.googleapis.com/*)
            auth_token="$(get_auth_token)" || \
                error "Unable to get auth token: $?"
            curl -sf -o "${1}" --retry 20 \
                    -H "Authorization: Bearer ${auth_token}" \
                    "${2}" || \
                error "Download of GCS file from ${2} failed: $?"
            ;;
        ftp://*|http://*|https://*)
            curl -skf -o "${1}" --retry 20 "${2}" || \
                error "download of ${2} failed with exit code $?"
            ;;
        *)
            base64 -d <<EOF | zcat > "${1}" || error "unable to decode payload: $?"
${2}
EOF
            ;;
    esac
    return 0
}
