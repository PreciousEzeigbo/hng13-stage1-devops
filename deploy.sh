#!/usr/bin/env bash

#############################################################################
# deploy.sh - Production-grade Docker Deployment Automation Script
# Author: Precious Ezeigbo
# Date: 2025-10-22
# Description: Automates setup, deployment, and configuration of Dockerized
#              applications on remote Linux servers with comprehensive
#              error handling, logging, and validation.
#############################################################################

set -euo pipefail
IFS=$'\n\t'

#############################################################################
# GLOBAL VARIABLES
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
TEMP_DIR=""
CLEANUP_MODE=false

# Color outputs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Deployment variables
GIT_REPO_URL=""
PAT=""
BRANCH_NAME="main"
SSH_USER=""
SSH_HOST=""
SSH_KEY_PATH=""
APP_PORT=""
PROJECT_NAME=""
REMOTE_DEPLOY_DIR="/opt/deployments"

#############################################################################
# UTILITY FUNCTIONS
#############################################################################

# Setup logging
setup_logging() {
    mkdir -p "${LOG_DIR}"
    exec > >(tee -a "${LOG_FILE}")
    exec 2>&1
    log_info "Logging initialized: ${LOG_FILE}"
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

# Error handler
error_exit() {
    log_error "$1"
    cleanup_temp
    exit "${2:-1}"
}

# Trap for unexpected errors
trap 'error_exit "Script failed at line $LINENO with exit code $?" $?' ERR
trap 'cleanup_temp; log_warning "Script interrupted by user"' INT TERM

# Cleanup temporary files
cleanup_temp() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
}

# Validate required commands
check_dependencies() {
    local deps=("git" "ssh" "scp" "curl" "rsync")
    log_info "Checking dependencies..."
    
    for cmd in "${deps[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            error_exit "Required command '${cmd}' not found. Please install it." 2
        fi
    done
    log_success "All dependencies are available"
}

#############################################################################
# INPUT VALIDATION FUNCTIONS
#############################################################################

# Validate URL format
validate_url() {
    local url="$1"
    if [[ ! "${url}" =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ "${port}" =~ ^[0-9]+$ ]] && [ "${port}" -ge 1 ] && [ "${port}" -le 65535 ]; then
        return 0
    fi
    return 1
}

# Validate SSH key
validate_ssh_key() {
    local key_path="$1"
    if [[ ! -f "${key_path}" ]]; then
        log_error "SSH key file not found: ${key_path}"
        return 1
    fi
    if [[ ! -r "${key_path}" ]]; then
        log_error "SSH key file not readable: ${key_path}"
        return 1
    fi
    return 0
}

#############################################################################
# USER INPUT COLLECTION
#############################################################################

collect_user_input() {
    log_info "Starting parameter collection..."
    
    # Git Repository URL
    while true; do
        read -rp "Enter Git Repository URL (https://...): " GIT_REPO_URL
        if validate_url "${GIT_REPO_URL}"; then
            break
        fi
        log_error "Invalid URL format. Please enter a valid HTTPS URL."
    done
    
    # Personal Access Token (hidden input)
    while true; do
        read -rsp "Enter Personal Access Token (PAT): " PAT
        echo
        if [[ -n "${PAT}" ]]; then
            break
        fi
        log_error "PAT cannot be empty."
    done
    
    # Branch name
    read -rp "Enter branch name (default: main): " BRANCH_NAME
    BRANCH_NAME="${BRANCH_NAME:-main}"
    
    # SSH Username
    while true; do
        read -rp "Enter SSH username: " SSH_USER
        if [[ -n "${SSH_USER}" ]]; then
            break
        fi
        log_error "Username cannot be empty."
    done
    
    # SSH Host
    while true; do
        read -rp "Enter server IP address: " SSH_HOST
        if validate_ip "${SSH_HOST}" || [[ "${SSH_HOST}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            break
        fi
        log_error "Invalid IP address or hostname."
    done
    
    # SSH Key Path
    while true; do
        read -rp "Enter SSH key path (e.g., ~/.ssh/id_rsa): " SSH_KEY_PATH
        SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
        if validate_ssh_key "${SSH_KEY_PATH}"; then
            break
        fi
    done
    
    # Application Port
    while true; do
        read -rp "Enter application internal port: " APP_PORT
        if validate_port "${APP_PORT}"; then
            break
        fi
        log_error "Invalid port number (1-65535)."
    done
    
    # Extract project name from repo URL and convert to lowercase
    PROJECT_NAME=$(basename "${GIT_REPO_URL}" .git | tr '[:upper:]' '[:lower:]' | tr '_' '-')
    
    log_success "All parameters collected successfully"
    log_info "Repository: ${GIT_REPO_URL}"
    log_info "Branch: ${BRANCH_NAME}"
    log_info "Target: ${SSH_USER}@${SSH_HOST}"
    log_info "Port: ${APP_PORT}"
}

#############################################################################
# REPOSITORY OPERATIONS
#############################################################################

clone_repository() {
    log_info "Starting repository operations..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Prepare authenticated URL
    local auth_url="${GIT_REPO_URL/https:\/\//https:\/\/${PAT}@}"
    
    # Check if directory already exists
    if [[ -d "${PROJECT_NAME}" ]]; then
        log_info "Repository directory exists. Pulling latest changes..."
        cd "${PROJECT_NAME}"
        git pull origin "${BRANCH_NAME}" || error_exit "Failed to pull latest changes" 3
    else
        log_info "Cloning repository..."
        git clone -b "${BRANCH_NAME}" "${auth_url}" "${PROJECT_NAME}" || error_exit "Failed to clone repository" 3
        cd "${PROJECT_NAME}"
    fi
    
    log_success "Repository ready at: $(pwd)"
}

validate_docker_files() {
    log_info "Validating Docker configuration files..."
    
    if [[ -f "Dockerfile" ]]; then
        log_success "Dockerfile found"
        return 0
    elif [[ -f "docker-compose.yml" || -f "docker-compose.yaml" ]]; then
        log_success "docker-compose file found"
        return 0
    else
        error_exit "No Dockerfile or docker-compose.yml found in repository" 4
    fi
}

#############################################################################
# SSH OPERATIONS
#############################################################################

test_ssh_connection() {
    log_info "Testing SSH connection to ${SSH_USER}@${SSH_HOST}..."
    
    if ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        "${SSH_USER}@${SSH_HOST}" "echo 'SSH connection successful'" &> /dev/null; then
        log_success "SSH connection established"
        return 0
    else
        error_exit "Failed to establish SSH connection" 5
    fi
}

execute_remote_command() {
    local command="$1"
    local description="${2:-Executing remote command}"
    
    log_info "${description}..."
    
    if ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
        "${SSH_USER}@${SSH_HOST}" "${command}"; then
        log_success "${description} completed"
        return 0
    else
        log_error "${description} failed"
        return 1
    fi
}

#############################################################################
# REMOTE ENVIRONMENT SETUP
#############################################################################

prepare_remote_environment() {
    log_info "Preparing remote environment..."
    
    # Update system packages
    execute_remote_command "sudo apt-get update -qq" "Updating package lists" || true
    
    # Install Docker
    log_info "Installing Docker..."
    execute_remote_command "
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://get.docker.com -o get-docker.sh && \
            sudo sh get-docker.sh && \
            rm get-docker.sh
        else
            echo 'Docker already installed'
        fi
    " "Docker installation"
    
    # Install Docker Compose
    log_info "Installing Docker Compose..."
    execute_remote_command "
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" \
                -o /usr/local/bin/docker-compose && \
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo 'Docker Compose already installed'
        fi
    " "Docker Compose installation"
    
    # Install Nginx
    log_info "Installing Nginx..."
    execute_remote_command "
        if ! command -v nginx &> /dev/null; then
            sudo apt-get install -y nginx
        else
            echo 'Nginx already installed'
        fi
    " "Nginx installation"
    
    # Add user to docker group
    execute_remote_command "
        sudo usermod -aG docker ${SSH_USER} || true
    " "Adding user to docker group"
    
    # Enable and start services
    execute_remote_command "
        sudo systemctl enable docker && \
        sudo systemctl start docker && \
        sudo systemctl enable nginx && \
        sudo systemctl start nginx
    " "Enabling and starting services"
    
    # Verify installations
    log_info "Verifying installations..."
    execute_remote_command "
        docker --version && \
        docker-compose --version && \
        nginx -v
    " "Version checks"
    
    log_success "Remote environment prepared successfully"
}

#############################################################################
# DEPLOYMENT OPERATIONS
#############################################################################

transfer_files() {
    log_info "Transferring project files to remote server..."
    
    # Create deployment directory on remote
    execute_remote_command "sudo mkdir -p ${REMOTE_DEPLOY_DIR} && sudo chown ${SSH_USER}:${SSH_USER} ${REMOTE_DEPLOY_DIR}" \
        "Creating deployment directory"
    
    # Transfer files using rsync
    if rsync -avz --delete -e "ssh -i ${SSH_KEY_PATH} -o StrictHostKeyChecking=no" \
        "${TEMP_DIR}/${PROJECT_NAME}/" \
        "${SSH_USER}@${SSH_HOST}:${REMOTE_DEPLOY_DIR}/${PROJECT_NAME}/"; then
        log_success "Files transferred successfully"
    else
        error_exit "File transfer failed" 6
    fi
}

deploy_application() {
    log_info "Deploying Docker application..."
    
    # Stop and remove existing containers
    execute_remote_command "
        cd ${REMOTE_DEPLOY_DIR}/${PROJECT_NAME} && \
        (docker-compose down 2>/dev/null || true) && \
        (docker stop ${PROJECT_NAME} 2>/dev/null || true) && \
        (docker rm ${PROJECT_NAME} 2>/dev/null || true)
    " "Cleaning up old containers" || true
    
    # Check for docker-compose file
    local has_compose
    has_compose=$(ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no \
        "${SSH_USER}@${SSH_HOST}" \
        "test -f ${REMOTE_DEPLOY_DIR}/${PROJECT_NAME}/docker-compose.yml && echo 'yes' || echo 'no'")
    
    if [[ "${has_compose}" == "yes" ]]; then
        log_info "Using docker-compose for deployment..."
        execute_remote_command "
            cd ${REMOTE_DEPLOY_DIR}/${PROJECT_NAME} && \
            docker-compose build && \
            docker-compose up -d
        " "Docker Compose deployment"
    else
        log_info "Using Dockerfile for deployment..."
        execute_remote_command "
            cd ${REMOTE_DEPLOY_DIR}/${PROJECT_NAME} && \
            docker build -t ${PROJECT_NAME}:latest . && \
            docker run -d --name ${PROJECT_NAME} -p ${APP_PORT}:${APP_PORT} --restart unless-stopped ${PROJECT_NAME}:latest
        " "Docker build and run"
    fi
    
    log_success "Application deployed successfully"
}

validate_container() {
    log_info "Validating container health..."
    
    sleep 5 # Give container time to start
    
    execute_remote_command "
        docker ps | grep -q ${PROJECT_NAME}
    " "Checking container status"
    
    execute_remote_command "
        docker logs ${PROJECT_NAME} --tail 20
    " "Fetching container logs" || true
    
    log_success "Container is running"
}

#############################################################################
# NGINX CONFIGURATION
#############################################################################

configure_nginx() {
    log_info "Configuring Nginx reverse proxy..."
    
    local nginx_config="/etc/nginx/sites-available/${PROJECT_NAME}"
    local nginx_enabled="/etc/nginx/sites-enabled/${PROJECT_NAME}"
    
    # Create Nginx configuration
    execute_remote_command "
        sudo tee ${nginx_config} > /dev/null <<EOF
server {
    listen 80;
    server_name ${SSH_HOST};

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
        proxy_cache_bypass \\\$http_upgrade;
    }
}
EOF
    " "Creating Nginx configuration"
    
    # Enable site
    execute_remote_command "
        sudo ln -sf ${nginx_config} ${nginx_enabled}
    " "Enabling Nginx site"
    
    # Test configuration
    execute_remote_command "
        sudo nginx -t
    " "Testing Nginx configuration"
    
    # Reload Nginx
    execute_remote_command "
        sudo systemctl reload nginx
    " "Reloading Nginx"
    
    log_success "Nginx configured successfully"
}

#############################################################################
# VALIDATION
#############################################################################

validate_deployment() {
    log_info "Validating complete deployment..."
    
    # Check Docker service
    execute_remote_command "
        sudo systemctl is-active docker
    " "Checking Docker service"
    
    # Check container status
    execute_remote_command "
        docker inspect ${PROJECT_NAME} --format='{{.State.Status}}'
    " "Checking container status"
    
    # Check Nginx
    execute_remote_command "
        sudo systemctl is-active nginx
    " "Checking Nginx service"
    
    # Test endpoint locally on remote
    log_info "Testing endpoint from remote server..."
    execute_remote_command "
        curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT} || echo 'Test failed'
    " "Local endpoint test" || true
    
    # Test via Nginx
    log_info "Testing via Nginx proxy..."
    execute_remote_command "
        curl -s -o /dev/null -w '%{http_code}' http://localhost || echo 'Test failed'
    " "Nginx proxy test" || true
    
    log_success "Deployment validation completed"
    log_info "Application should be accessible at: http://${SSH_HOST}"
}

#############################################################################
# CLEANUP MODE
#############################################################################

cleanup_deployment() {
    log_info "Starting cleanup of deployed resources..."
    
    # Stop and remove containers
    execute_remote_command "
        cd ${REMOTE_DEPLOY_DIR}/${PROJECT_NAME} && \
        (docker-compose down -v 2>/dev/null || true) && \
        (docker stop ${PROJECT_NAME} 2>/dev/null || true) && \
        (docker rm ${PROJECT_NAME} 2>/dev/null || true) && \
        (docker rmi ${PROJECT_NAME}:latest 2>/dev/null || true)
    " "Removing containers and images" || true
    
    # Remove deployment directory
    execute_remote_command "
        sudo rm -rf ${REMOTE_DEPLOY_DIR}/${PROJECT_NAME}
    " "Removing deployment directory" || true
    
    # Remove Nginx configuration
    execute_remote_command "
        sudo rm -f /etc/nginx/sites-enabled/${PROJECT_NAME} && \
        sudo rm -f /etc/nginx/sites-available/${PROJECT_NAME} && \
        sudo systemctl reload nginx
    " "Removing Nginx configuration" || true
    
    log_success "Cleanup completed successfully"
}

#############################################################################
# MAIN EXECUTION
#############################################################################

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --cleanup    Remove all deployed resources
    --help       Show this help message

Description:
    Automates the deployment of Dockerized applications to remote servers.
    The script will prompt for all necessary parameters interactively.

Examples:
    $0              # Normal deployment
    $0 --cleanup    # Remove deployed resources

EOF
    exit 0
}

main() {
    echo "=========================================="
    echo "  Docker Deployment Automation Script"
    echo "=========================================="
    echo
    
    # Setup logging
    setup_logging
    
    for arg in "$@"; do
        case $arg in
            --cleanup)
                CLEANUP_MODE=true
                shift
                ;;
            --help)
                show_usage
                ;;
            *)
                log_error "Unknown option: $arg"
                show_usage
                ;;
        esac
    done
    
    check_dependencies
    
    # Collect user input
    collect_user_input
    
    if [[ "${CLEANUP_MODE}" == true ]]; then
        # Cleanup mode
        test_ssh_connection
        cleanup_deployment
        log_success "Cleanup mode completed successfully"
        exit 0
    fi
    
    # Normal deployment flow
    log_info "Starting deployment process..."
    
    # Step 2: Clone repository
    clone_repository
    
    # Step 3: Validate Docker files
    validate_docker_files
    
    # Step 4: Test SSH connection
    test_ssh_connection
    
    # Step 5: Prepare remote environment
    prepare_remote_environment
    
    # Step 6: Deploy application
    transfer_files
    deploy_application
    validate_container
    
    # Step 7: Configure Nginx
    configure_nginx
    
    # Step 8: Validate deployment
    validate_deployment
    
    # Cleanup temporary files
    cleanup_temp
    
    log_success "=========================================="
    log_success "  DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log_success "=========================================="
    log_info "Application URL: http://${SSH_HOST}"
    log_info "Log file: ${LOG_FILE}"
    
    exit 0
}


main "$@"