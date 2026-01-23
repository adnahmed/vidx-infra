#!/bin/bash
# LocalStack setup script for local development and testing

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

log_info "Setting up LocalStack for VIDX development..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Create docker-compose for LocalStack
cat > docker-compose.localstack.yml << 'EOF'
version: '3.8'

services:
  localstack:
    image: localstack/localstack-pro:latest
    container_name: vidx-localstack
    ports:
      - "4566:4566"
      - "4510-4559:4510-4559"
      - "4571:4571"
    environment:
      SERVICES: ec2,eks,ecr,s3,iam,kms,logs,cloudwatch
      DEBUG: 1
      PERSISTENCE: 1
      DOCKER_HOST: unix:///var/run/docker.sock
      LOCALSTACK_AUTH_TOKEN: ${LOCALSTACK_AUTH_TOKEN}
      AWS_REGION: us-east-1
      AWS_ACCESS_KEY_ID: test
      AWS_SECRET_ACCESS_KEY: test
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${TMPDIR:-/tmp}/localstack:/tmp/localstack
    networks:
      - vidx-local

  # MongoDB for local development
  mongodb-local:
    image: mongo:7
    container_name: vidx-mongodb-local
    environment:
      MONGO_INITDB_ROOT_USERNAME: vidx
      MONGO_INITDB_ROOT_PASSWORD: vidx
    ports:
      - "27017:27017"
    volumes:
      - mongodb-local-data:/data/db
    networks:
      - vidx-local

  # RabbitMQ for local development
  rabbitmq-local:
    image: rabbitmq:3-management-alpine
    container_name: vidx-rabbitmq-local
    environment:
      RABBITMQ_DEFAULT_USER: vidx
      RABBITMQ_DEFAULT_PASS: vidx
    ports:
      - "5672:5672"
      - "15672:15672"
    volumes:
      - rabbitmq-local-data:/var/lib/rabbitmq
    networks:
      - vidx-local

volumes:
  mongodb-local-data:
  rabbitmq-local-data:

networks:
  vidx-local:
    driver: bridge
EOF

log_info "Starting LocalStack and dependencies..."
docker-compose -f docker-compose.localstack.yml up -d

log_success "LocalStack started successfully!"
log_info "Waiting for services to be ready..."
sleep 10

# Configure AWS CLI for LocalStack
log_info "Configuring AWS CLI for LocalStack..."
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL_S3=http://localhost:4566
export AWS_ENDPOINT_URL_EC2=http://localhost:4566
export AWS_ENDPOINT_URL_EKS=http://localhost:4566
export AWS_ENDPOINT_URL_ECR=http://localhost:4566
export AWS_ENDPOINT_URL_IAM=http://localhost:4566

# Test LocalStack connection
log_info "Testing LocalStack connection..."
if aws s3 ls --endpoint-url=http://localhost:4566 > /dev/null 2>&1; then
    log_success "LocalStack is ready!"
else
    echo "Warning: Could not connect to LocalStack"
fi

log_info "Creating S3 bucket..."
aws s3 mb s3://vidx-video-storage --endpoint-url=http://localhost:4566 || true

log_success "LocalStack setup complete!"

echo ""
echo "=========================================="
echo "LocalStack Services:"
echo "  LocalStack: http://localhost:4566"
echo "  MongoDB: localhost:27017"
echo "  RabbitMQ: localhost:5672"
echo "  RabbitMQ Management: http://localhost:15672"
echo "=========================================="
echo ""

echo "To deploy with LocalStack:"
echo "  cd terraform"
echo "  terraform apply -var-file=terraform.localstack.tfvars"
echo ""

echo "To stop LocalStack:"
echo "  docker-compose -f docker-compose.localstack.yml down"
echo ""
