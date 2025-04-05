#!/bin/bash
set -e

GH_PROJECT_NAME=base-immich-nextcloud
GH_BASE_URL=https://github.com/thedebuggedlife/selfhost-bootstrap/tree/main
GH_PROJECT_URL=$GH_BASE_URL/projects/base-immich-nextcloud
GH_IO_BASE_URL=https://thedebuggedlife.github.io/selfhost-bootstrap
GH_IO_APPDATA_URL=$GH_IO_BASE_URL/appdata/$GH_PROJECT_NAME.zip
GH_RAW_BASE_URL=https://raw.githubusercontent.com/thedebuggedlife/selfhost-bootstrap/refs/heads/main
GH_RAW_PROJECT_URL=$GH_RAW_BASE_URL/projects/$GH_PROJECT_NAME

SMTP2GO_API_BASE_URL=https://api.smtp2go.com/v3
CLOUDFLARE_API_BASE_URL=https://api.cloudflare.com/client/v4
TAILSCALE_API_BASE_URL=https://api.tailscale.com/api/v2
IMMICH_BASE_URL=

################################################################################
#                               COLOR DEFINITIONS

# Reset
COff='\033[0m'       # Text Reset

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# Bold
BBlack='\033[1;30m'       # Black
BRed='\033[1;31m'         # Red
BGreen='\033[1;32m'       # Green
BYellow='\033[1;33m'      # Yellow
BBlue='\033[1;34m'        # Blue
BPurple='\033[1;35m'      # Purple
BCyan='\033[1;36m'        # Cyan
BWhite='\033[1;37m'       # White

# Underline
UBlack='\033[4;30m'       # Black
URed='\033[4;31m'         # Red
UGreen='\033[4;32m'       # Green
UYellow='\033[4;33m'      # Yellow
UBlue='\033[4;34m'        # Blue
UPurple='\033[4;35m'      # Purple
UCyan='\033[4;36m'        # Cyan
UWhite='\033[4;37m'       # White

# High Intensity
IBlack='\033[0;90m'       # Black
IRed='\033[0;91m'         # Red
IGreen='\033[0;92m'       # Green
IYellow='\033[0;93m'      # Yellow
IBlue='\033[0;94m'        # Blue
IPurple='\033[0;95m'      # Purple
ICyan='\033[0;96m'        # Cyan
IWhite='\033[0;97m'       # White

# Bold High Intensity
BIBlack='\033[1;90m'      # Black
BIRed='\033[1;91m'        # Red
BIGreen='\033[1;92m'      # Green
BIYellow='\033[1;93m'     # Yellow
BIBlue='\033[1;94m'       # Blue
BIPurple='\033[1;95m'     # Purple
BICyan='\033[1;96m'       # Cyan
BIWhite='\033[1;97m'      # White

################################################################################
#                                   LOGGING

log_header() {
    echo -e "\n${BWhite}================================================================================\n$1${COff}\n"
}

log_warn() {
    echo -en "\n🟡 ${BIYellow}WARN:${IYellow} $1${COff}\n\n" >&2
}

log_error() {
    echo -en "\n🔴 ${BIRed}ERROR:${IRed} $1${COff}\n\n" >&2
}

log_done() {
    echo -en "\n🎉 ${BWhite}All operations completed successfully${COff}\n\n"
}

################################################################################
#                           MANIPULATING .ENV FILE

# Save a kvp to $ENV_FILE
# Params:   $1 Variable name
#           $2 Variable value
save_env() {
    local env_variable=$1
    local env_value=$2
    echo -e "Saving ${Purple}$env_variable${COff} in ${Cyan}$ENV_FILE${COff}"
    sed -i -E "s|^($env_variable)=.*|\1=${env_value}|" "$ENV_FILE"
    eval "$env_variable=$env_value"
}

# Generate a random id and save to $ENV_FILE
# Params:   $1 Variable name
#           $2 Length (#chars) of value [default=20]
save_env_id() {
    local env_variable=$1
    local id_length=${2:-20}
    local env_value="${!env_variable}"
    if [ -z "$env_value" ]; then
        env_value=$(tr -cd '[:alnum:]' </dev/urandom | fold -w "${id_length}" | head -n 1 | tr -d '\n')
    fi
    save_env "$env_variable" "$env_value"
}

# Prompt user for a value and save to $ENV_FILE
# Params:   $1 Variable name
#           $2 Text prompt
#           $3 If `true`, offer existing variable value as default [default=true]
#           $4 If `true`, do not allow empty values [default=true]
#           $5 If `true`, mask the input (password) [default=false]
ask_for_env() {
    local env_variable=$1
    local prompt=$2
    local use_default=${3:-true}
    local required=${4:-true}
    local masked=${5:-false}
    if [[ "$RESUME" = "true" && -n "${!env_variable}" && "$use_default" = "true" ]]; then 
        return 0
    fi
    local default_value
    local env_variable_default="${env_variable}_DEFAULT"
    if [[ "$use_default" = "true" ]]; then
        default_value="${!env_variable:-${!env_variable_default}}"
    fi
    local user_input=$(ask_value "$prompt" "$default_value" "$required" "" "$masked")
    save_env "$env_variable" "$user_input"
}

################################################################################
#                           MANIPULATING SECRETS

# Save the value of an environment variable to a secret file
# Params:   $1 Secret file name
#           $2 Variable name
save_env_secret() {
    local secret_filename=$1
    local env_variable=$2
    if [ ! -n "${!env_variable}" ]; then
        log_error "Missing value for '$env_variable' in '$ENV_FILE'"
        exit 1
    fi
    echo -e "Creating secret file ${Cyan}$secret_filename${COff}"
    printf "%s" "${!env_variable}" >"$secret_filename"
}

# Create a random secret and save to a secret file
# Params:   $1 Secret file name
#           $2 Length (#chars) of generated secret
create_secret() {
    local secret_filename=$1
    local SECRET_LENGTH=${2:-40}
    if [ -f "$secret_filename" ]; then
        echo -e "Secret file ${Cyan}$secret_filename${COff} already exists."
    else
        echo -e "Creating secret file ${Cyan}$secret_filename${COff}"
        tr -cd '[:alnum:]' </dev/urandom | fold -w "${SECRET_LENGTH}" | head -n 1 | tr -d '\n' >$secret_filename
    fi
}

# Create a random password and its digest and save to a secret file
# Uses Authelia's crypto hash generation with argon2 algorithm
# Params:   $1 Name of the password/digest pair
#           $2 Length (#chars) of the generated password [default=64]
create_password_digest_pair() {
    local pair_name=$1
    local password_length=${2:-64}
    local password_filename="${pair_name}_password"
    local digest_filename="${pair_name}_digest"
    if [ -f "$password_filename" ] && [ -f "$digest_filename" ]; then
        echo -e "The password and digest files for ${Cyan}$pair_name${COff} already exist."
        return 0
    fi
    local output=$(sg docker -c "docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --random --random.length ${password_length} --random.charset alphanumeric")
    local password_value=$(echo "$output" | awk '/Random Password:/ {print $3}')
    local digest_value=$(echo "$output" | awk '/Digest:/ {print $2}')
    if [ -z "$password_value" ] || [ -z "$digest_value" ]; then
        log_error "Password or digest extraction failed."
        exit 1
    fi
    echo -e "Creating password file ${Cyan}$password_filename${COff}"
    printf "%s" "$password_value" >"$password_filename"
    echo -e "Creating digest file ${Cyan}$digest_filename${COff}"
    printf "%s" "$digest_value" >"$digest_filename"
}

# Create an RSA key using OpenSSL and saves private and public keys to file
# Params:   $1 Name of the private key file
#           $2 Name of the public key file
#           $3 Lenght of the key [default=2048]
create_rsa_keypair() {
    local private_key=$1
    local public_key=$2
    local key_length=${3:-2048}
    if [ -f "$private_key" ]; then
        echo -e "Private key file ${Cyan}$private_key${COff} already exists."
    else
        echo -e "Generating private key ${Cyan}$private_key${COff}."
        openssl genrsa -out "$private_key" $key_length
        if [ $? -ne 0 ]; then
            logerror "Failed to generate private key '$private_key'."
            exit 1
        fi
    fi
    if [ -f "$public_key" ]; then
        echo -e "Public key file ${Cyan}$public_key${COff} already exists."
    else
        echo -e "Generating public key ${Cyan}$public_key${COff}."
        openssl rsa -in "$private_key" -outform PEM -pubout -out "$public_key"
        if [ $? -ne 0 ]; then
            log_error "Failed to generate public key '$public_key'"
            exit 1
        fi
    fi
}

################################################################################
#                                   HTTP HELPERS

# Makes an HTTP request and returns the response body (if any)
# Params:   $1 HTTP Method (GET|DELETE|PUT|POST)
#           $2 URL of request
#           $3 Header for authentication (e.g. "X-API-Key: my-key")
#           $4 Body of the request [optional]
# Returns:  The body of the response
rest_call() {
    local method=$1
    local url=$2
    local auth=$3
    local body=$4
    # Debug
    # echo "Method: $method" >&2
    # echo "URL: $url" >&2
    # echo "Body: $body" >&2
    # Make the curl request.
    local response
    if [ -n "$body" ]; then
        response=$(curl -s -w "\n%{http_code}" \
            --request $method \
            --url $url \
            --header "Content-Type: application/json" \
            --header "$auth" \
            --header "accept: application/json" \
            --data "$body")
    else
        response=$(curl -s -w "\n%{http_code}" \
            --request $method \
            --url $url \
            --header "$auth" \
            --header "accept: application/json")
    fi
    # Separate the body and the HTTP status code.
    local http_status=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    # Debug
    # echo "HTTP Status: $http_status" >&2
    # echo -e "Response Body:\n$(echo $response | jq .)" >&2
    # Check if the status code indicates success (2XX)
    if [[ "$http_status" =~ ^2 ]]; then
        echo "$response"
    else
        log_error "Request to $method $url failed with $http_status: $response"
        return 1
    fi
}

################################################################################
#                              IMMICH API CLIENT

immich_rest_call() {
    if [[ -z "$IMMICH_BASE_URL" || -z "$IMMICH_API_KEY" ]]; then
        log_error "Base settings to call Immich have not been set."
        return 1
    fi
    local response
    if ! response=$(rest_call $1 "$IMMICH_BASE_URL/api/$2" "x-api-key: $IMMICH_API_KEY" "$3"); then
        return 1
    fi
    echo "$response"
}

immich_get_config() {
    local response
    if ! response=$(immich_rest_call GET system-config); then
        return 1
    fi
    if ! echo "$response" | jq empty > /dev/null 2>&1; then
        log_error "Immich API did not return valid JSON"
        log_error "$resposne"
    fi
    echo "$response"
}

immich_update_config() {
    immich_rest_call PUT system-config "$1"
    if [ $? -ne 0 ]; then
        return 1
    fi
}

################################################################################
#                              SMTP2GO API CLIENT

# Makes a request to SMTP2GO API
# Params:   $1 HTTP Method
#           $2 API Path
#           $3 Request body [Optional]
# Returns:  Body of the response
smtp2go_rest_call() {
    local response
    if ! response=$(rest_call $1 "$SMTP2GO_API_BASE_URL/$2" "X-Smtp2go-Api-Key: $SMTP2GO_API_KEY" "$3"); then
        return 1
    fi
    echo "$response"
}

# Adds a verified domain
# Params:   $1 Domain name
# Returns:  The domain object
smtp2go_add_domain() {
    local domain_name=$1
    echo -e "Attempting to create domain ${UPurple}$domain_name${COff} via SMTP2GO API..." >&2
    local response
    if ! response=$(smtp2go_rest_call POST domain/add "{\"auto_verify\": false, \"domain\": \"$domain_name\"}"); then
        return 1
    fi
    local domain_obj=$(echo "$response" | jq -r --arg domain "$domain_name" '.data.domains[] | select(.domain.fulldomain == $domain)')
    if [ -z "$domain_obj" ]; then
        log_error "Could not extract domain from response: $response"
        return 1
    fi
    echo "$domain_obj"
}

# Checks if validation of a domain has succeeded
# Params:   $1 Domain name
#           $2 Number of seconds to wait [Default=15]
smtp2go_validate_domain() {
    local domain_name=$1
    local wait_sec=${2:-15}
    local response
    for i in $(seq 1 "$wait_sec"); do
        echo -n "Waiting for 5s for DNS records to propagate..."
        sleep 5
        if ! response=$(smtp2go_rest_call POST domain/verify "{\"domain\":\"$domain_name\"}"); then
            exit 1
        fi
        local domain=$(echo "$response" | jq -r --arg domain "$domain_name" '.data.domains[] | select(.domain.fulldomain == $domain)')
        local dkim=$(echo "$domain" | jq -r '.domain.dkim_verified')
        local return_path=$(echo "$domain" | jq -r '.domain.rpath_verified')
        local link=$(echo "$domain" | jq -r '.trackers[0].cname_verified')
        if [ "$dkim" = "true" ] && [ "$return_path" = "true" ]; then
            echo -e "\nDomain ${UPurple}$domain_name${COff} is fully verified"
            return 0
        fi
        echo " domain has not been validated yet."
    done
    log_error "Failed to verify $domain_name: $response"
    exit 1
}

# Adds an SMTP user to the account
# Params:   $1 Username
# Returns:  User object
smtp2go_add_user() {
    local username=$1
    local password=$(tr -cd '[:alnum:]' </dev/urandom | fold -w 20 | head -n 1 | tr -d '\n')
    local json_payload=$(jq -n \
        --arg username "$username" \
        --arg password "$password" \
        --arg description "Email sender for self-hosted applications" \
        '{username: $username, email_password: $password, description: $description}')
    echo -e "Creating user ${Purple}$username${COff} in SMTP2GO account" >&2
    local response
    if ! response=$(smtp2go_rest_call POST users/smtp/add "$json_payload"); then
        return 1
    fi
    local user=$(echo "$response" | jq -r --arg username "$username" '.data.results[] | select(.username == $username)')
    if [ -z "$user" ]; then
        log_error "Failed to create user: $response"
        return 1
    fi
    echo "$user"
}

################################################################################
#                            CLOUDFLARE API CLIENT

# Makes a request to Cloudflare API
# Params:   $1 HTTP Method
#           $2 API Path
#           $3 Request body [Optional]
# Returns:  Body of the response
cloudflare_rest_call() {
    local response
    if ! response=$(rest_call $1 "$CLOUDFLARE_API_BASE_URL/$2" "Authorization: Bearer ${CF_DNS_API_TOKEN}" "$3"); then
        return 1
    fi
    echo "$response"
}

cloudflare_get_account_id() {
    local response
    if ! response=$(cloudflare_rest_call GET accounts); then
        return 1
    fi
    local account_id=$(echo "$response" | jq -r '.result[0].id')
    if [[ -z "$account_id" || "$account_id" = "null" ]]; then
        log_error "Failed to retrieve cloudflare account ID"
        return 1
    fi
    echo "$account_id"
}

# Gets the ID of a zone by domain name
# Params:   $1 Domain name
# Returns:  The ID of the zone
cloudflare_get_zone_id() {
    local domain_name=$1
    local response
    if ! response=$(cloudflare_rest_call "GET" "zones?name=${domain_name}"); then
        return 1
    fi
    local zone_id=$(echo "$response" | jq -r '.result[0].id')
    if [ -z "$zone_id" ] || [ "$zone_id" = "null" ]; then
        log_error "Unable to retrieve zone ID for domain $domain_name"
        return 1
    fi
    echo "$zone_id"
}

# Gets a DNS record by name
# Params:   $1 Zone ID
#           $2 Name of the record
# Returns:  DNS record object
cloudflare_get_record() {
    local zone_id=$1
    local name=$2
    local response
    if ! response=$(cloudflare_rest_call GET "zones/$zone_id/dns_records?&name=$name"); then
        return 1
    fi
    echo "$response"
}

# Adds or updates a DNS record
# Params:   $1 Zone ID
#           $2 Type of DNS record (e.g. A | AAAA | CNAME)
#           $3 Name of the record
#           $4 Content to save on the record (e.g. 10.10.10.10)
#           $5 Whether the record should get CloudFlare proxy logic [Default=true]
cloudflare_add_or_update_record() {
    local zone_id=$1
    local type=$2
    local name=$3
    local content=$4
    local proxied=${5:-false}
    local existing
    if ! existing=$(cloudflare_get_record $zone_id "$name"); then
        exit 1
    fi
    local record_id=$(echo "$existing" | jq -r '.result[0].id // empty')
    local json_payload=$(jq -n \
        --arg type "$type" \
        --arg name "$name" \
        --arg content "$content" \
        --arg comment "SMTP2GO verification record" \
        --argjson proxied $proxied \
        '{type: $type, name: $name, content: $content, proxied: $proxied, comment: $comment}')
    local response
    if [ -n "$record_id" ]; then
        echo -e "Updating existing ${Cyan}$type${COff} record for ${Purple}$name${COff}..."
        if ! response=$(cloudflare_rest_call PUT "zones/$zone_id/dns_records/$record_id" "$json_payload"); then
            exit 1
        fi
        if echo "$response" | jq -e '.success' >/dev/null; then
            echo "Record updated successfully."
        else
            log_error "Failed to update record: $response"
            exit 1
        fi
    else
        echo -e "Creating new ${Cyan}$type${COff} record for ${Purple}$name${COff}..."
        if ! response=$(cloudflare_rest_call POST "zones/$zone_id/dns_records" "$json_payload"); then
            exit 1
        fi
        if echo "$response" | jq -e '.success' >/dev/null; then
            echo "Record created successfully."
        else
            log_error "Failed to create record: $response"
            exit 1
        fi
    fi
}

cloudflare_get_tunnel() {
    local account_id=$1
    local tunnel_name=$2
    local response
    if ! response=$(cloudflare_rest_call GET "accounts/$account_id/cfd_tunnel"); then
        return 1
    fi
    local tunnel=$(echo "$response" | jq -r --arg name "$tunnel_name" 'limit(1; .result[] | select(.name == $name and ((.deleted_at // "") == "")))')
    if [[ -z "$tunnel" || "$tunnel" = "null" ]]; then
        echo ""
    else
        echo "$tunnel"
    fi
}

cloudflare_create_tunnel() {
    local account_id=$1
    local tunnel_name=$2
    local body=$(jq -n --arg name "$tunnel_name" '{"name": $name, "config_src": "cloudflare"}')
    local response
    if ! response=$(cloudflare_rest_call POST "accounts/$account_id/cfd_tunnel" "$body"); then
        return 1
    fi
    local tunnel=$(echo "$response" | jq '.result')
    if [[ -z "$tunnel" || "$tunnel" = "null" ]]; then
        log_error "Failed to create cloudflared tunnel"
        return 1
    fi
    echo "$tunnel"
}

cloudflare_get_tunnel_token() {
    local account_id=$1
    local tunnel_id=$2
    local response
    if ! response=$(cloudflare_rest_call GET "accounts/$account_id/cfd_tunnel/$tunnel_id/token"); then
        return 1
    fi
    local secret=$(echo "$response" | jq -r '.result')
    if [[ -z "$secret" || "$secret" = "null" ]]; then
        log_error "Failed to retrieve cloudflare tunnel token"
        return 1
    fi
    echo "$secret"
}

################################################################################
#                            TAILSCALE API CLIENT

# Makes a request to Tailscale API
# Params:   $1 HTTP Method
#           $2 API Path
#           $3 Request body [Optional]
# Returns:  Body of the response
tailscale_rest_call() {
    local response
    if ! response=$(rest_call $1 "$TAILSCALE_API_BASE_URL/$2" "Authorization: Bearer ${TAILSCALE_API_KEY}" "$3"); then
        return 1
    fi
    echo "$response"
}

tailscale_create_auth_key() {
    local response
    body='{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":false,"preauthorized":true}}},"expirySeconds":120}'
    if ! response=$(tailscale_rest_call "POST" "tailnet/-/keys" "$body"); then
        return 1
    fi
    local key
    if ! key=$(echo "$response" | jq -r '.key') || [ -z "$key" ]; then
        log_error "Failed to retrieve key from server response"
        return 1
    fi
    echo "$key"
}

tailscale_find_device() {
    local ip=$1
    local response
    if ! response=$(tailscale_rest_call "GET" tailnet/-/devices); then
        return 1
    fi
    echo "$response" | jq --arg ip "$ip" '.devices[] | select(.addresses[] == $ip)'
}

tailscale_disable_key_expiration() {
    local device_id=$1
    local body='{"keyExpiryDisabled":true}'
    tailscale_rest_call POST "device/${device_id}/key" "$body"
    if [ $? -ne 0 ]; then
        return 1
    fi
}

# Makes sure a given path exist, if not, it is created with $USER:docker ownership
ensure_path_exists() {
    if [ ! -d "$1" ]; then
        if ! { 
            sudo mkdir -p "$1" && 
            sudo chown $USER:docker "$1" 
        }; then
            log_error "Failed to create path $1"
            exit 1
        fi
    fi
}

################################################################################
#                            CONFIGURATION STEPS

# Create the application data folder (which is mounted into Docker)
create_data_locations() {
    ensure_path_exists "$APPDATA_LOCATION"
    SECRETS_PATH="${APPDATA_LOCATION%/}/secrets/"
    ensure_path_exists "$SECRETS_PATH"
    ensure_path_exists "$IMMICH_UPLOAD_LOCATION"
}

# Download the default application data files
download_appdata() {
    local appdata_files=(
        "${APPDATA_LOCATION%/}/authelia/configuration.yml"
        "${APPDATA_LOCATION%/}/lldap/bootstrap/group-configs/immich_user.json"
        "${APPDATA_LOCATION%/}/lldap/bootstrap/group-configs/nextcloud_user.json"
        "${APPDATA_LOCATION%/}/lldap/bootstrap/group-configs/server_admin.json"
        "${APPDATA_LOCATION%/}/lldap/bootstrap/user-configs/authelia.json"
        "${APPDATA_LOCATION%/}/traefik/dynamic-config.yml"
        "${APPDATA_LOCATION%/}/traefik/traefik.yml"
    )
    local missing_files=false
    for path in "${appdata_files[@]}"; do
        if [ ! -f "$path" ] || [ ! -s "$path" ]; then
            echo -e "File ${Cyan}$path${COff} is missing or empty."
            missing_files=true
        fi
    done
    if [ "$missing_files" != true ]; then
        return 0
    fi
    local user_input
    echo
    read -p "Do you want to download the missing configuration files? [Y/n] " user_input </dev/tty
    echo
    user_input=${user_input:-Y}
    if [[ "$user_input" =~ ^[Yy]$ ]]; then
        echo -e "Downloading appdata from ${Cyan}$GH_IO_APPDATA_URL${COff} ...\n"
        curl -fsSL $GH_IO_APPDATA_URL \
            | sudo busybox unzip -n - -d "$APPDATA_LOCATION" 2>&1 \
            | grep -E "creating:|inflating:" \
            | awk -F': ' '{print $2}' \
            | while read -r path; do
                echo -e "Changing owner of: ${Purple}${APPDATA_LOCATION%/}/$path${COff}"
                sudo chown $USER:docker "${APPDATA_LOCATION%/}/$path"
              done
        if [ $? -ne 0 ]; then
            return 1
        fi
    else
        abort_install
        return 1
    fi
}

# Ask for any variables that aren't yet defined in the .env file
ask_for_variables() {
    # Global Settings

    if [ -n "$APPDATA_OVERRIDE" ]; then
        save_env APPDATA_LOCATION "${APPDATA_OVERRIDE%/}"
    else
        ask_for_env APPDATA_LOCATION "Application Data folder"
    fi
    ask_for_env TZ "Server Timezone"
    ask_for_env CERT_ACME_EMAIL "Email For Certificate Registration"

    # Tailscale Settings

    ask_for_env TAILSCALE_API_KEY "Tailscale API Key"

    # Cloudflare Settings

    ask_for_env CF_DNS_API_TOKEN "Cloudflare DNS API Token"
    ask_for_env CF_DOMAIN_NAME "Domain Name (e.g. example.com)"
    save_env CF_DOMAIN_CN "\"$(echo "$CF_DOMAIN_NAME" | sed 's/^/dc=/' | sed 's/\./,dc=/g')\""
    ask_for_env CF_TUNNEL_NAME "Cloudflare Tunnel Name"

    # SMTP Server Settings

    ask_for_env SMTP2GO_API_KEY "SMTP2GO API Key"
    if [ -z "$SMTP_SENDER" ]; then
        save_env SMTP_SENDER "noreply@${CF_DOMAIN_NAME}"
    fi
    ask_for_env SMTP_SENDER "SMTP Email From"
    if [ "$USE_SMTP2GO" != "true" ]; then
        ask_for_env SMTP_USERNAME "SMTP Server Username"
        ask_for_env SMTP_PASSWORD "SMTP Server Password"
        ask_for_env SMTP_SERVER "SMTP Server Address"
        ask_for_env SMTP_PORT "SMTP Server Port"
        ask_for_env SMTP_SECURE "SMTP Security Protocol (optional) ('tls' or 'ssl')" true false
    else
        if [ -z "$SMTP_USERNAME" ]; then
            save_env SMTP_USERNAME "selfhost@${CF_DOMAIN_NAME}"
        fi
        ask_for_env SMTP_USERNAME "SMTP Server Username"
    fi

    # Authelia Settings

    ask_for_env AUTHELIA_THEME "Authelia admin website theme (dark | light)"

    # LLDAP Settings

    ask_for_env LLDAP_ADMIN_PASSWORD "LLDAP Administrator Password" true true true

    # Portainer Settings

    ask_for_env PORTAINER_ADMIN_PASSWORD "Portainer Administrator Password" true true true

    # Immich Settings

    ask_for_env IMMICH_VERSION "Version of Immich to install"
    ask_for_env IMMICH_SUBDOMAIN "Subdomain under ${CF_DOMAIN_NAME} to use for Immich"
    ask_for_env IMMICH_UPLOAD_LOCATION "Immich photo upload location"
    ask_for_env IMMICH_DEFAULT_QUOTA "Immich default user storage quota (in GB)"

    # Nextcloud Settings

    ask_for_env NEXTCLOUD_VERSION "Version of Nextcloud to install"
    ask_for_env NEXTCLOUD_SUBDOMAIN "Subdomain under ${CF_DOMAIN_NAME} to use for Nextcloud"
    ask_for_env NEXTCLOUD_DATA_LOCATION "Nextcloud document storage location"
}

# Create any missing secret files
save_secrets() {
    save_env_id OIDC_IMMICH_CLIENT_ID
    save_env_id OIDC_GRAFANA_CLIENT_ID
    save_env_id OIDC_NEXTCLOUD_CLIENT_ID
    save_env_secret "${SECRETS_PATH}cloudflare_dns_api_token" CF_DNS_API_TOKEN
    save_env_secret "${SECRETS_PATH}smtp_password" SMTP_PASSWORD
    save_env_secret "${SECRETS_PATH}ldap_admin_password" LLDAP_ADMIN_PASSWORD
    save_env_secret "${SECRETS_PATH}portainer_admin_password" PORTAINER_ADMIN_PASSWORD
    create_secret "${SECRETS_PATH}authelia_session_secret"
    create_secret "${SECRETS_PATH}authelia_storage_encryption_key"
    create_secret "${SECRETS_PATH}ldap_jwt_secret"
    create_secret "${SECRETS_PATH}ldap_key_seed"
    create_secret "${SECRETS_PATH}ldap_authelia_password"
    create_secret "${SECRETS_PATH}oidc_hmac_secret"
    create_secret "${SECRETS_PATH}immich_db_password"
    create_secret "${SECRETS_PATH}nextcloud_db_root_password"
    create_secret "${SECRETS_PATH}nextcloud_db_password"
    create_password_digest_pair "${SECRETS_PATH}oidc_immich"
    create_password_digest_pair "${SECRETS_PATH}oidc_nextcloud"
    create_password_digest_pair "${SECRETS_PATH}oidc_grafana"
    create_rsa_keypair "${SECRETS_PATH}oidc_jwks_key" "${SECRETS_PATH}oidc_jwks_public"
    if [ $? -ne 0 ]; then
        return 1
    fi
    chmod 644 "${SECRETS_PATH}"*
    if [ $? -ne 0 ]; then
        return 1
    fi
}

# Create the necessary DNS records as specified by SMTP2GO
# Params:   $1 Domain object as returned by SMTP2GO API
configure_smtp_domain_records() {
    local domain_obj=$1
    local zone_id
    if ! zone_id=$(cloudflare_get_zone_id "$CF_DOMAIN_NAME"); then
        exit 1
    fi
    local name=$(echo "$domain_obj" | jq -r '.domain.dkim_selector')
    local content=$(echo "$domain_obj" | jq -r '.domain.dkim_expected')
    if [ -z "$name" ] || [ -z "$content" ]; then
        log_error "Could not find DNS record name or content for DKIM"
        exit 1
    fi
    cloudflare_add_or_update_record $zone_id "CNAME" "$name._domainkey.$CF_DOMAIN_NAME" $content
    name=$(echo "$domain_obj" | jq -r '.domain.rpath_selector')
    content=$(echo "$domain_obj" | jq -r '.domain.rpath_expected')
    if [ -z "$name" ] || [ -z "$content" ]; then
        log_error "Could not find DNS record name or content for Return Path"
        exit 1
    fi
    cloudflare_add_or_update_record $zone_id "CNAME" $name.$CF_DOMAIN_NAME $content
    name=$(echo "$domain_obj" | jq -r '.trackers[0].subdomain')
    content=$(echo "$domain_obj" | jq -r '.trackers[0].cname_expected')
    if [ -z "$name" ] || [ -z "$content" ]; then
        log_error "Could not find DNS record name or content for Link"
        exit 1
    fi
    cloudflare_add_or_update_record $zone_id "CNAME" $name.$CF_DOMAIN_NAME $content
}

# Configure the domain and validate it has been verified by SMTP2GO to send emails
configure_smtp_domain() {
    local user_input
    if [ "$SMTP2GO_DOMAIN_VALIDATED" = "true" ]; then
        echo "Domain has been previously verified."
        if [ "$RESUME" = "true" ]; then return 0; fi
        read -p "Do you want to revalidate the domain configuration? [y/N]" user_input </dev/tty
        user_input=${user_input:-N}
        if [[ ! "$user_input" =~ ^[Yy]$ ]]; then return 0; fi
    fi
    if [ -z "$CF_DOMAIN_NAME" ] || [ -z "$CF_DNS_API_TOKEN" ] || [ -z "$SMTP2GO_API_KEY" ]; then
        log_error "Error: Please set CF_DOMAIN_NAME, CF_DNS_API_TOKEN and SMTP2GO_API_KEY values in the '$ENV_FILE' file."
        exit 1
    fi
    local response
    if ! response=$(smtp2go_rest_call POST domain/view); then
        exit 1
    fi
    local domain=$(echo "$response" | jq -r --arg domain "$CF_DOMAIN_NAME" '.data.domains[] | select(.domain.fulldomain == $domain)')
    if [ -z "$domain" ]; then
        if ! domain=$(smtp2go_add_domain "$CF_DOMAIN_NAME"); then
            exit 1
        fi
    fi
    local dkim=$(echo "$domain" | jq -r '.domain.dkim_verified')
    local return_path=$(echo "$domain" | jq -r '.domain.rpath_verified')
    local link=$(echo "$domain" | jq -r '.trackers[0].cname_verified')
    if [ "$dkim" = "true" ] && [ "$return_path" = "true" ]; then
        echo -e "Domain ${UPurple}$CF_DOMAIN_NAME${COff} is fully verified"
    else
        echo -e "Domain ${UPurple}$CF_DOMAIN_NAME${COff} is not fully verified"
        configure_smtp_domain_records "$domain"
        if [ $? -ne 0 ]; then
            return 1
        fi
        smtp2go_validate_domain $CF_DOMAIN_NAME
        if [ $? -ne 0 ]; then
            exit 1
        fi
    fi
    save_env SMTP2GO_DOMAIN_VALIDATED "true"
}

# Create a user that can send mail through SMTP2GO and save the credentials
configure_smtp_user() {
    if [ -n "$SMTP_PASSWORD" ]; then
        echo "SMTP2GO user appears to already be configured."
        if [ "$RESUME" = "true" ]; then return 0; fi
        read -p "Do you want to validate or re-create the user with SMTP2GO? [y/N] " user_input </dev/tty
        user_input=${user_input:-N}
        if [[ ! "$user_input" =~ ^[Yy]$ ]]; then return 0; fi
    fi
    if [ -z "$SMTP_USERNAME" ] || [ -z "$SMTP2GO_API_KEY" ]; then
        log_error "Please set SMTP_USERNAME and SMTP2GO_API_KEY values in the '$ENV_FILE' file."
        exit 1
    fi
    local username="$SMTP_USERNAME"
    local response
    if ! response=$(smtp2go_rest_call POST users/smtp/view); then
        exit 1
    fi
    local user=$(echo "$response" | jq -r --arg username "$username" '.data.results[] | select(.username == $username)')
    if [ -z "$user" ]; then
        echo "User ${Purple}$username${COff} does not exist in SMTP2GO account. Creating user..."
        if ! user=$(smtp2go_add_user $username); then
            exit 1
        fi
    fi
    local password=$(echo "$user" | jq -r '.email_password')
    save_env SMTP_PASSWORD "${password}"
}

# Use the cloudflare CLI to create a tunnel
# TBD: Switch to using the API instead
configure_cloudflare_tunnel() {
    if [ -z "$CF_TUNNEL_NAME" ]; then
        log_error "Please specify a value for 'CF_TUNNEL_NAME' in the '$ENV_FILE' file."
        exit 1
    fi
    local user_input
    local token_file=${SECRETS_PATH}cloudflare_tunnel_token
    if [ -n "$CF_TUNNEL_ID" ] && [ -f "$token_file" ]; then
        echo "Cloudflare tunnel appears to be already configured." >&2
        if [ "$RESUME" = "true" ]; then return 0; fi
        read -p "Do you want to reconfigure the Cloudflare tunnel information? [y/N] " user_input </dev/tty
        user_input=${user_input:-N}
        if [[ ! "$user_input" =~ ^[Yy]$ ]]; then return 0; fi
    fi
    local account_id
    if ! account_id=$(cloudflare_get_account_id); then
        exit 1
    fi
    local tunnel=$(cloudflare_get_tunnel "$account_id" "$CF_TUNNEL_NAME")
    if [ -z "$tunnel" ]; then
        echo -e "Cloudflare tunnel ${Purple}$CF_TUNNEL_NAME${COff} does not exist. Creating one..."
        if ! tunnel=$(cloudflare_create_tunnel "$account_id" "$CF_TUNNEL_NAME"); then
            exit 1
        fi
    else
        echo -e "Cloudflare tunnel ${Purple}$CF_TUNNEL_NAME${COff} already exists."
    fi
    local tunnel_id=$(echo "$tunnel" | jq -r '.id')
    local token
    if ! token=$(cloudflare_get_tunnel_token "$account_id" "$tunnel_id"); then
        exit 1
    fi
    save_env "CF_TUNNEL_ID" "$tunnel_id"
    echo -e "Saving tunnel credentials to ${Cyan}$token_file${COff}..."
    printf "%s" "$token" >"$token_file"
}

# Check that Tailscale is installed and started
check_tailscale() {
    if ! command -v tailscale >/dev/null 2>&1; then
        echo -e "\n${Yellow}Tailscale is not installed.${COff}"
        read -p "Do you want to install tailscale? [Y/n] " user_input </dev/tty
        user_input=${user_input:-Y}
        if [[ "$user_input" =~ ^[Yy]$ ]]; then
            echo "Installing tailscale..."
            if ! curl -fsSL https://tailscale.com/install.sh | sh >/dev/null; then
                log_error "Failed to install tailscale"
                exit 1
            else
                echo -e "\n✅ Tailscale installation completed successfully\n"
            fi
        else
            abort_install
        fi
    fi
}

# Connect to tailscale
connect_tailscale() {
    if tailscale status >/dev/null 2>&1; then return 0; fi
    local connected=false
    echo "Connecting to Tailscale..."
    local up_params=""
    if [ -n "$TAILSCALE_API_KEY" ]; then
        local auth_key
        if ! auth_key=$(tailscale_create_auth_key); then
            exit 1
        fi
        up_params="$up_params --auth-key=$auth_key"
    fi
    sudo tailscale up $up_params
    if [ $? -ne 0 ]; then
        log_error "Failed to initiate tailscale connection."
        exit 1
    fi
    for i in {1..15}; do
        if tailscale status >/dev/null 2>&1; then
            connected=true
            break
        fi
        sleep 1
    done
    if [ ! "$connected" = true ]; then
        log_error "Failed to connect Tailscale."
        exit 1
    fi
}

# Extract the tailscale IP
configure_tailscale() {
    check_tailscale
    if [ $? -ne 0 ]; then
        return 1
    fi
    connect_tailscale
    if [ $? -ne 0 ]; then
        return 1
    fi
    sudo systemctl enable --now tailscaled
    if [ $? -ne 0 ]; then
        log_error "Failed to enable tailscale auto-start"
        exit 1
    fi
    local tailscale_ip=$(tailscale ip -4)
    if [ -z "$tailscale_ip" ]; then
        log_error "Failed to detect the Tailnet IP"
        exit 1
    fi
    echo "Tailscale is connected."
    if [[ -z "$TAILSCALE_IP" && -n "$TAILSCALE_API_KEY" ]]; then
        local device
        if ! device=$(tailscale_find_device $tailscale_ip) || [ -z "$device" ]; then
            log_error "Failed to find tailscale device with address: $tailscale_ip"
            exit 1
        fi
        local device_id
        if ! device_id=$(echo $device | jq -r '.id'); then
            log_error "Could not extract id for tailscale device $device"
            exit 1
        fi
        tailscale_disable_key_expiration "$device_id" >/dev/null
        if [ $? -ne 0 ]; then
            exit 1
        fi
        echo -e "Key expiration disabled for ${Cyan}$tailscale_ip${COff}"
    fi
    save_env TAILSCALE_IP "$tailscale_ip"
}

# Check that Docker is installed
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "\n${Yellow}Docker is not installed.${COff}"
        read -p "Do you want to install Docker? [Y/n] " user_input </dev/tty
        user_input=${user_input:-Y}
        if [[ "$user_input" =~ ^[Yy]$ ]]; then
            echo "Installing Docker..."
            if ! curl -fsSL https://get.docker.com | sudo sh; then
                log_error "Docker installation failed"
                exit 1
            else
                echo -e "\n✅ Docker installation completed successfully\n"
            fi
            sudo systemctl enable --now docker > /dev/null
            if ! getent group docker > /dev/null 2>&1; then
                sudo groupadd docker > /dev/null
            fi
            sudo usermod -aG docker $USER > /dev/null
        else
            abort_install
            exit 1
        fi
    fi
}

# Create docker resources needed for deployment
configure_docker() {
    check_docker
    if [ $? -ne 0 ]; then
        return 1
    fi
    ask_for_env DOCKER_NETWORK "Docker network"
    if ! sg docker -c "docker network inspect '${DOCKER_NETWORK}'" >/dev/null 2>&1; then
        echo -e "Docker network ${Cyan}$DOCKER_NETWORK${COff} does not exist. Creating it with default settings..."
        sg docker -c "docker network create '$DOCKER_NETWORK'" > /dev/null
    else
        echo -e "Docker network ${Cyan}$DOCKER_NETWORK${COff} already exists."
    fi
}

# Check that the ENV file is current with the remote version
prepare_env_file() {
    local remote_env="$GH_RAW_PROJECT_URL/.env"
    local user_input merge_with
    if [ -f "$ENV_FILE" ]; then
        echo -e "File ${Cyan}$ENV_FILE${COff} already exists."
        local missing_keys=false
        while IFS='=' read -r key value; do
            if [ -n "$key" ]; then
                if ! grep -q "^${key}=" "$ENV_FILE"; then
                    echo -e "Key ${Purple}$key${COff} not found in ${Cyan}$ENV_FILE${COff}"
                    missing_keys=true
                fi
            fi
        done < <(curl -fsSL "$remote_env" | grep -v '^[[:space:]]*#')
        if [ "$missing_keys" != true ]; then return 0; fi
        local key value 
        echo -e "\nOne or more keys are missing from ${Cyan}$ENV_FILE${Coff}."
        read -p "Do you want to merge '$ENV_FILE' with the version that is available online? [Y/n] " user_input </dev/tty
        user_input=${user_input:-Y}
        if [[ ! "$user_input" =~ ^[Yy]$ ]]; then 
            abort_install
        fi
        merge_with="$ENV_FILE.bak"
        mv "$ENV_FILE" "$merge_with"
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    curl -fsSL -o "$ENV_FILE" "$remote_env"
    if [ $? -ne 0 ]; then
        return 1
    fi
    if [ -n "$merge_with" ]; then
        grep -v '^[[:space:]]*#' "$merge_with" | while IFS='=' read -r key value; do
            if [ -n "$key" ] && [ -n "$value" ]; then
                if grep -q "^${key}=" "$ENV_FILE"; then
                    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
                    echo -e "Updated ${Purple}$key${COff} in ${Cyan}$ENV_FILE${COff}."
                fi
            fi
        done
    fi
}

# Check that the docker compose project file is present
prepare_docker_compose() {
    local suffix=$1
    local user_input
    local compose_file="docker-compose${suffix}.yml"
    if [ -f "$compose_file" ]; then
        echo -e "File ${Cyan}$compose_file${COff} already exists."
        if [ "$RESUME" = "true" ]; then return 0; fi
        read -p "Do you want to replace '$compose_file' with the version that is available online? [y/N] " user_input </dev/tty
        user_input=${user_input:-N}
        if [[ ! "$user_input" =~ ^[Yy]$ ]]; then return 0; fi
    fi
    curl -fsSL -o "$compose_file" "$GH_RAW_PROJECT_URL/${compose_file}"
    if [ $? -ne 0 ]; then
        return 1
    fi
    echo -e "File ${Cyan}$compose_file${COff} created."
}

# Deploy services via docker compose
deploy_project() {
    local user_input
    echo -en "Project ${Purple}$COMPOSE_PROJECT${COff} is ready for deployment. "
    read -p "Do you want to proceed? [Y/n] " user_input </dev/tty
    user_input=${user_input:-Y}
    if [[ ! "$user_input" =~ ^[Yy]$ ]]; then
        abort_install
    fi
    local compose_options="-p '$COMPOSE_PROJECT' --env-file '$ENV_FILE' $COMPOSE_OPTIONS"
    local compose_up_options="-d -y --remove-orphans --quiet-pull $COMPOSE_UP_OPTIONS"
    sg docker -c "docker compose $compose_options up $compose_up_options"
    if [ $? -ne 0 ]; then
        return 1
    fi
}

# Create the users and groups needed to run the applications
bootstrap_lldap() {
    if [[ ! -s "${SECRETS_PATH}ldap_authelia_password" ]]; then
        log_error "Missing secret files. Make sure to deploy project before running bootstrap."
        exit 1
    fi
    # Paste the generated secret for Authelia's LLDAP password into the bootstrap user file
    local authelia_password=$(<"${SECRETS_PATH}ldap_authelia_password")
    local authelia_file="${APPDATA_LOCATION%/}/lldap/bootstrap/user-configs/authelia.json"
    local authelia_json=$(jq --arg password "$authelia_password" '.password = $password' "$authelia_file")
    echo "$authelia_json" > "$authelia_file"
    # Run LLDAP's built-in bootstrap script to create/update users and groups
    echo "Bootstrapping LLDAP with pre-configured users and groups..."
    sg docker -c "docker exec -e LLDAP_ADMIN_PASSWORD_FILE=/run/secrets/ldap_admin_password -e USER_CONFIGS_DIR=/data/bootstrap/user-configs -e GROUP_CONFIGS_DIR=/data/bootstrap/group-configs -it lldap ./bootstrap.sh"
    if [ $? -ne 0 ]; then
        log_error "Failed to bootstrap LLDAP users and groups"
        return 1
    fi
    # Restart Authelia so it can connect to LLDAP with the updated user information
    echo -e "\nRestarting Authelia container..."
    sg docker -c "docker restart authelia"
    if [ $? -ne 0 ]; then
        log_error "Failed to restart Authelia container"
        return 1
    fi
}

# Create a string of '*' characters with the same length as the input
mask_password() {
    local input="$1"
    local len=${#input}
    printf "%${len}s" "" | tr ' ' '*'
}

# Asks user for input
# Params:   $1 The prompt to display
#           $2 The default value if user does not enter a value
#           $3 If `true`, keep asking user for value until not empty
#           $4 The options to show in between square braces []
#           $5 If `true` value will be treated as a secret (***)
# Returns:  The value entered by the user
ask_value() {
    local prompt="$1"
    local default="$2"
    local required=${3:-false}
    local display="${4:-${default}}"
    local masked=${5:-false}
    local user_input
    while true; do
        if [ "$masked" = "true" ]; then 
            display=$(mask_password "$display")
        fi
        if [[ -n "$display" ]]; then
            read $( [ "$masked" = true ] && echo "-s" ) -p "$prompt [${display}]: " user_input </dev/tty
        else
            read $( [ "$masked" = true ] && echo "-s" ) -p "$prompt: " user_input </dev/tty
        fi
        if [ "$masked" = true ]; then echo >&2; fi
        user_input=${user_input:-${default}}
        if [[ -n "$user_input" || "$required" != "true" ]]; then
            break
        fi
        echo -e "\n${Yellow}Empty value is not allowed. Please try again.${COff}\n" >&2
    done
    echo "$user_input"
}

# Create the file needed by LLDAP to bootstrap an account. Account will be given server-admin permissions
configure_admin_account() {
    local config_file="${APPDATA_LOCATION%/}/lldap/bootstrap/user-configs/admin.json"
    local username email password
    
    # Read the values from file (if it exists)
    if [[ -f "$config_file" ]]; then
        username=$(jq -r '.id' "$config_file")
        email=$(jq -r '.email' "$config_file")
        password=$(jq -r '.password' "$config_file")
    fi

    # If already configured and the --resume flag was specified, skip the rest
    if [[ -n "$username" && -n "$email" && -n "$password" && "$RESUME" = "true" ]]; then return 0; fi

    echo -e "Configuring the user account for the server administrator...\n" 

    username=$(ask_value "Username" "$username" true)
    email=$(ask_value "Email address" "$email" true)
    password=$(ask_value "Password" "$password" true "$password" true)

    echo -e "\nGenerating user configuration file ${Purple}$config_file${COff}\n"

    local json=$( [ -s "$config_file" ] && cat "$config_file" || echo "{}" )
    echo "$(echo $json | jq --arg id "$username" --arg email "$email" --arg password "$password" '.id = $id | .email = $email | .password = $password')" > "$config_file"
    if [ $? -ne 0 ]; then
        return 1
    fi
}

bootstrap_immich() {
    if [[ -z "$CF_DOMAIN_NAME" || \
          -z "$OIDC_IMMICH_CLIENT_ID" || \
          -z "$SMTP_SENDER" || \
          -z "$SMTP_SERVER" || \
          -z "$SMTP_PORT" || \
          -z "$SMTP_USERNAME" || \
          -z "$SMTP_PASSWORD" || \
          -z "$SMTP_PASSWORD" || \
          ! -s "${SECRETS_PATH}oidc_immich_password" ]]; then
        log_error "Missing values in .env file. Make sure to deploy project before running bootstrap."
        exit 1
    fi

    IMMICH_BASE_URL="https://${IMMICH_SUBDOMAIN}.${CF_DOMAIN_NAME}"

    if [[ -z "$IMMICH_API_KEY" || "$RESUME" != "true" ]]; then

        echo -e "\nYour Immich server address is: ${UCyan}${IMMICH_BASE_URL}${COff}"
        echo -e "\nTo get an API Key, sign in and go to ${Purple}Account Settings${COff} and look for ${Purple}API Keys${COff}."
        echo -e "\n${UYellow}You MUST use the same username and password provided for the server administrator.${COff}\n"

        ask_for_env IMMICH_API_KEY "API Key for Immich"
    fi

    echo "Fetching current Immich server configuration..."
    
    local immich_config
    if ! immich_config=$(immich_get_config); then
        exit 1
    fi

    local client_secret=$(<"${SECRETS_PATH}oidc_immich_password")

    if ! immich_config=$(echo "$immich_config" | jq \
        --arg clientId "$OIDC_IMMICH_CLIENT_ID" \
        --arg clientSecret "$client_secret" \
        --argjson storageQuota "$IMMICH_DEFAULT_QUOTA" \
        --arg externalDomain "https://${IMMICH_SUBDOMAIN}.${CF_DOMAIN_NAME}" \
        --arg smtpFrom "$SMTP_SENDER" \
        --arg smtpServer "$SMTP_SERVER" \
        --argjson smtpPort "$SMTP_PORT" \
        --arg smtpUsername "$SMTP_USERNAME" \
        --arg smtpPassword "$SMTP_PASSWORD" \
        --arg issuerUrl "https://authelia.${CF_DOMAIN_NAME}/.well-known/openid-configuration" '
        .oauth.enabled = true |
        .oauth.autoLaunch = true |
        .oauth.autoRegister = true |
        .oauth.buttonText = "Login" |
        .oauth.clientId = $clientId |
        .oauth.clientSecret = $clientSecret |
        .oauth.defaultStorageQuota = $storageQuota |
        .oauth.issuerUrl = $issuerUrl |
        .passwordLogin.enabled = false |
        .server.externalDomain = $externalDomain |
        .notifications.smtp.enabled = true |
        .notifications.smtp.from = $smtpFrom |
        .notifications.smtp.transport.host = $smtpServer |
        .notifications.smtp.transport.port = $smtpPort |
        .notifications.smtp.transport.username = $smtpUsername |
        .notifications.smtp.transport.password = $smtpPassword
    '); then
        log_error "Failed to generate Immich config json"
        exit 1
    fi

    echo "Saving updated Immich server configuration..."

    immich_update_config "$immich_config" >/dev/null
    if [ $? -ne 0 ]; then
        return 1
    fi
}

get_resume_command() {
    echo -n "bash $0 --resume"
    if [ -n "$RUN_BOOTSTRAP" = "true" ]; then echo -n " --bootstrap"; fi
    if [ -n "$APPDATA_OVERRIDE" ]; then echo -n " --appdata \"$APPDATA_OVERRIDE\""; fi
    if [ "$ENV_FILE" != ".env" ]; then echo -n " --env \"$ENV_FILE\""; fi
    if [ "$USE_SMTP2GO" = "false" ]; then echo -n " --custom-smtp"; fi
}

# Terminate program and print instructions on how to invoke again to resume
abort_install() {
    log_warn "Setup aborted by user."
    echo -e "To resume, run: ${BIGreen}$(get_resume_command)${COff}\n"
    exit 1
}

# If the user aborts with CTRL+C, print instructions on how to resume installation
trap "echo && abort_install" SIGINT

print_usage() {
    echo "Usage: $0 [--appdata <path>] [--env <file>]"
    echo ""
    echo "Options:"
    echo "  --appdata <path>    Application data for deployment. [Default: '/srv/appdata']"
    echo "  --bootstrap         Run initial configuration of self-hosted apps."
    echo "  --env <path>        Environment file to read variables from. [Default: './env']"
    echo "  --project <name>    Name to use for the Docker Compose project. [Default: 'self-host']"
    echo "  --custom-smtp       Do not use SMTP2GO for sending email, provide custom SMTP configuration."
    echo "  --resume            Skip any steps that have been previously completed."
    echo "  --dry-run           Execute Docker Compose in dry run mode."
    echo "  -h, --help          Display this help message."
    exit 1
}

APPDATA_OVERRIDE=
SECRETS_PATH=
USE_SMTP2GO=true
RUN_BOOTSTRAP=
RESUME=false
ENV_FILE=.env
COMPOSE_PROJECT=self-host
COMPOSE_OPTIONS="-f docker-compose.yml -f docker-compose-immich.yml -f docker-compose-nextcloud.yml"
COMPOSE_UP_OPTIONS=

################################################################################
#                           PARSE COMMAND LINE

while [ "$#" -gt 0 ]; do
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    --appdata)
        if [ -n "$2" ]; then
            APPDATA_OVERRIDE="$2"
            shift 2
            continue
        else
            echo "Error: --appdata requires a directory path."
            exit 1
        fi
        ;;
    --custom-smtp)
        USE_SMTP2GO=false
        shift 1
        continue
        ;;
    --bootstrap)
        RUN_BOOTSTRAP=true
        shift 1
        continue
        ;;
    --dry-run)
        COMPOSE_UP_OPTIONS="$COMPOSE_UP_OPTIONS --dry-run"
        shift 1
        continue
        ;;
    --resume)
        RESUME=true
        shift 1
        continue
        ;;
    --env)
        if [ -n "$2" ]; then
            ENV_FILE="$2"
            shift 2
            continue
        else
            echo "Error: --env requires a file path."
            exit 1
        fi
        ;;
    --project)
        if [ -n "$2" ]; then
            COMPOSE_PROJECT="$2"
            shift 2
            continue
        else
            echo "Error: --project requires a name."
            exit 1
        fi
        ;;
    -h | --help)
        print_usage
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

################################################################################
#                           MAIN PROGRAM LOGIC

if [ "$RUN_BOOTSTRAP" = "true" ]; then
    source "$ENV_FILE"

    SECRETS_PATH="${APPDATA_LOCATION}/secrets/"

    log_header "Bootstrapping LLDP user and group identities"

    configure_admin_account
    if [ $? -ne 0 ]; then
        log_error "Failed to configure the server administrator account."
        exit 1
    fi

    bootstrap_lldap
    if [ $? -ne 0 ]; then
        log_error "Failed to bootstrap LLDAP."
        exit 1
    fi

    log_header "Bootstrapping Immich configuration"

    bootstrap_immich
    if [ $? -ne 0 ]; then
        log_error "Failed to bootstrap Immich."
        exit 1
    fi

    log_done
    exit 0
fi

log_header "Preparing deployment files"

prepare_env_file
if [ $? -ne 0 ]; then
    log_error "Failed to prepare '$ENV_FILE'."
    exit 1
fi

source "$ENV_FILE"

prepare_docker_compose
if [ $? -ne 0 ]; then
    log_error "Failed to prepare 'docker-compose.yml'."
    exit 1
fi

prepare_docker_compose "-immich"
if [ $? -ne 0 ]; then
    log_error "Failed to prepare 'docker-compose-immich.yml'."
    exit 1
fi

ask_for_variables
if [ $? -ne 0 ]; then
    log_error "Failed to configure '$ENV_FILE' with configuration values."
    exit 1
fi

log_header "Configuring Docker"

configure_docker
if [ $? -ne 0 ]; then
    log_error "Docker configuration failed."
    exit 1
fi

log_header "Preparing application data folder"

create_data_locations
if [ $? -ne 0 ]; then
    log_error "Could not create data folders."
    exit 1
fi

download_appdata
if [ $? -ne 0 ]; then
    log_error "Could not download application data."
    exit 1
fi

log_header "Configuring Tailscale"

configure_tailscale
if [ $? -ne 0 ]; then
    log_error "Tailscale configuration failed."
    exit 1
fi

log_header "Configuring CloudFlare Tunnel"

configure_cloudflare_tunnel
if [ $? -ne 0 ]; then
    log_error "Cloudflare tunnel configuration failed."
    exit 1
fi

if [ "$USE_SMTP2GO" = "true" ]; then

    log_header "Configuring SMTP2GO Account"

    configure_smtp_domain
    if [ $? -ne 0 ]; then
        log_error "SMTP domain configuration failed."
        exit 1
    fi

    configure_smtp_user
    if [ $? -ne 0 ]; then
        log_error "SMTP user configuration failed."
        exit 1
    fi

    save_env SMTP_SERVER mail.smtp2go.com
    save_env SMTP_PORT "587"
    save_env SMTP_SECURE "tls"
fi

log_header "Preparing secret files"

save_secrets
if [ $? -ne 0 ]; then
    log_error "Failed to save secret files."
    exit 1
fi

log_header "Deploying services"

deploy_project
if [ $? -ne 0 ]; then
    log_error "Failed to deploy project with docker compose."
    exit 1
fi