#!/bin/bash

# Constants
readonly ACTION=$1
readonly MODE=$2
readonly STATEFUL_NODES=${STATEFUL_NODES:-"cluster"}
readonly HAPI_FHIR_INSTANCES=${HAPI_FHIR_INSTANCES:-1}
export HAPI_FHIR_INSTANCES
COMPOSE_FILE_PATH=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" || exit
  pwd -P
)
readonly COMPOSE_FILE_PATH

# Import libraries
ROOT_PATH="${COMPOSE_FILE_PATH}/.."
. "${ROOT_PATH}/utils/config-utils.sh"
. "${ROOT_PATH}/utils/docker-utils.sh"
. "${ROOT_PATH}/utils/log.sh"

await_postgres_start() {
  log info "Waiting for Postgres to start up before HAPI-FHIR"

  docker::await_container_startup postgres-1
  docker::await_container_status postgres-1 Running

  if [[ "$STATEFUL_NODES" == "cluster" ]]; then
    docker::await_container_startup postgres-2
    docker::await_container_status postgres-2 Running

    docker::await_container_startup postgres-3
    docker::await_container_status postgres-3 Running
  fi
}

if [ "${STATEFUL_NODES}" == "cluster" ]; then
  log info "Running FHIR Datastore HAPI FHIR package in Cluster node mode"
  postgresClusterComposeParam="-c ${COMPOSE_FILE_PATH}/docker-compose-postgres.cluster.yml"
else
  log info "Running FHIR Datastore HAPI FHIR package in Single node mode"
  postgresClusterComposeParam=""
fi

if [ "${MODE}" == "dev" ]; then
  log info "Running FHIR Datastore HAPI FHIR package in DEV mode"
  postgresDevComposeParam="-c ${COMPOSE_FILE_PATH}/docker-compose-postgres.dev.yml"
  hapiFhirDevComposeParam="-c ${COMPOSE_FILE_PATH}/docker-compose.dev.yml"
else
  log info "Running FHIR Datastore HAPI FHIR package in PROD mode"
  postgresDevComposeParam=""
  hapiFhirDevComposeParam=""
fi

if [ "${ACTION}" == "init" ]; then
  try "docker stack deploy -c ${COMPOSE_FILE_PATH}/docker-compose-postgres.yml $postgresClusterComposeParam $postgresDevComposeParam instant" "Failed to deploy FHIR Datastore HAPI FHIR Postgres"

  await_postgres_start

  try "docker stack deploy -c ${COMPOSE_FILE_PATH}/docker-compose.yml $hapiFhirDevComposeParam instant" "Failed to deploy FHIR Datastore HAPI FHIR"
elif [ "${ACTION}" == "up" ]; then
  try "docker stack deploy -c ${COMPOSE_FILE_PATH}/docker-compose-postgres.yml $postgresClusterComposeParam $postgresDevComposeParam instant" "Failed to stand up hapi-fhir postgres"

  await_postgres_start

  try "docker stack deploy -c ${COMPOSE_FILE_PATH}/docker-compose.yml $hapiFhirDevComposeParam instant" "Failed to stand up hapi-fhir"
elif [ "${ACTION}" == "down" ]; then
  try "docker service scale instant_hapi-fhir=0 instant_postgres-1=0" "Failed to scale down hapi-fhir"

  if [ "$STATEFUL_NODES" == "cluster" ]; then
    try "docker service scale instant_postgres-2=0 instant_postgres-3=0" "Failed to scale down hapi-fhir postgres replicas"
  fi

elif [ "${ACTION}" == "destroy" ]; then
  try "docker service rm instant_hapi-fhir instant_postgres-1" "Failed to destroy hapi-fhir"

  config::await_service_removed instant_hapi-fhir
  config::await_service_removed instant_postgres-1

  try "docker volume rm instant_hapi-postgres-1-data" "Failed to destroy hapi-fhir volume"

  if [ "${STATEFUL_NODES}" == "cluster" ]; then
    try "docker service rm instant_postgres-2 instant_postgres-3" "Failed to destroy hapi-fhir postgres replicas"
    config::await_service_removed instant_postgres-2
    config::await_service_removed instant_postgres-3
    try "docker volume rm instant_hapi-postgres-2-data instant_hapi-postgres-3-data" "Failed to remove hapi-fhir postgres volumes"

    log warn "Volumes are only deleted on the host on which the command is run. Postgres volumes on other nodes are not deleted"
  fi
else
  log error "Valid options are: init, up, down, or destroy"
fi
