#!/bin/bash
# Local development environment setup script for VIDX

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker."
        exit 1
    fi
    log_success "Docker found"

    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed."
        exit 1
    fi
    log_success "Docker Compose found"

    if ! docker info > /dev/null 2>&1; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    log_success "Docker daemon is running"
}

# Start LocalStack
start_localstack() {
    log_info "Starting LocalStack and dependencies..."

    if docker compose -f docker-compose.localstack.yml ps | grep -q "Up"; then
        log_warning "Services already running. Skipping start."
        return
    fi

    docker compose -f docker-compose.localstack.yml up -d

    log_info "Waiting for services to be ready..."
    sleep 15

    # Wait for LocalStack health
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:4566/_localstack/health | grep -q "services" 2>/dev/null; then
            log_success "LocalStack is ready"
            return
        fi
        echo -n "."
        sleep 1
        ((attempt++))
    done

    log_error "LocalStack failed to start within timeout"
    exit 1
}

# Create environment file
create_env_file() {
    log_info "Creating environment configuration..."

    if [ -f ".env.local" ]; then
        log_warning ".env.local already exists. Skipping creation."
        return
    fi

    cat > .env.local << 'EOF'
# AWS Configuration for LocalStack
AWS_ENDPOINT_URL=http://localhost:4566
AWS_DEFAULT_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test

# Queue & Storage Configuration
QUEUE_TYPE=sqs
STORAGE_TYPE=s3

# Database Configuration
DB_TYPE=mongodb
VIDX_DB_HOST=localhost
VIDX_DB_PORT=27017
VIDX_DB_USER=vidx
VIDX_DB_PASS=vidx
VIDX_DB_BASE=admin

# Messaging Configuration (fallback to RabbitMQ)
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USER=vidx
RABBITMQ_PASS=vidx
RABBITMQ_BASE=/

# S3 Configuration
AWS_S3_BUCKET=vidx-video-storage
S3_PRESIGN_EXPIRY=3600

# Backend Configuration
VIDX_HOST=0.0.0.0
VIDX_PORT=8000
VIDX_LOG_LEVEL=INFO

# Application Keys (should be changed for production)
VIDX_JWT_SECRET=dev-secret-key-change-in-production
VIDX_JWT_ALGORITHM=HS256
VIDX_JWT_EXP_MINUTES=60
EOF

    log_success ".env.local created"
    log_info "Configuration:"
    echo "  QUEUE_TYPE=sqs"
    echo "  STORAGE_TYPE=s3"
    echo "  AWS_ENDPOINT_URL=http://localhost:4566"
    echo "  MongoDB: localhost:27017"
    echo "  RabbitMQ: localhost:5672"
}

# Verify services
verify_services() {
    log_info "Verifying services..."

    # LocalStack
    if curl -s http://localhost:4566/_localstack/health | grep -q "services"; then
        log_success "LocalStack is running"
    else
        log_error "LocalStack health check failed"
        return 1
    fi

    # MongoDB
    if docker exec vidx-mongodb mongosh --eval "db.adminCommand('ping')" -u vidx -p vidx --authenticationDatabase admin > /dev/null 2>&1; then
        log_success "MongoDB is running"
    else
        log_warning "MongoDB health check failed (may still be starting)"
    fi

    # RabbitMQ
    if docker exec vidx-rabbitmq rabbitmq-diagnostics -q ping > /dev/null 2>&1; then
        log_success "RabbitMQ is running"
    else
        log_warning "RabbitMQ health check failed (may still be starting)"
    fi
}

# Display connection info
display_info() {
    log_success "Local development environment is ready!"
    echo ""
    echo "=========================================="
    echo "Service Connection Details"
    echo "=========================================="
    echo "LocalStack (AWS): http://localhost:4566"
    echo "MongoDB: mongodb://vidx:vidx@localhost:27017"
    echo "RabbitMQ AMQP: amqp://vidx:vidx@localhost:5672/"
    echo "RabbitMQ UI: http://localhost:15672"
    echo ""
    echo "=========================================="
    echo "Next Steps"
    echo "=========================================="
    echo "1. Load environment:"
    echo "   source .env.local"
    echo ""
    echo "2. Install dependencies:"
    echo "   cd backend && poetry install"
    echo "   cd frontend && npm install"
    echo ""
    echo "3. Start backend (in one terminal):"
    echo "   cd backend && poetry run uvicorn vidx.web.application:app --reload"
    echo ""
    echo "4. Start worker (in another terminal):"
    echo "   cd backend && poetry run start-celery"
    echo ""
    echo "5. Start frontend (in another terminal):"
    echo "   cd frontend && npm start"
    echo ""
    echo "=========================================="
    echo "Documentation"
    echo "=========================================="
    echo "See LOCALSTACK_DEVELOPMENT.md for detailed setup and troubleshooting"
    echo ""
}

# Stop services
stop_services() {
    log_info "Stopping services..."
    docker compose -f docker-compose.localstack.yml down
    log_success "Services stopped"
}

# Clean up (reset state)
clean_services() {
    log_warning "Resetting all services and data..."
    docker compose -f docker-compose.localstack.yml down -v
    rm -f .env.local
    log_success "Clean complete. Run again to start fresh."
}

# Main
main() {
    case "${1:-start}" in
        start)
            check_prereqs
            start_localstack
            create_env_file
            verify_services
            display_info
            ;;
        stop)
            stop_services
            ;;
        restart)
            stop_services
            sleep 2
            start_localstack
            verify_services
            log_success "Services restarted"
            ;;
        clean)
            clean_services
            ;;
        status)
            docker compose -f docker-compose.localstack.yml ps
            ;;
        logs)
            docker compose -f docker-compose.localstack.yml logs -f "${2:-localstack}"
            ;;
        *)
            cat << USAGE
Usage: $0 {start|stop|restart|clean|status|logs [service]}

Commands:
  start     Start LocalStack and all dependencies (default)
  stop      Stop all services
  restart   Restart all services
  clean     Stop services and remove all volumes (clean slate)
  status    Show service status
  logs      Display logs (optionally specify service: localstack|mongodb|rabbitmq)

Example:
  $0 start
  $0 logs localstack
  $0 clean
USAGE
            exit 1
            ;;
    esac
}

main "$@"
