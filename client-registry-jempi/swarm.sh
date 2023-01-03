#!/bin/bash

declare ACTION=""
declare MODE=""
declare COMPOSE_FILE_PATH=""
declare PACKAGE_NAME=""
declare UTILS_PATH=""
declare KAFKA_SERVICES=()
declare DGRAPH_SERVICES=()
declare COMBINED_SERVICES=()
declare SERVICE_NAMES=()
declare VOLUME_NAMES=()

function init_vars() {
  ACTION=$1
  MODE=$2

  PACKAGE_NAME=$(basename "$PWD" | sed -e 's/-/ /g' -e 's/\b\(.\)/\u\1/g')

  COMPOSE_FILE_PATH=$(
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit
    pwd -P
  )

  UTILS_PATH="${COMPOSE_FILE_PATH}/../utils"

  DGRAPH_SERVICES=("jempi-ratel")
  VOLUME_NAMES=("jempi-zero-01-data")

  for i in {1..3}; do
    KAFKA_SERVICES=(
      "${KAFKA_SERVICES[@]}"
      "jempi-kafka-0$i"
    )
    DGRAPH_SERVICES=(
      "${DGRAPH_SERVICES[@]}"
      "jempi-alpha-0$i"
    )
    VOLUME_NAMES=(
      "${VOLUME_NAMES[@]}"
      "jempi-kafka-0$i-data"
      "jempi-alpha-0$i-data"
    )
  done

  COMBINED_SERVICES=(
    "jempi-async-receiver"
    "jempi-sync-receiver"
    "jempi-pre-processor"
    "jempi-controller"
    "jempi-em-calculator"
    "jempi-linker"
  )

  SERVICE_NAMES=(
    "${KAFKA_SERVICES[@]}"
    "${DGRAPH_SERVICES[@]}"
    "${COMBINED_SERVICES[@]}"
    "jempi-kafdrop"
    "jempi-zero-01"
    "jempi-api"
  )

  readonly ACTION
  readonly MODE
  readonly COMPOSE_FILE_PATH
  readonly UTILS_PATH
  readonly KAFKA_SERVICES
  readonly DGRAPH_SERVICES
  readonly COMBINED_SERVICES
  readonly SERVICE_NAMES
  readonly VOLUME_NAMES
}

# shellcheck disable=SC1091
function import_sources() {
  source "${UTILS_PATH}/docker-utils.sh"
  source "${UTILS_PATH}/config-utils.sh"
  source "${UTILS_PATH}/log.sh"
}

function initialize_package() {
  local kafdrop_dev_compose_param=""
  local dgraph_dev_compose_param=""
  local dgraph_zero_dev_compose_param=""
  local combined_dev_compose_param=""
  local api_dev_compose_param=""
  local dgraph_cluster_compose_param=""
  local dgraph_zero_cluster_compose_param=""

  if [[ "$MODE" == "dev" ]]; then
    log info "Running $PACKAGE_NAME package in DEV mode"
    kafdrop_dev_compose_param="docker-compose.kafdrop-dev.yml"
    dgraph_dev_compose_param="docker-compose.dgraph-dev.yml"
    dgraph_zero_dev_compose_param="docker-compose.dgraph-zero-dev.yml"
    combined_dev_compose_param="docker-compose.combined-dev.yml"
    api_dev_compose_param="docker-compose.api-dev.yml"
  else
    log info "Running $PACKAGE_NAME package in PROD mode"
  fi

  if [[ "$CLUSTERED_MODE" == "true" ]]; then
    dgraph_cluster_compose_param="docker-compose.dgraph-cluster.yml"
    dgraph_zero_cluster_compose_param="docker-compose.dgraph-zero-cluster.yml"
  fi

  (
    log info "Deploy Kafka"
    docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.kafka.yml"
    docker::deploy_sanity "${KAFKA_SERVICES[@]}"

    log info "Deploy Kafdrop"
    docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.kafdrop.yml" "$kafdrop_dev_compose_param"
    docker::deploy_sanity "jempi-kafdrop"

    docker::deploy_config_importer "$COMPOSE_FILE_PATH/importer/docker-compose.config.yml" "jempi-kafka-config-importer" "jempi-kafka"

    log info "Deploy Dgraph"
    docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.dgraph-zero.yml" "$dgraph_zero_dev_compose_param" "$dgraph_zero_cluster_compose_param"
    docker::deploy_sanity "jempi-zero-01"

    docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.dgraph.yml" "$dgraph_dev_compose_param" "$dgraph_cluster_compose_param"
    docker::deploy_sanity "${DGRAPH_SERVICES[@]}"

    log info "Deploy other combined services"
    docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.combined.yml" "$combined_dev_compose_param"
    docker::deploy_sanity "${COMBINED_SERVICES[@]}"

    log info "Deploy JeMPI API"
    docker::deploy_service "${COMPOSE_FILE_PATH}" "docker-compose.api.yml" "$api_dev_compose_param"
    docker::deploy_sanity "jempi-api"

    log info "Register openHIM channels"
    if docker service ps -q instant_openhim-core &>/dev/null; then
      docker::deploy_config_importer "$COMPOSE_FILE_PATH/importer/openhim/docker-compose.config.yml" "jempi-openhim-config-importer" "openhim"
    else
      log warn "Service 'interoperability-layer-openhim' does not appear to be running... skipping configuring of async/sync JeMPI channels"
    fi

  ) ||
    {
      log error "Failed to deploy $PACKAGE_NAME package"
      exit 1
    }
}

function destroy_package() {
  docker::service_destroy "${SERVICE_NAMES[@]}" "jempi-kafka-config-importer" "jempi-openhim-config-importer"

  docker::try_remove_volume "${VOLUME_NAMES[@]}"

  if [[ "${CLUSTERED_MODE}" == "true" ]]; then
    log warn "Volumes are only deleted on the host on which the command is run. Postgres volumes on other nodes are not deleted"
  fi

  docker::prune_configs "jempi-kafka"
}

main() {
  init_vars "$@"
  import_sources

  if [[ "${ACTION}" == "init" ]] || [[ "${ACTION}" == "up" ]]; then
    if [[ "${CLUSTERED_MODE}" == "true" ]]; then
      log info "Running $PACKAGE_NAME package in Cluster node mode"
    else
      log info "Running $PACKAGE_NAME package in Single node mode"
    fi

    initialize_package
  elif [[ "${ACTION}" == "down" ]]; then
    log info "Scaling down $PACKAGE_NAME"

    docker::scale_services_down "${SERVICE_NAMES[@]}"
  elif [[ "${ACTION}" == "destroy" ]]; then
    log info "Destroying $PACKAGE_NAME"

    destroy_package
  else
    log error "Valid options are: init, up, down, or destroy"
  fi
}

main "$@"
