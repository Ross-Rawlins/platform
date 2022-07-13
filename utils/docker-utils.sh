#!/bin/bash
#
# Library name: docker
# This is a library that contains functions to assist with docker actions

. "$(pwd)/utils/config-utils.sh"
. "$(pwd)/utils/log.sh"

# Waits for a container to be up
#
# Arguments:
# - $1 : service name (eg. analytics-datastore-elastic-search)
#
docker::await_container_startup() {
    local -r SERVICE_NAME=${1:?"FATAL: await_container_startup SERVICE_NAME not provided"}

    log info "Waiting for ${SERVICE_NAME} to start up..."
    local start_time
    start_time=$(date +%s)
    until [[ -n $(docker service ls -qf name=instant_"${SERVICE_NAME}") ]]; do
        config::timeout_check "${start_time}" "${SERVICE_NAME} to start"
        sleep 1
    done
    overwrite "Waiting for ${SERVICE_NAME} to start up... Done"
}

# Waits for a container to be up
#
# Arguments:
# - $1 : service name (eg. analytics-datastore-elastic-search)
# - $2 : service status (eg. running)
#
docker::await_container_status() {
    local -r SERVICE_NAME=${1:?"FATAL: await_container_startup parameter not provided"}
    local -r SERVICE_STATUS=${2:?"FATAL: await_container_startup parameter not provided"}

    log info "Waiting for ${SERVICE_NAME} to be ${SERVICE_STATUS}..."
    local start_time
    start_time=$(date +%s)
    until [[ $(docker service ps instant_"${SERVICE_NAME}" --format "{{.CurrentState}}" 2>/dev/null) == *"${SERVICE_STATUS}"* ]]; do
        config::timeout_check "${start_time}" "${SERVICE_NAME} to start"
        sleep 1
    done
    overwrite "Waiting for ${SERVICE_NAME} to be ${SERVICE_STATUS}... Done"
}

# Waits for a container to be destroyed
#
# Arguments:
# - $1 : service name (eg. analytics-datastore-elastic-search)
#
docker::await_container_destroy() {
    local -r SERVICE_NAME=${1:?"FATAL: await_container_destroy SERVICE_NAME not provided"}

    log info "Waiting for ${SERVICE_NAME} to be destroyed..."
    local start_time
    start_time=$(date +%s)
    until [[ -z $(docker ps -qlf name="instant_${SERVICE_NAME}") ]]; do
        config::timeout_check "${start_time}" "${SERVICE_NAME} to be destroyed"
        sleep 1
    done
    overwrite "Waiting for ${SERVICE_NAME} to be destroyed... Done"
}

# Waits for a service to be destroyed
#
# Arguments:
# - $1 : service name (eg. analytics-datastore-elastic-search)
#
docker::await_service_destroy() {
    local -r SERVICE_NAME=${1:?"FATAL: await_container_destroy SERVICE_NAME not provided"}

    log info "Waiting for ${SERVICE_NAME} to be destroyed..."
    local start_time
    start_time=$(date +%s)
    until [[ -z $(docker service ls -qf name=instant_"${SERVICE_NAME}") ]]; do
        config::timeout_check "${start_time}" "${SERVICE_NAME} to be destroyed"
        sleep 1
    done
    overwrite "Waiting for ${SERVICE_NAME} to be destroyed... Done"
}
