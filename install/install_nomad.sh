#!/bin/bash

# Project N.O.M.A.D. Installation Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. Installation Script
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
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

WHIPTAIL_TITLE="Project N.O.M.A.D Installation"

# On macOS, /opt is not in Docker Desktop's default file sharing list.
# $HOME is always shared, so we use ~/.project-nomad as the install location.
# On Linux, /opt/project-nomad is the standard location.
if [[ "$(uname -s)" == "Darwin" ]]; then
  NOMAD_DIR="${HOME}/.project-nomad"
else
  NOMAD_DIR="/opt/project-nomad"
fi
MANAGEMENT_COMPOSE_FILE_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/management_compose.yaml"
START_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/start_nomad.sh"
STOP_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/stop_nomad.sh"
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/update_nomad.sh"
script_option_debug='true'
accepted_terms='false'
local_ip_address=''

# Detect OS and architecture once at startup
OS_TYPE="$(uname -s)"   # Darwin or Linux
ARCH="$(uname -m)"      # arm64, x86_64, etc.
IS_MACOS=false
IS_LINUX=false
IS_APPLE_SILICON=false

if [[ "$OS_TYPE" == "Darwin" ]]; then
  IS_MACOS=true
  if [[ "$ARCH" == "arm64" ]]; then
    IS_APPLE_SILICON=true
  fi
elif [[ "$OS_TYPE" == "Linux" ]]; then
  IS_LINUX=true
fi

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

header() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${GREEN}#########################################################################${RESET}\\n"
}

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

check_has_sudo() {
  if $IS_MACOS; then
    # On macOS, sudo access is needed for /opt — check it
    if sudo -n true 2>/dev/null; then
      echo -e "${GREEN}#${RESET} User has sudo permissions.\\n"
    else
      # Prompt once — if it succeeds we're good, if not bail out
      echo -e "${YELLOW}#${RESET} Sudo access is required. You may be prompted for your password.\\n"
      if ! sudo true; then
        echo -e "${RED}#${RESET} Failed to obtain sudo permissions. Please run with an account that has sudo access."
        exit 1
      fi
      echo -e "${GREEN}#${RESET} Sudo permissions confirmed.\\n"
    fi
  else
    if sudo -n true 2>/dev/null; then
      echo -e "${GREEN}#${RESET} User has sudo permissions.\\n"
    else
      echo "User does not have sudo permissions"
      header_red
      echo -e "${RED}#${RESET} This script requires sudo permissions to run. Please run the script with sudo.\\n"
      echo -e "${RED}#${RESET} For example: sudo bash $(basename "$0")"
      exit 1
    fi
  fi
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
  echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

check_platform() {
  if $IS_MACOS; then
    echo -e "${GREEN}#${RESET} Running on macOS ($(sw_vers -productVersion), $ARCH).\\n"
    if $IS_APPLE_SILICON; then
      echo -e "${GREEN}#${RESET} Apple Silicon detected — native arm64 containers will be used.\\n"
    fi
  elif $IS_LINUX; then
    if [[ ! -f /etc/debian_version ]]; then
      echo -e "${YELLOW}#${RESET} Warning: non-Debian Linux detected. The script will attempt to continue but some package installation steps may fail.\\n"
    else
      echo -e "${GREEN}#${RESET} Debian-based Linux detected.\\n"
    fi
  else
    header_red
    echo -e "${RED}#${RESET} Unsupported operating system: $OS_TYPE. This script supports macOS and Linux only."
    exit 1
  fi
}

ensure_dependencies_installed() {
  if $IS_MACOS; then
    _ensure_deps_macos
  else
    _ensure_deps_linux
  fi
}

_ensure_deps_macos() {
  local missing_deps=()

  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies: ${missing_deps[*]}...\\n"
    # curl ships with macOS but can be missing on stripped-down environments
    if ! command -v brew &> /dev/null; then
      echo -e "${RED}#${RESET} Homebrew not found and required dependencies are missing. Please install Homebrew (https://brew.sh) and try again."
      exit 1
    fi
    brew install "${missing_deps[@]}"
  fi

  echo -e "${GREEN}#${RESET} All required dependencies are already installed.\\n"
}

_ensure_deps_linux() {
  local missing_deps=()

  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  if ! command -v gpg &> /dev/null; then
    missing_deps+=("gpg")
  fi

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${YELLOW}#${RESET} Installing required dependencies: ${missing_deps[*]}...\\n"
    sudo apt-get update
    sudo apt-get install -y "${missing_deps[@]}"

    for dep in "${missing_deps[@]}"; do
      if ! command -v "$dep" &> /dev/null; then
        echo -e "${RED}#${RESET} Failed to install $dep. Please install it manually and try again."
        exit 1
      fi
    done
    echo -e "${GREEN}#${RESET} Dependencies installed successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} All required dependencies are already installed.\\n"
  fi
}

check_is_debug_mode(){
  if [[ "${script_option_debug}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Debug mode is enabled, the script will not clear the screen...\\n"
  else
    clear; clear
  fi
}

generateRandomPass() {
  local length="${1:-32}"
  local password
  # LC_ALL=C required on macOS — without it, BSD tr errors on non-ASCII bytes from /dev/urandom
  password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")
  echo "$password"
}

ensure_docker_installed() {
  if $IS_MACOS; then
    _ensure_docker_macos
  else
    _ensure_docker_linux
  fi
}

_ensure_docker_macos() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}#${RESET} Docker is not installed.\\n"
    echo -e "${YELLOW}#${RESET} On macOS, please install Docker Desktop for Mac (Apple Silicon) from:"
    echo -e "${WHITE_R}  https://www.docker.com/products/docker-desktop/${RESET}\\n"
    echo -e "${YELLOW}#${RESET} After installing Docker Desktop, open it, wait for the engine to start, then re-run this script."
    exit 1
  fi

  # Docker Desktop on Mac doesn't use systemctl — check if the daemon is reachable
  if ! docker info &>/dev/null; then
    echo -e "${RED}#${RESET} Docker is installed but the Docker daemon is not running.\\n"
    echo -e "${YELLOW}#${RESET} Please open Docker Desktop and wait for the engine to start, then re-run this script."
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Docker is installed and running.\\n"
}

_ensure_docker_linux() {
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Docker not found. Installing Docker...\\n"

    sudo apt-get update
    sudo apt-get install -y ca-certificates curl

    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh

    if ! command -v docker &> /dev/null; then
      echo -e "${RED}#${RESET} Docker installation failed. Please check the logs and try again."
      exit 1
    fi

    echo -e "${GREEN}#${RESET} Docker installation completed.\\n"
  else
    echo -e "${GREEN}#${RESET} Docker is already installed.\\n"

    if ! systemctl is-active --quiet docker; then
      echo -e "${YELLOW}#${RESET} Docker is installed but not running. Attempting to start Docker...\\n"
      sudo systemctl start docker
      if ! systemctl is-active --quiet docker; then
        echo -e "${RED}#${RESET} Failed to start Docker. Please check the Docker service status and try again."
        exit 1
      else
        echo -e "${GREEN}#${RESET} Docker service started successfully.\\n"
      fi
    else
      echo -e "${GREEN}#${RESET} Docker service is already running.\\n"
    fi
  fi
}

check_docker_compose() {
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} This script requires 'docker compose' (v2), not 'docker-compose' (v1)."
    echo -e "${YELLOW}#${RESET} Please read the Docker documentation at https://docs.docker.com/compose/install/ for instructions."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker Compose v2 is available.\\n"
}

# Only runs on Linux — macOS uses Metal/Apple Silicon, not NVIDIA
setup_nvidia_container_toolkit() {
  if $IS_MACOS; then
    echo -e "${YELLOW}#${RESET} macOS detected — skipping NVIDIA container toolkit (not applicable).\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Checking for NVIDIA GPU...\\n"

  local has_nvidia_gpu=false
  if command -v lspci &> /dev/null; then
    if lspci 2>/dev/null | grep -i nvidia &> /dev/null; then
      has_nvidia_gpu=true
      echo -e "${GREEN}#${RESET} NVIDIA GPU detected.\\n"
    fi
  fi

  if ! $has_nvidia_gpu && command -v nvidia-smi &> /dev/null; then
    if nvidia-smi &> /dev/null; then
      has_nvidia_gpu=true
      echo -e "${GREEN}#${RESET} NVIDIA GPU detected via nvidia-smi.\\n"
    fi
  fi

  if ! $has_nvidia_gpu; then
    echo -e "${YELLOW}#${RESET} No NVIDIA GPU detected. Skipping NVIDIA container toolkit installation.\\n"
    return 0
  fi

  if command -v nvidia-ctk &> /dev/null; then
    echo -e "${GREEN}#${RESET} NVIDIA container toolkit is already installed.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Installing NVIDIA container toolkit...\\n"

  if ! curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey 2>/dev/null | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to add NVIDIA container toolkit GPG key. Continuing anyway...\\n"
    return 0
  fi

  if ! curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list 2>/dev/null \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null 2>&1; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to add NVIDIA container toolkit repository. Continuing anyway...\\n"
    return 0
  fi

  if ! sudo apt-get update 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to update package list. Continuing anyway...\\n"
    return 0
  fi

  if ! sudo apt-get install -y nvidia-container-toolkit 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to install NVIDIA container toolkit. Continuing anyway...\\n"
    return 0
  fi

  echo -e "${GREEN}#${RESET} NVIDIA container toolkit installed successfully.\\n"

  echo -e "${YELLOW}#${RESET} Configuring Docker to use NVIDIA runtime...\\n"

  if ! sudo nvidia-ctk runtime configure --runtime=docker 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} nvidia-ctk configure failed, attempting manual configuration...\\n"

    local daemon_json="/etc/docker/daemon.json"
    local config_success=false

    if [[ -f "$daemon_json" ]]; then
      sudo cp "$daemon_json" "${daemon_json}.backup" 2>/dev/null || true

      if ! grep -q '"nvidia"' "$daemon_json" 2>/dev/null; then
        if command -v jq &> /dev/null; then
          if sudo jq '. + {"runtimes": {"nvidia": {"path": "nvidia-container-runtime", "runtimeArgs": []}}}' "$daemon_json" > /tmp/daemon.json.tmp 2>/dev/null; then
            if sudo mv /tmp/daemon.json.tmp "$daemon_json" 2>/dev/null; then
              config_success=true
            fi
          fi
          sudo rm -f /tmp/daemon.json.tmp 2>/dev/null || true
        fi
      else
        config_success=true
      fi
    else
      if echo '{"runtimes":{"nvidia":{"path":"nvidia-container-runtime","runtimeArgs":[]}}}' | sudo tee "$daemon_json" > /dev/null 2>&1; then
        config_success=true
      fi
    fi

    if ! $config_success; then
      echo -e "${YELLOW}#${RESET} Manual daemon.json configuration unsuccessful. GPU support may require manual setup.\\n"
    fi
  fi

  echo -e "${YELLOW}#${RESET} Restarting Docker service...\\n"
  if ! sudo systemctl restart docker 2>/dev/null; then
    echo -e "${YELLOW}#${RESET} Warning: Failed to restart Docker service. You may need to restart it manually.\\n"
    return 0
  fi

  echo -e "${YELLOW}#${RESET} Verifying NVIDIA runtime configuration...\\n"
  sleep 2

  if docker info 2>/dev/null | grep -q "nvidia"; then
    echo -e "${GREEN}#${RESET} NVIDIA runtime successfully configured and verified.\\n"
  else
    echo -e "${YELLOW}#${RESET} Warning: NVIDIA runtime not detected in Docker info. GPU acceleration may not work.\\n"
    echo -e "${YELLOW}#${RESET} You may need to manually configure /etc/docker/daemon.json and restart Docker.\\n"
  fi

  echo -e "${GREEN}#${RESET} NVIDIA container toolkit configuration completed.\\n"
}

get_install_confirmation(){
  echo -e "${YELLOW}#${RESET} This script will install Project N.O.M.A.D. and its dependencies on your machine."
  echo -e "${YELLOW}#${RESET} If you already have Project N.O.M.A.D. installed with customized config or data, please be aware that running this installation script may overwrite existing files and configurations. It is highly recommended to back up any important data/configs before proceeding."
  read -p "Are you sure you want to continue? (y/N): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the installation."
      ;;
    * )
      echo "User chose not to continue with the installation."
      exit 0
      ;;
  esac
}

accept_terms() {
  printf "\n\n"
  echo "License Agreement & Terms of Use"
  echo "__________________________"
  printf "\n\n"
  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0. The full license can be found at https://www.apache.org/licenses/LICENSE-2.0 or in the LICENSE file of this repository."
  printf "\n"
  echo "By accepting this agreement, you acknowledge that you have read and understood the terms and conditions of the Apache License 2.0 and agree to be bound by them while using Project N.O.M.A.D."
  echo -e "\n\n"
  read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
  case "$choice" in
    y|Y )
      accepted_terms='true'
      ;;
    * )
      echo "License Agreement & Terms of Use not accepted. Installation cannot continue."
      exit 1
      ;;
  esac
}

create_nomad_directory(){
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${YELLOW}#${RESET} Creating directory for Project N.O.M.A.D at $NOMAD_DIR...\\n"
    if $IS_MACOS; then
      # On macOS NOMAD_DIR is under $HOME — no sudo needed, and we must not use sudo
      # or the container (running as a non-root user) won't be able to write to it
      mkdir -p "$NOMAD_DIR"
    else
      sudo mkdir -p "$NOMAD_DIR"
      sudo chown "$(whoami):$(id -gn)" "$NOMAD_DIR"
    fi
    echo -e "${GREEN}#${RESET} Directory created successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Directory $NOMAD_DIR already exists.\\n"
  fi

  if $IS_MACOS; then
    mkdir -p "${NOMAD_DIR}/storage/logs"
    touch "${NOMAD_DIR}/storage/logs/admin.log"
    # Ensure the container (non-root) can write to storage
    chmod -R 755 "${NOMAD_DIR}/storage"
  else
    sudo mkdir -p "${NOMAD_DIR}/storage/logs"
    sudo touch "${NOMAD_DIR}/storage/logs/admin.log"
  fi
}

get_local_ip() {
  if $IS_MACOS; then
    # Try en0 (Wi-Fi) first, then en1, then fall back to any active interface
    local_ip_address=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || \
      ifconfig | awk '/inet / && !/127\.0\.0\.1/ {print $2; exit}')
  else
    local_ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi

  if [[ -z "$local_ip_address" ]]; then
    echo -e "${YELLOW}#${RESET} Unable to determine local IP address — defaulting to localhost.\\n"
    local_ip_address="localhost"
  else
    echo -e "${GREEN}#${RESET} Local IP address: ${local_ip_address}\\n"
  fi
}

download_management_compose_file() {
  local compose_file_path="${NOMAD_DIR}/compose.yml"

  echo -e "${YELLOW}#${RESET} Downloading docker compose file...\\n"
  if ! curl -fsSL "$MANAGEMENT_COMPOSE_FILE_URL" -o "$compose_file_path"; then
    echo -e "${RED}#${RESET} Failed to download the docker compose file. Please check the URL and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker compose file downloaded to $compose_file_path.\\n"

  local app_key
  local db_root_password
  local db_user_password
  app_key=$(generateRandomPass)
  db_root_password=$(generateRandomPass)
  db_user_password=$(generateRandomPass)

  # Remove stale MySQL data so credentials initialize cleanly
  if [[ -d "${NOMAD_DIR}/mysql" ]]; then
    echo -e "${YELLOW}#${RESET} Removing existing MySQL data directory to ensure credentials match...\\n"
    sudo rm -rf "${NOMAD_DIR}/mysql"
  fi

  echo -e "${YELLOW}#${RESET} Configuring docker compose env variables...\\n"

  if $IS_MACOS; then
    # BSD sed on macOS requires an explicit backup extension with -i
    sed -i '' "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$compose_file_path"
    sed -i '' "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file_path"
    sed -i '' "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file_path"
    sed -i '' "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file_path"
    sed -i '' "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file_path"

    # Rewrite hardcoded /opt/project-nomad paths to the macOS install location
    sed -i '' "s|/opt/project-nomad|${NOMAD_DIR}|g" "$compose_file_path"

    # Inject NOMAD_STORAGE_PATH so the seeder uses the correct host path for service volume mounts.
    # Without this, the seeder falls back to /opt/project-nomad/storage which is not shared on macOS.
    sed -i '' "s|- NODE_ENV=production|- NODE_ENV=production\n      - NOMAD_STORAGE_PATH=${NOMAD_DIR}/storage|" "$compose_file_path"

    # Remove the root filesystem bind-mount from disk-collector — Docker Desktop on macOS
    # runs inside a Linux VM and does not allow mounting / from the host.
    sed -i '' '/\/:\//d' "$compose_file_path"

    # Inject platform: linux/arm64 for images that have native arm64 builds.
    # Inject platform: linux/amd64 for sidecar images that are amd64-only (run via Rosetta 2).
    # This suppresses the "image platform does not match host platform" warning and ensures
    # Docker picks the right variant instead of guessing.
    # Inject host CPU info as env vars so the admin container can display real Mac hardware details.
    # systeminformation reads Linux VM /proc/cpuinfo inside Docker and returns no Apple CPU data.
    local cpu_chip cpu_cores cpu_physical_cores
    cpu_chip=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/{print $2}' | xargs)
    cpu_cores=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Total Number of Cores/{print $2}' | awk '{print $1}')
    cpu_physical_cores="$cpu_cores"

    if [[ -n "$cpu_chip" ]]; then
      # Insert env vars into the admin service environment block
      sed -i '' "s|- DISABLE_COMPRESSION=|- HOST_CPU_MANUFACTURER=Apple\n      - HOST_CPU_BRAND=${cpu_chip}\n      - HOST_CPU_CORES=${cpu_cores}\n      - HOST_CPU_PHYSICAL_CORES=${cpu_physical_cores}\n      - DISABLE_COMPRESSION=|" "$compose_file_path"
      echo -e "${GREEN}#${RESET} Injected host CPU info: Apple ${cpu_chip} (${cpu_cores} cores).\\n"
    fi

    # All crosstalk sidecar/app images are amd64-only — run via Rosetta 2 on Apple Silicon.
    # mysql, redis, and dozzle have native arm64 builds so we pin those for better performance.
    sed -i '' "s|image: ghcr.io/crosstalk-solutions/project-nomad:latest|image: ghcr.io/crosstalk-solutions/project-nomad:latest\n    platform: linux/amd64|g" "$compose_file_path"
    sed -i '' "s|image: ghcr.io/crosstalk-solutions/project-nomad-sidecar-updater:latest|image: ghcr.io/crosstalk-solutions/project-nomad-sidecar-updater:latest\n    platform: linux/amd64|g" "$compose_file_path"
    sed -i '' "s|image: ghcr.io/crosstalk-solutions/project-nomad-disk-collector:latest|image: ghcr.io/crosstalk-solutions/project-nomad-disk-collector:latest\n    platform: linux/amd64|g" "$compose_file_path"
    sed -i '' "s|image: mysql:8.0|image: mysql:8.0\n    platform: linux/arm64|g" "$compose_file_path"
    sed -i '' "s|image: redis:7-alpine|image: redis:7-alpine\n    platform: linux/arm64|g" "$compose_file_path"
    sed -i '' "s|image: amir20/dozzle:v10.0|image: amir20/dozzle:v10.0\n    platform: linux/arm64|g" "$compose_file_path"
  else
    sed -i "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$compose_file_path"
    sed -i "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file_path"
    sed -i "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file_path"
    sed -i "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file_path"
    sed -i "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file_path"
  fi

  echo -e "${GREEN}#${RESET} Docker compose file configured successfully.\\n"
}

download_helper_scripts() {
  local start_script_path="${NOMAD_DIR}/start_nomad.sh"
  local stop_script_path="${NOMAD_DIR}/stop_nomad.sh"
  local update_script_path="${NOMAD_DIR}/update_nomad.sh"

  echo -e "${YELLOW}#${RESET} Downloading helper scripts...\\n"

  if ! curl -fsSL "$START_SCRIPT_URL" -o "$start_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the start script."
    exit 1
  fi
  chmod +x "$start_script_path"

  if ! curl -fsSL "$STOP_SCRIPT_URL" -o "$stop_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the stop script."
    exit 1
  fi
  chmod +x "$stop_script_path"

  if ! curl -fsSL "$UPDATE_SCRIPT_URL" -o "$update_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the update script."
    exit 1
  fi
  chmod +x "$update_script_path"

  echo -e "${GREEN}#${RESET} Helper scripts downloaded to ${NOMAD_DIR}.\\n"
}

start_management_containers() {
  echo -e "${YELLOW}#${RESET} Starting management containers...\\n"
  # Export NOMAD_DIR so docker compose can resolve ${NOMAD_DIR} variable substitutions in the compose file
  export NOMAD_DIR
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d; then
    echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Management containers started successfully.\\n"
}

verify_gpu_setup() {
  echo -e "\\n${YELLOW}#${RESET} GPU Setup Verification\\n"
  echo -e "${YELLOW}===========================================${RESET}\\n"

  if $IS_MACOS && $IS_APPLE_SILICON; then
    echo -e "${GREEN}✓${RESET} Apple Silicon (M-series) detected — Metal GPU acceleration is available natively.\\n"
    echo -e "${GREEN}#${RESET} Ollama running on Apple Silicon will automatically use the GPU via Metal. No additional configuration needed.\\n"
    echo -e "${YELLOW}===========================================${RESET}\\n"
    return 0
  fi

  # Linux NVIDIA check
  if command -v nvidia-smi &> /dev/null; then
    echo -e "${GREEN}✓${RESET} NVIDIA GPU detected:"
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | while read -r line; do
      echo -e "  ${WHITE_R}$line${RESET}"
    done
    echo ""
  else
    echo -e "${YELLOW}○${RESET} No NVIDIA GPU detected (nvidia-smi not available)\\n"
  fi

  if command -v nvidia-ctk &> /dev/null; then
    echo -e "${GREEN}✓${RESET} NVIDIA Container Toolkit installed: $(nvidia-ctk --version 2>/dev/null | head -n1)\\n"
  else
    echo -e "${YELLOW}○${RESET} NVIDIA Container Toolkit not installed\\n"
  fi

  if docker info 2>/dev/null | grep -q "nvidia"; then
    echo -e "${GREEN}✓${RESET} Docker NVIDIA runtime configured\\n"
  else
    echo -e "${YELLOW}○${RESET} Docker NVIDIA runtime not detected\\n"
  fi

  if command -v lspci &> /dev/null; then
    if lspci 2>/dev/null | grep -iE "amd|radeon" &> /dev/null; then
      echo -e "${YELLOW}○${RESET} AMD GPU detected (ROCm support not currently available)\\n"
    fi
  fi

  echo -e "${YELLOW}===========================================${RESET}\\n"

  if command -v nvidia-smi &> /dev/null && docker info 2>/dev/null | grep -q "nvidia"; then
    echo -e "${GREEN}#${RESET} GPU acceleration is properly configured! The AI Assistant will use your GPU.\\n"
  else
    echo -e "${YELLOW}#${RESET} GPU acceleration not detected. The AI Assistant will run in CPU-only mode.\\n"
    if command -v nvidia-smi &> /dev/null && ! docker info 2>/dev/null | grep -q "nvidia"; then
      echo -e "${YELLOW}#${RESET} Tip: Your GPU is detected but Docker runtime is not configured.\\n"
      echo -e "${YELLOW}#${RESET} Try restarting Docker: ${WHITE_R}sudo systemctl restart docker${RESET}\\n"
    fi
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\n"
  if $IS_MACOS; then
    echo -e "${GREEN}#${RESET} To start N.O.M.A.D manually: ${WHITE_R}bash ${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  else
    echo -e "${GREEN}#${RESET} Project N.O.M.A.D's Command Center will start automatically on reboot. To start it manually: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  fi
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Pre-flight checks
check_is_bash
check_platform
check_has_sudo
ensure_dependencies_installed
check_is_debug_mode

# Main install
get_install_confirmation
accept_terms
ensure_docker_installed
check_docker_compose
setup_nvidia_container_toolkit
get_local_ip
create_nomad_directory
download_helper_scripts
download_management_compose_file
start_management_containers
verify_gpu_setup
success_message
