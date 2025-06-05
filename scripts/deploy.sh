#!/bin/bash

# Yii2 DevOps Deployment Script
# Usage: ./scripts/deploy.sh [environment] [image_tag]

set -e

ENVIRONMENT=${1:-production}
IMAGE_TAG=${2:-latest}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    command -v ansible >/dev/null 2>&1 || error "Ansible is not installed"
    command -v docker >/dev/null 2>&1 || error "Docker is not installed"
    
    if [ ! -f "$PROJECT_ROOT/ansible/inventory/hosts" ]; then
        error "Ansible inventory file not found"
    fi
    
    log "Prerequisites check passed"
}

# Validate environment
validate_environment() {
    case $ENVIRONMENT in
        production|staging|development)
            log "Deploying to $ENVIRONMENT environment"
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT. Use: production, staging, or development"
            ;;
    esac
}

# Test connectivity
test_connectivity() {
    log "Testing connectivity to target hosts..."
    
    cd "$PROJECT_ROOT/ansible"
    if ! ansible all -i inventory/hosts -m ping; then
        error "Cannot connect to target hosts"
    fi
    
    log "Connectivity test passed"
}

# Build and push image (if needed)
build_image() {
    if [ "$BUILD_IMAGE" = "true" ]; then
        log "Building Docker image..."
        
        cd "$PROJECT_ROOT"
        docker build -t "yii2-devops:$IMAGE_TAG" .
        
        if [ -n "$DOCKER_REGISTRY" ]; then
            docker tag "yii2-devops:$IMAGE_TAG" "$DOCKER_REGISTRY/yii2-devops:$IMAGE_TAG"
            docker push "$DOCKER_REGISTRY/yii2-devops:$IMAGE_TAG"
        fi
        
        log "Image built and pushed successfully"
    fi
}

# Deploy application
deploy_application