#!/bin/bash
#
# Library name: config
# This is a library that contains functions to assist with docker configs

. "$(pwd)/utils/log.sh"

# Sets the digest variables for the conf raft files in the provided docker compose file
#
# Requirements:
# - All configs must have a file and name property
# - The name property must end in -${DIGEST_VAR_NAME:?err} (eg. name: my-file-${MY_FILE_DIGEST:?err})
#
# Arguments:
# - $1 : docker compose directory path (eg. /home/user/project/docker-compose.yml)
#
# Exports:
# As many digest environment variables as are declared in the provided docker compose file
config::set_config_digests() {
    local -r DOCKER_COMPOSE_PATH="${1:?"FATAL: function 'set_config_digests' is missing a parameter"}"

    # Get configs files and names from yml file
    local -r files=($(yq '.configs."*.*".file' "${DOCKER_COMPOSE_PATH}"))
    local -r names=($(yq '.configs."*.*".name' "${DOCKER_COMPOSE_PATH}"))
    local -r composeFolderPath="${DOCKER_COMPOSE_PATH%/*}"

    for ((i = 0; i < ${#files[@]}; i++)); do
        file=${files[$i]}
        name=${names[$i]}

        fileName="${composeFolderPath}${file//\.\///}" # TODO: Throw an error if the file name is too long to allow for a unique enough digest
        envVarName=$(echo "${name}" | grep -P -o "{.*:?err}" | sed 's/[{}]//g' | sed 's/:?err//g')

        # generate and truncate the digest to conform to the 64 character restriction on docker config names
        envDeclarationCharacters=":?err" # '${:?err}' from setting an env variable
        remainder=$((64 - (${#name} - ${#envVarName} - ${#envDeclarationCharacters})))
        export "${envVarName}"="$(cksum "${fileName}" | awk '{print $1}' | cut -c -${remainder})"
    done
}

# Removes stale docker configs based on the provided docker-compose file
#
# Requirements:
# - All configs must have a file and name property
# - The name property must end in -${DIGEST_VAR_NAME:?err} (eg. name: my-file-${MY_FILE_DIGEST:?err})
#
# Arguments:
# - $1 : docker compose directory path (eg. /home/user/project/docker-compose.yml)
# - $2 : config label (eg. logstash)
config::remove_stale_service_configs() {
    local -r DOCKER_COMPOSE_PATH="${1:?"FATAL: function 'remove_stale_service_configs' is missing a parameter"}"
    local -r CONFIG_LABEL="${2:?"FATAL: function 'remove_stale_service_configs' is missing a parameter"}"

    local -r composeNames=($(yq '.configs."*.*".name' "${DOCKER_COMPOSE_PATH}"))
    local configsToRemove=()

    for composeName in "${composeNames[@]}"; do
        composeNameWithoutEnv=$(echo "${composeName}" | sed 's/-\${.*//g')

        composeNameOccurences=$(for word in "${composeNames[@]}"; do echo "${word}"; done | grep -c "${composeNameWithoutEnv}")
        if [[ $composeNameOccurences -gt "1" ]]; then
            log warn "Warning: Duplicate config name (${composeNameWithoutEnv}) was found in ${DOCKER_COMPOSE_PATH}"
        fi

        raftIds=($(docker config ls -f "label=name=${CONFIG_LABEL}" -f "name=${composeNameWithoutEnv}" --format "{{.ID}}"))
        # Only keep the most recent of all configs with the same name
        if [[ ${#raftIds[@]} -gt 1 ]]; then
            mostRecentRaftId="${raftIds[0]}"
            for ((i = 1; i < ${#raftIds[@]}; i++)); do
                raftId=${raftIds[$i]}
                mostRecentRaftCreatedDate=$(docker config inspect -f "{{.CreatedAt}}" "${mostRecentRaftId}")
                raftCreatedDate=$(docker config inspect -f "{{.CreatedAt}}" "${raftId}")
                if [[ $raftCreatedDate > $mostRecentRaftCreatedDate ]]; then
                    configsToRemove+=("${mostRecentRaftId}")
                    mostRecentRaftId="${raftId}"
                else
                    configsToRemove+=("${raftId}")
                fi
            done
        fi
    done

    if [[ "${#configsToRemove[@]}" -gt 0 ]]; then
        try "docker config rm ${configsToRemove[*]}" "Failed to remove configs: ${configsToRemove[*]}"
    fi
}

# A function that exists in a loop to see how long that loop has run for, providing a warning
# at the time specified in argument $3, and exits with code 124 after the time specified in argument $4.
#
# Arguments:
# - $1 : start time of the timeout check
# - $2 : a message containing reference to the loop that timed out
# - $3 : timeout time in seconds, default is 300 seconds
# - $4 : elapsed time to issue running-for-longer-than-expected warning (in seconds), default is 60 seconds
config::timeout_check() {
    local startTime=$(($1))
    local message=$2
    local exitTime="${3:-300}"
    local warningTime="${4:-60}"

    local timeDiff=$(($(date +%s) - $startTime))
    if [[ $timeDiff -ge $warningTime ]] && [[ $timeDiff -lt $(($warningTime + 1)) ]]; then
        log warn "Warning: Waited $warningTime seconds for $message. This is taking longer than it should..."
    elif [[ $timeDiff -ge $exitTime ]]; then
        log error "Fatal: Waited $exitTime seconds for $message. Exiting..."
        exit 124
    fi
}

# A generic function confirming whether or not a containerized api is reachable
#
# Requirements:
# - The function attempts to start up a helper container using the jembi/await-helper image. It is therefore necessary
#   to specify the docker-compose file to deploy the await-helper container which the await_service_running function
#   relies on. Details on configuring the await-helper can be found at https://github.com/jembi/platform-await-helper.
#
# Arguments:
# - $1 : the service being awaited
# - $2 : path to await-helper compose.yml file (eg. ~/projects/platform/dashboard-visualiser-jsreport/docker-compose.await-helper.yml)
# - $3 : desired number of instances of the awaited-service
# - $4 : (optional) the max time allowed to wait for a service's response, defaults to 300 seconds
# - $5 : (optional) elapsed time to throw a warning, defaults to 60 seconds
config::await_service_running() {
    local -r service_name="${1:?"FATAL: await_service_running function args not correctly set"}"
    local -r await_helper_file_path="${2:?"FATAL: await_service_running function args not correctly set"}"
    local -r service_instances="${3:?"FATAL: await_service_running function args not correctly set"}"
    local -r exit_time="${4:-}"
    local -r warning_time="${5:-}"
    local -r start_time=$(date +%s)

    try "docker stack deploy -c $await_helper_file_path instant" "Failed to deploy await helper"
    until [[ $(docker service ls -f name=instant_"$service_name" --format "{{.Replicas}}") == *"$service_instances/$service_instances"* ]]; do
        config::timeout_check "$start_time" "$service_name to start" "$exit_time" "$warning_time"
        sleep 1
    done

    local await_helper_state
    await_helper_state=$(docker service ps instant_await-helper --format "{{.CurrentState}}")
    until [[ $await_helper_state == *"Complete"* ]]; do
        config::timeout_check "$start_time" "$service_name status check" "$exit_time" "$warning_time"

        await_helper_state=$(docker service ps instant_await-helper --format "{{.CurrentState}}")
        if [[ $await_helper_state == *"Failed"* ]] || [[ $await_helper_state == *"Rejected"* ]]; then
            log error "Fatal: Received error when trying to verify state of $service_name. Error:
       $(docker service ps instant_await-helper --no-trunc --format '{{.Error}}')"
            exit 1
        fi
    done

    try "docker service rm instant_await-helper" "Failed to remove await-helper"
}

# A function which removes a config importing service on successful completion, and exits with an error otherwise
#
# Arguments:
# - $1 : the name of the config importer
# - $2 : (optional) the timeout time for the config importer to run, defaults to 300 seconds
# - $3 : (optional) elapsed time to throw a warning, defaults to 60 seconds
config::remove_config_importer() {
    local -r config_importer_service_name="${1:?"FATAL: remove_config_importer function args not correctly set"}"
    local -r exit_time="${2:-}"
    local -r warning_time="${3:-}"
    local -r start_time=$(date +%s)

    local config_importer_state

    if [[ -z $(docker service ps instant_"$config_importer_service_name") ]]; then
        log info "instant_$config_importer_service_name service cannot be removed as it does not exist!"
        exit 0
    fi

    config_importer_state=$(docker service ps instant_"$config_importer_service_name" --format "{{.CurrentState}}")
    until [[ $config_importer_state == *"Complete"* ]]; do
        config::timeout_check "$start_time" "$config_importer_service_name to run" "$exit_time" "$warning_time"
        sleep 1

        config_importer_state=$(docker service ps instant_"$config_importer_service_name" --format "{{.CurrentState}}")
        if [[ $config_importer_state == *"Failed"* ]] || [[ $config_importer_state == *"Rejected"* ]]; then
            log error "Fatal: $config_importer_service_name failed with error:
       $(docker service ps instant_"$config_importer_service_name" --no-trunc --format '{{.Error}}')"
            exit 1
        fi
    done

    try "docker service rm instant_$config_importer_service_name" "Failed to remove config importer "
}

# Waits for the provided service to be removed
#
# Arguments:
# - $1 : service name (eg. instant_analytics-datastore-elastic-search)
config::await_service_removed() {
    local -r SERVICE_NAME="${1:?"FATAL: await_service_removed SERVICE_NAME not provided"}"
    local start_time=$(date +%s)

    until [[ -z $(docker stack ps instant -qf name="${SERVICE_NAME}") ]]; do
        config::timeout_check "$start_time" "${SERVICE_NAME} to be removed"
        sleep 1
    done
    log info "Service $SERVICE_NAME successfully removed"
}

# Waits for the provided service to join the network
#
# Arguments:
# $1 : service name (eg. instant_analytics-datastore-elastic-search)
config::await_network_join() {
    local -r SERVICE_NAME="${1:?"FATAL: await_service_removed SERVICE_NAME not provided"}"
    local start_time=$(date +%s)
    local exit_time=30
    local warning_time=10

    log info "Waiting for ${SERVICE_NAME} to join network..."

    # TODO: do a better regex/string matching check to ensure that we don't accidentally
    # check for services with append to this service name, e.g., if we're looking for
    # instant_analytics-datastore-elastic-search and we have instant_analytics-datastore-elastic-search-helper
    # we could get a false-positive
    until [[ $(docker network inspect -v instant_default -f "{{.Services}}") == *"${SERVICE_NAME}"* ]]; do
        config::timeout_check "$start_time" "${SERVICE_NAME} to join the network" $exit_time $warning_time
        sleep 1
    done
}

# Generates configs for a service from a folder and adds them to a temp docker-compose file
#
# Arguments:
# - $1 : service name (eg. data-mapper-logstash)
# - $2 : target base (eg. /usr/share/logstash/)
# - $3 : target folder path in absolute format (eg. "$COMPOSE_FILE_PATH"/pipeline)
# - $4 : compose file path (eg. "$COMPOSE_FILE_PATH")
#
# Exports:
# All exports are required for yq to process the values and are not intended for external use
# - service_config_query
# - config_target
# - config_source
# - config_query
# - config_file
# - config_label_name
# - config_service_name
config::generate_service_configs() {
    local -r SERVICE_NAME=${1:?"FATAL: generate_service_config parameter missing"}
    local -r TARGET_BASE=${2:?"FATAL: generate_service_config parameter missing"}
    local -r TARGET_FOLDER_PATH=${3:?"FATAL: generate_service_config parameter missing"}
    local -r COMPOSE_FILE_PATH=${4:?"FATAL: generate_service_config parameter missing"}
    local -r TARGET_FOLDER_NAME=$(basename "${TARGET_FOLDER_PATH}")
    local count=0

    try "touch ${COMPOSE_FILE_PATH}/docker-compose.tmp.yml" "Failed to create temp service config compose file"

    find "${TARGET_FOLDER_PATH}" -maxdepth 10 -mindepth 1 -type f | while read -r file; do
        file_name=${file/"${TARGET_FOLDER_PATH%/}"/}
        file_name=${file_name:1}
        file_hash=$(cksum "${file}" | awk '{print $1}')

        # for these variables to be visible by yq they need to be exported
        export service_config_query=".services.${SERVICE_NAME}.configs[${count}]"
        export config_target="${TARGET_BASE%/}/${TARGET_FOLDER_NAME}/${file_name}"
        export config_source="${SERVICE_NAME}-${file_hash}"

        export config_query=".configs.${config_source}"
        export config_file="./${TARGET_FOLDER_NAME}/${file_name}"
        export config_label_name="${TARGET_FOLDER_NAME}/${file_name}"
        export config_service_name=$SERVICE_NAME

        yq -i '
        .version = "3.9" |
        eval(strenv(service_config_query)).target = env(config_target) |
        eval(strenv(service_config_query)).source = strenv(config_source) |
        eval(strenv(config_query)).file = strenv(config_file) |
        eval(strenv(config_query)).name = strenv(config_source) |
        eval(strenv(config_query)).labels.name = strenv(config_label_name) |
        eval(strenv(config_query)).labels.service = strenv(config_service_name)
        ' "${COMPOSE_FILE_PATH}/docker-compose.tmp.yml"

        count=$((count + 1))
    done
}

# Removes nginx configs for destroyed services
#
# Arguments:
# - $@ : a list of configs to remove
config::remove_service_nginx_config() {
    local configs=("$@")
    local config_rm_command=""
    local config_rm_list=""
    for config in "${configs[@]}"; do
        if [[ -n $(docker config ls -qf name="$config") ]]; then
            config_rm_command="$config_rm_command --config-rm $config"
            config_rm_list="$config_rm_list $config"
        fi
    done

    try "docker service update $config_rm_command instant_reverse-proxy-nginx" "Error updating nginx service"
    try "docker config rm $config_rm_list" "Failed to remove configs"
}
