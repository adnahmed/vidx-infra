#!/bin/bash
# deployment-setup.sh - Complete setup script for VIDX production deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
ENVIRONMENT=${ENVIRONMENT:-production}
CLUSTER_NAME="vidx-eks-cluster"
NAMESPACE="vidx-prod"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    for tool in terraform aws kubectl helm git docker; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Configure AWS credentials
configure_aws() {
    log_info "Configuring AWS credentials..."
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        log_warning "AWS credentials not set via environment variables"
        log_info "Running 'aws configure'..."
        aws configure
    else
        export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
        export AWS_DEFAULT_REGION=$AWS_REGION
    fi
    
    log_success "AWS configured"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing Terraform..."
    cd terraform
    terraform init
    log_success "Terraform initialized"
    cd ..
}

# Plan Terraform
plan_terraform() {
    log_info "Planning Terraform deployment..."
    cd terraform
    
    if [ "$ENVIRONMENT" == "production" ]; then
        terraform plan -var-file=terraform.prod.tfvars -out=tfplan
    else
        terraform plan -var-file=terraform.dev.tfvars -out=tfplan
    fi
    
    log_success "Terraform plan created"
    cd ..
}

# Apply Terraform
apply_terraform() {
    log_info "Applying Terraform configuration..."
    cd terraform
    terraform apply tfplan
    log_success "Infrastructure created"
    
    # Save outputs
    terraform output -json > outputs.json
    log_info "Outputs saved to terraform/outputs.json"
    cd ..
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl..."
    
    aws eks update-kubeconfig \
        --name $CLUSTER_NAME \
        --region $AWS_REGION
    
    log_success "kubectl configured"
    
    # Verify connection
    log_info "Verifying cluster connection..."
    kubectl cluster-info
    log_success "Cluster connection verified"
}

# Deploy Kubernetes manifests
deploy_kubernetes() {
    log_info "Deploying Kubernetes manifests..."
    
    cd k8s
    
    # Apply with kustomize
    if command -v kustomize &> /dev/null; then
        log_info "Using kustomize for deployment..."
        kustomize build . | kubectl apply -f -
    else
        log_warning "kustomize not found, applying manifests individually..."
        kubectl apply -f namespace.yaml
        kubectl apply -f mongodb-*.yaml
        kubectl apply -f rabbitmq-*.yaml
        kubectl apply -f backend-*.yaml
        kubectl apply -f worker-*.yaml
        kubectl apply -f frontend-*.yaml
        kubectl apply -f rbac.yaml
        kubectl apply -f pdb.yaml
        kubectl apply -f ingress.yaml
    fi
    
    log_success "Kubernetes manifests deployed"
    cd ..
}

# Wait for deployments
wait_for_deployments() {
    log_info "Waiting for deployments to be ready..."
    
    kubectl wait --for=condition=available --timeout=300s \
        deployment/vidx-backend -n $NAMESPACE || true
    
    kubectl wait --for=condition=available --timeout=300s \
        deployment/vidx-frontend -n $NAMESPACE || true
    
    log_success "Deployments are ready"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    log_info "Pods:"
    kubectl get pods -n $NAMESPACE
    
    log_info "Services:"
    kubectl get svc -n $NAMESPACE
    
    log_info "Ingress:"
    kubectl get ingress -n $NAMESPACE
    
    log_info "HPA Status:"
    kubectl get hpa -n $NAMESPACE
    
    log_success "Deployment verified"
}

# Display connection information
display_info() {
    log_info "Deployment complete! Connection information:"
    
    local alb_endpoint=$(kubectl get ingress vidx-ingress -n $NAMESPACE \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "PENDING")
    
    echo ""
    echo "==================================="
    echo "Cluster: $CLUSTER_NAME"
    echo "Namespace: $NAMESPACE"
    echo "Region: $AWS_REGION"
    echo "ALB Endpoint: $alb_endpoint"
    echo "MongoDB: mongodb.vidx-prod.svc.cluster.local:27017"
    echo "RabbitMQ: rabbitmq.vidx-prod.svc.cluster.local:5672"
    echo "==================================="
    echo ""
    
    log_info "To view logs:"
    echo "  kubectl logs -n $NAMESPACE deployment/vidx-backend -f"
    echo ""
    
    log_info "To access RabbitMQ management:"
    echo "  kubectl port-forward -n $NAMESPACE svc/rabbitmq 15672:15672"
    echo "  Then visit: http://localhost:15672 (user: vidx / pass: vidx)"
    echo ""
}

# Main execution
main() {
    log_info "Starting VIDX deployment setup..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Region: $AWS_REGION"
    echo ""
    
    check_prerequisites
    configure_aws
    init_terraform
    plan_terraform
    
    # Ask for confirmation before applying
    read -p "Do you want to apply the Terraform plan? (yes/no) " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log_warning "Deployment cancelled"
        exit 0
    fi
    
    apply_terraform
    configure_kubectl
    deploy_kubernetes
    wait_for_deployments
    verify_deployment
    display_info
    
    log_success "VIDX deployment completed successfully!"
}

# Run main function
main "$@"
