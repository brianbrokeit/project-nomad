#!/bin/bash

# Project N.O.M.A.D. Update Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Update Script
# Version               | 2.0.0
# Author                | Crosstalk Solutions, LLC
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m'
GRAY_R='\033[39m'
RED='\033[1;31m'
GREEN='\033[1;32m'

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Platform Detection                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

OS_TYPE="$(uname -s)"
IS_MACOS=false
IS_LINUX=false

if [[ "$OS_TYPE" == "Darwin" ]]; then
  IS_MACOS=true
elif [[ "$OS_TYPE" == "Linux" ]]; then
  IS_LINUX=true
fi

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_has_sudo() {
  if $IS_MACOS; then
    if ! sudo -n true 2>/dev/null; then
      echo -e "${YELLOW}#${RESET} Sudo access is required. You may be prompted for your password.\\n"
      if ! sudo true; then
        echo -e "${RED}#${RESET} Failed to obtain sudo permissions."
        exit 1
      fi
    fi
    echo -e "${GREEN}#${RESET} Sudo permissions confirmed.\\n"
  else
    if sudo -n true 2>/dev/null; then
      echo -e "${GREEN}#${RESET} User has sudo permissions.\\n"
    else
      echo -e "${RED}#${RESET} This script requires sudo permissions to run.\\n"
      echo -e "${RED}#${RESET} For example: sudo bash $(basename "$0")"
      exit 1
    fi
  fi
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    echo -e "${RED}#${RESET} This script requires bash to run.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
  echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

get_update_confirmation(){
  read -p "This script will update Project N.O.M.A.D. No data loss is expected, but you should always back up data before proceeding. Continue? (y/N): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} Continuing with the update."
      ;;
    * )
      echo -e "${RED}#${RESET} Update cancelled."
      exit 0
      ;;
  esac
}

ensure_docker_installed_and_running() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}#${RESET} Docker is not installed. Did you mean to use the install script?"
    exit 1
  fi

  if $IS_MACOS; then
    if ! docker info &>/dev/null; then
      echo -e "${RED}#${RESET} Docker daemon is not running. Please open Docker Desktop and wait for the engine to start, then try again."
      exit 1
    fi
  else
    if ! systemctl is-active --quiet docker; then
      echo -e "${RED}#${RESET} Docker is not running. Attempting to start Docker..."
      sudo systemctl start docker
      if ! systemctl is-active --quiet docker; then
        echo -e "${RED}#${RESET} Failed to start Docker. Please start Docker and try again."
        exit 1
      fi
    fi
  fi

  echo -e "${GREEN}#${RESET} Docker is running.\\n"
}

check_docker_compose() {
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} See: https://docs.docker.com/compose/install/"
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker Compose v2 is available.\\n"
}

ensure_docker_compose_file_exists() {
  local nomad_dir
  if $IS_MACOS; then
    nomad_dir="${HOME}/.project-nomad"
  else
    nomad_dir="/opt/project-nomad"
  fi
  NOMAD_DIR="$nomad_dir"

  if [ ! -f "${NOMAD_DIR}/compose.yml" ]; then
    echo -e "${RED}#${RESET} compose.yml not found at ${NOMAD_DIR}/compose.yml. Please run the install script first."
    exit 1
  fi
}

get_local_ip() {
  if $IS_MACOS; then
    local_ip_address=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || \
      ifconfig | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}')
  else
    local_ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi

  if [[ -z "$local_ip_address" ]]; then
    local_ip_address="localhost"
  fi
}

force_recreate() {
  echo -e "${YELLOW}#${RESET} Pulling the latest Docker images...\\n"
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" pull; then
    echo -e "${RED}#${RESET} Failed to pull the latest Docker images. Please check your network connection and try again."
    exit 1
  fi

  echo -e "${YELLOW}#${RESET} Forcing recreation of containers...\\n"
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d --force-recreate; then
    echo -e "${RED}#${RESET} Failed to recreate containers. Please check the Docker logs for more details."
    exit 1
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D update completed successfully!\\n"
  echo -e "${GREEN}#${RESET} You can access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_is_bash
check_has_sudo
get_update_confirmation
ensure_docker_installed_and_running
check_docker_compose
ensure_docker_compose_file_exists
force_recreate
get_local_ip
success_message
