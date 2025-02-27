#!/bin/bash

#
# Notice: Please make sure you use the script in the project root directory.
#
# For example:
# ```
# DOCKER_USER=ti-community-infra IMAGE_TAG=v0.0.1 SKIP_PUSH=1 SKIP_PATRONI=1 SKIP_TESTS=1 SKIP_PROD=1 ./deployments/images/build_images.sh

#
# SKIP_DEV=1 (skip dev env images)
# SKIP_PROD=1 (skip prod env images)
# SKIP_PUSH=1 (skip push the images)
#

if [ -z "${DOCKER_USER}" ]
then
  echo "$0: you need to set docker user via DOCKER_USER=username"
  exit 1
fi

if [ -z "${IMAGE_TAG}" ]
then
  echo "$0: you need to set docker image tag via IMAGE_TAG=tag"
  exit 2
fi

cwd="$(pwd)"

# Project root directory.
DEVSTATS_ROOT="${cwd}"
DEVSTATS_REPORTS_DIR="${cwd}/devstats-reports"

# Docker images directory.
DEPLOYMENT_DOCKER_IMAGES_DIR="${cwd}/deployments/images"
TEMP_DIR="${cwd}/deployments/images/temp"

# Configuration file directory.
DEVSTATS_CNCF_CONFIG_DIR="${cwd}/devstats"
DEVSTATS_SHARED_CONFIG_DIR="${cwd}/configs/shared"
DEVSTATS_DEV_CONFIG_DIR="${cwd}/configs/dev"
DEVSTATS_PROD_CONFIG_DIR="${cwd}/configs/prod"

# The path to devstats packages.
DEVSTATS_CODE_TAR="${TEMP_DIR}/devstatscode.tar"
DEVSTATS_REPORTS_TAR="${TEMP_DIR}/devstats-reports.tar"
DEVSTATS_API_SERVER_BIN_TAR="${TEMP_DIR}/devstats-api-bins.tar"
GRAFANA_TOOL_BIN_TAR="${TEMP_DIR}/grafana-tool-bins.tar"

# The path to config file package.
DEVSTATS_CNCF_CONFIG_TAR="${TEMP_DIR}/devstats-config-cncf.tar"
DEVSTATS_SHARED_CONFIG_TAR="${TEMP_DIR}/devstats-config-shared.tar"
DEVSTATS_DEV_CONFIG_TAR="${TEMP_DIR}/devstats-config-dev.tar"
DEVSTATS_PROD_CONFIG_TAR="${TEMP_DIR}/devstats-config-prod.tar"

DEVSTATS_API_DEV_CONFIG_TAR="${TEMP_DIR}/devstats-api-config-dev.tar"
DEVSTATS_API_PROD_CONFIG_TAR="${TEMP_DIR}/devstats-api-config-prod.tar"


#
# Prepare Stage
#

# Ensure those directory is exist.
cd "${DEVSTATS_CNCF_CONFIG_DIR}" || exit 3
cd "${DEVSTATS_REPORTS_DIR}" || exit 4
cd "${DEPLOYMENT_DOCKER_IMAGES_DIR}" || exit 4

# Create a directory to temporarily store files that need to be written to the image.
mkdir -p "$TEMP_DIR"

#
# Package Stage
#

# Package the sourcecode and binary of devstats.
cd "${DEVSTATS_ROOT}" || exit 6
make replacer sqlitedb runq api || exit 7

if [ -n "$DEVSTATS_CODE_TAR" ]
then
  rm -f "$DEVSTATS_CODE_TAR" 2>/dev/null
fi

if [ -n "$DEVSTATS_API_SERVER_BIN_TAR" ]
then
  rm -f "$DEVSTATS_API_SERVER_BIN_TAR" 2>/dev/null
fi

if [ -n "$GRAFANA_TOOL_BIN_TAR" ]
then
  rm -f "$GRAFANA_TOOL_BIN_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_CODE_TAR" cmd cron devel git internal tools/check go.mod go.sum .git .golangci.yml Makefile || exit 5
tar cf "$DEVSTATS_API_SERVER_BIN_TAR" api || exit 44
tar cf "$GRAFANA_TOOL_BIN_TAR" replacer sqlitedb runq || exit 6

# Package the files in devstats-report repository.
cd "$DEVSTATS_REPORTS_DIR" || exit 40

if [ -n "$DEVSTATS_REPORTS_TAR" ]
then
  rm -f "$DEVSTATS_REPORTS_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_REPORTS_TAR" sh sql affs rep contributors velocity find.sh || exit 41

# Package the configs files from cncf/devstats.
cd "$DEVSTATS_CNCF_CONFIG_DIR" || exit 7

if [ -n "$DEVSTATS_CNCF_CONFIG_TAR" ]
then
  rm -f "$DEVSTATS_CNCF_CONFIG_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_CNCF_CONFIG_TAR" hide git metrics devel shared scripts cron docs jsons/.keep util_sql util_sh github_users.json companies.yaml skip_dates.yaml  || exit 8

# Copy static file to temp directory, for copying to the docker image.
cp apache/www/index_*.html "${TEMP_DIR}/" || exit 22

#
# Pack the configuration files of different environments into different compressed packages,
# and then decompress them when building the image for overwriting default config.
#
# TODO: Move the project psql.sh file to the projects directory
# so that we don't need to update the build_images.sh when we add a new project.
#

# Package the shared config file.
# Notice: This file will override the config files from cncf/devstats repository.
cd "$DEVSTATS_SHARED_CONFIG_DIR" || exit 62

if [ -n "$DEVSTATS_SHARED_CONFIG_TAR" ]
then
  rm -f "$DEVSTATS_SHARED_CONFIG_TAR" 2>/dev/null
fi

tar cf "$DEVSTATS_SHARED_CONFIG_TAR" ./*

# Package the devstats config file for dev environment.
# Notice: This file will override the config files from shared directory and cncf/devstats repository.
if [ -z "$SKIP_DEV" ]
then
  cd "$DEVSTATS_DEV_CONFIG_DIR" || exit 61

  if [ -n "$DEVSTATS_DEV_CONFIG_TAR" ]
  then
    rm -f "$DEVSTATS_DEV_CONFIG_TAR" 2>/dev/null
  fi

  tar cf "$DEVSTATS_DEV_CONFIG_TAR" all tidb tikv chaosmesh ob metrics scripts devel docs projects.yaml
  tar cf "$DEVSTATS_API_DEV_CONFIG_TAR" projects.yaml
fi

# Package the devstats config file for prod environment.
# Notice: This file will override the config files from shared directory and cncf/devstats repository.
if [ -z "$SKIP_PROD" ]
then
  cd "$DEVSTATS_PROD_CONFIG_DIR" || exit 62

  tar cf "$DEVSTATS_PROD_CONFIG_TAR" all tidb tikv chaosmesh ob metrics scripts devel docs projects.yaml
  tar cf "$DEVSTATS_API_PROD_CONFIG_TAR" projects.yaml
fi

#
# Build Image Stage
#

cd "${DEPLOYMENT_DOCKER_IMAGES_DIR}" || exit 11

if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker build -f Dockerfile.full.dev -t "${DOCKER_USER}/devstats-dev:${IMAGE_TAG}" . || exit 12
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.full.prod -t "${DOCKER_USER}/devstats-prod:${IMAGE_TAG}" . || exit 33
  fi
fi

if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker build -f Dockerfile.minimal.dev -t "${DOCKER_USER}/devstats-minimal-dev:${IMAGE_TAG}" . || exit 13
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.minimal.prod -t "${DOCKER_USER}/devstats-minimal-prod:${IMAGE_TAG}" . || exit 35
  fi
fi

if [ -z "$SKIP_GRAFANA" ]
then
  docker build -f Dockerfile.grafana -t "${DOCKER_USER}/devstats-grafana:${IMAGE_TAG}" . || exit 36
fi

if [ -z "$SKIP_TESTS" ]
then
  docker build -f Dockerfile.tests -t "${DOCKER_USER}/devstats-tests:${IMAGE_TAG}" . || exit 15
fi

if [ -z "$SKIP_PATRONI" ]
then
  #docker build -f Dockerfile.patroni -t "${DOCKER_USER}/devstats-patroni:${IMAGE_TAG}" . || exit 16
  docker build -f Dockerfile.patroni -t "${DOCKER_USER}/devstats-patroni-new:${IMAGE_TAG}" . || exit 16
  docker build -f Dockerfile.patroni.13 -t "${DOCKER_USER}/devstats-patroni-13:${IMAGE_TAG}" . || exit 16
fi

if [ -z "$SKIP_STATIC" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker build -f Dockerfile.static.dev -t "${DOCKER_USER}/devstats-static-dev:${IMAGE_TAG}" . || exit 24
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.static.prod -t "${DOCKER_USER}/devstats-static-prod:${IMAGE_TAG}" . || exit 23
  fi
  docker build -f Dockerfile.static.default -t "${DOCKER_USER}/devstats-static-default:${IMAGE_TAG}" . || exit 27
  docker build -f Dockerfile.static.backups -t "${DOCKER_USER}/backups-page:${IMAGE_TAG}" . || exit 42
fi

if [ -z "$SKIP_REPORTS" ]
then
  docker build -f Dockerfile.reports -t "${DOCKER_USER}/devstats-reports:${IMAGE_TAG}" . || exit 37
fi

if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker build -f Dockerfile.api.dev -t "${DOCKER_USER}/devstats-api-dev:${IMAGE_TAG}" . || exit 48
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker build -f Dockerfile.api.prod -t "${DOCKER_USER}/devstats-api-prod:${IMAGE_TAG}" . || exit 46
  fi
fi


#
# Clean Stage
#

# Clean the temp file for build.
if [ -n "$TEMP_DIR" ]
then
  rm -rf "$TEMP_DIR"
fi

#
# Push Stage
#

# Don't push the images, just build.
if [ -n "$SKIP_PUSH" ]
then
  exit 0
fi

# Build docker image for full sync.
if [ -z "$SKIP_FULL" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker push "${DOCKER_USER}/devstats-dev:${IMAGE_TAG}" || exit 17
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-prod:${IMAGE_TAG}" || exit 34
  fi
fi

# Build docker image for minimal sync.
if [ -z "$SKIP_MIN" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker push "${DOCKER_USER}/devstats-minimal-dev:${IMAGE_TAG}" || exit 18
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-minimal-prod:${IMAGE_TAG}" || exit 36
  fi
fi

# Build docker image for grafana.
if [ -z "$SKIP_GRAFANA" ]
then
  docker push "${DOCKER_USER}/devstats-grafana:${IMAGE_TAG}" || exit 19
fi

# Build docker image for tests.
if [ -z "$SKIP_TESTS" ]
then
  docker push "${DOCKER_USER}/devstats-tests:${IMAGE_TAG}" || exit 20
fi

# Build docker image for patroni database.
if [ -z "$SKIP_PATRONI" ]
then
  #docker push "${DOCKER_USER}/devstats-patroni" || exit 21
  docker push "${DOCKER_USER}/devstats-patroni-new:${IMAGE_TAG}" || exit 21
  docker push "${DOCKER_USER}/devstats-patroni-13:${IMAGE_TAG}" || exit 21
fi

# Build docker image for static files.
if [ -z "$SKIP_STATIC" ]
then
  if [ -z "$SKIP_DEV" ]
  then
    docker push "${DOCKER_USER}/devstats-static-dev:${IMAGE_TAG}" || exit 28
  fi
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-static-prod:${IMAGE_TAG}" || exit 24
  fi
  docker push "${DOCKER_USER}/devstats-static-default:${IMAGE_TAG}" || exit 31
  docker push "${DOCKER_USER}/backups-page:${IMAGE_TAG}" || exit 43
fi

if [ -z "$SKIP_REPORTS" ]
then
  docker push "${DOCKER_USER}/devstats-reports:${IMAGE_TAG}" || exit 38
fi

# Build docker image for API server.
if [ -z "$SKIP_API" ]
then
  if [ -z "$SKIP_PROD" ]
  then
    docker push "${DOCKER_USER}/devstats-api-prod:${IMAGE_TAG}" || exit 47
  fi
  if [ -z "$SKIP_DEV" ]
  then
    docker push "${DOCKER_USER}/devstats-api-dev:${IMAGE_TAG}" || exit 49
  fi
fi

echo 'OK'
