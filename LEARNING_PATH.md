# Cloud Infrastructure Learning Path

> **From Single-Machine Development to Multi-Region Distributed Systems**
>
> Starting point: Experience with Heroku, Vercel, single VM deployments  
> Goal: Understanding multi-region, auto-scaling, cloud-native architecture

---

## Quick Start: Your First Week

```bash
# Day 1: Get the system running locally
docker-compose up

# Day 2: Understand what's running
docker ps
curl http://localhost:8000/docs  # FastAPI Swagger UI

# Day 3: Break something and fix it
docker-compose stop mongodb
# Watch backend fail, restart it, understand dependencies

# Day 4-5: Read architecture docs
# See "Phase 1" below
```

---

## Learning Philosophy

**The Loop:**
1. **Read** a concept (from book or doc)
2. **Find** it in this repo
3. **Run** it locally
4. **Break** it intentionally
5. **Fix** it and understand why it broke

**Time Investment:**
- **Part-time (10h/week)**: 8-12 weeks to production-ready
- **Full-time (40h/week)**: 3-4 weeks to production-ready

---

## Phase 1: Local Container Orchestration (Week 1-2)

### Learning Goals
- Understand Docker containers vs VMs
- Know when to use Docker Compose vs Kubernetes
- Grasp service dependencies and networking

### Reading
- **Book**: First 2 chapters of "Docker Deep Dive" by Nigel Poulton OR
- **Free**: Docker official docs (Get Started section)
- **This Repo**: [CLOUD_NATIVE_ARCHITECTURE.md](CLOUD_NATIVE_ARCHITECTURE.md) - Local Development section

### Hands-On Exercises

#### Exercise 1.1: Run the Full Stack Locally
```bash
# Start everything
docker-compose up -d

# Verify all services
docker ps
docker-compose logs backend
docker-compose logs celery-worker

# Access the system
open http://localhost:8000/docs  # Backend API
open http://localhost:3000       # Frontend (if running)
```

**Understand:**
- Why does backend need MongoDB? (Check `backend/vidx/db/`)
- What is RabbitMQ doing? (Check `backend/vidx/services/celery/`)
- What's the difference between `backend` and `celery-worker` containers?

#### Exercise 1.2: Service Dependencies
```bash
# Stop MongoDB
docker-compose stop mongodb

# Try to use the backend
curl http://localhost:8000/health
# What error do you see?

# Restart MongoDB
docker-compose start mongodb

# Check logs
docker-compose logs backend | tail -20
```

**Question to Answer:**
- How long does it take backend to reconnect?
- Where in the code handles connection retries? (Hint: `backend/vidx/db/`)

#### Exercise 1.3: Understand Celery + RabbitMQ
```bash
# Submit a test task
python backend/validate_task_execution.py

# Watch it being processed
docker-compose logs -f celery-worker

# Stop the worker mid-task
docker-compose stop celery-worker
# What happens to the task?

# Restart and see it resume
docker-compose start celery-worker
```

**Key Concept:** Task durability - RabbitMQ queues persist tasks

#### Exercise 1.4: Read the Docker Compose Config
Open: [docker-compose.yml](docker-compose.yml)

**Understand each section:**
```yaml
services:
  backend:
    depends_on:  # Why does it depend on MongoDB/RabbitMQ?
    environment: # Where do these env vars get used?
    volumes:     # Why mount the code directory?
    ports:       # What is 8000:8000 doing?
```

### Checkpoint Questions
- [ ] What happens if MongoDB crashes while backend is running?
- [ ] Can you add a new environment variable to backend and see it in the logs?
- [ ] How would you scale to 3 Celery workers? (Hint: `docker-compose up --scale`)
- [ ] Where are video files stored locally vs production? (Check settings.py)

### Resources
- [Docker Compose docs](https://docs.docker.com/compose/)
- This repo: [LOCAL_TESTING_GUIDE.md](LOCAL_TESTING_GUIDE.md)

---

## Phase 2: Kubernetes Fundamentals (Week 3-4)

### Learning Goals
- Understand why Kubernetes exists (what Docker Compose can't do)
- Grasp Pods, Deployments, Services, ConfigMaps, Secrets
- Know how to debug running containers in K8s

### Reading
- **Book**: "Kubernetes in Action" by Marko Lukša (Chapters 1-4)
- **Free**: Official Kubernetes tutorials - [Learn Kubernetes Basics](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
- **This Repo**: [KUBERNETES_REFERENCE.md](KUBERNETES_REFERENCE.md)

### Setup: Local Kubernetes Cluster

**Option A: kind (Kubernetes in Docker)**
```bash
# Install kind
# Windows: choco install kind
# Mac: brew install kind

# Create cluster
kind create cluster --name vidx-local

# Verify
kubectl cluster-info
kubectl get nodes
```

**Option B: Minikube**
```bash
# Install minikube
# Windows: choco install minikube
# Mac: brew install minikube

minikube start --driver=docker
kubectl get nodes
```

### Hands-On Exercises

#### Exercise 2.1: Deploy Backend to Kubernetes
```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Deploy MongoDB first (StatefulSet)
kubectl apply -f k8s/mongodb-secret.yaml
kubectl apply -f k8s/mongodb-configmap.yaml
kubectl apply -f k8s/mongodb-statefulset.yaml

# Watch it start
kubectl get pods -n vidx-prod -w

# Check logs
kubectl logs -f mongodb-0 -n vidx-prod
```

**Compare to Docker Compose:**
- Docker: `docker-compose up mongodb`
- K8s: Multiple YAML files, explicit dependencies

**Why?** Kubernetes gives you fine-grained control for production

#### Exercise 2.2: Deploy Backend Service
```bash
# Apply ConfigMap and Secret first
kubectl apply -f k8s/backend-secret.yaml
kubectl apply -f k8s/backend-configmap.yaml

# Deploy the backend
kubectl apply -f k8s/backend-deployment.yaml

# Check status
kubectl get deployment -n vidx-prod
kubectl get pods -n vidx-prod

# Describe a pod (see events)
kubectl describe pod <backend-pod-name> -n vidx-prod
```

**Read the YAML:** [k8s/backend-deployment.yaml](k8s/backend-deployment.yaml)

**Understand:**
```yaml
spec:
  replicas: 2          # Why 2? (High availability)
  resources:
    requests:          # Scheduling: "I need at least this"
    limits:            # Safety: "Don't let me use more than this"
  livenessProbe:       # Health check: restart if failing
  readinessProbe:      # Traffic: don't send requests if not ready
```

#### Exercise 2.3: Understand Services (Networking)
```bash
# Create service
kubectl apply -f k8s/backend-deployment.yaml  # includes Service

# Get service details
kubectl get svc -n vidx-prod
kubectl describe svc vidx-backend -n vidx-prod

# Port forward to access locally
kubectl port-forward svc/vidx-backend 8000:8000 -n vidx-prod

# Test in another terminal
curl http://localhost:8000/docs
```

**Key Concept:** Service = stable IP/DNS for Pods (which come and go)

#### Exercise 2.4: Horizontal Pod Autoscaling
```bash
# Install metrics server (required for HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# For local testing, patch it to work with self-signed certs
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Deploy HPA
kubectl apply -f k8s/backend-hpa.yaml

# Watch it work
kubectl get hpa -n vidx-prod -w

# Generate load (in another terminal)
kubectl run -it --rm load-generator --image=busybox /bin/sh
# Inside the pod:
while true; do wget -q -O- http://vidx-backend.vidx-prod.svc.cluster.local:8000/health; done
```

**Read:** [k8s/backend-hpa.yaml](k8s/backend-hpa.yaml)

**Understand:**
- `minReplicas: 2` - Always at least 2 (high availability)
- `maxReplicas: 10` - Never more than 10 (cost control)
- `averageUtilization: 70` - Scale up if CPU > 70%

**Question:** Why not set CPU target to 90%? (Leaves no headroom for spikes)

#### Exercise 2.5: Rolling Updates (Zero Downtime)
```bash
# Check current image
kubectl get deployment vidx-backend -n vidx-prod -o yaml | grep image:

# Update to a new image version
kubectl set image deployment/vidx-backend \
  vidx-backend=<your-ecr-repo>/vidx-backend:v2.0 \
  -n vidx-prod

# Watch rollout
kubectl rollout status deployment/vidx-backend -n vidx-prod

# See revision history
kubectl rollout history deployment/vidx-backend -n vidx-prod

# Rollback if needed
kubectl rollout undo deployment/vidx-backend -n vidx-prod
```

**Key Concept:** Kubernetes replaces Pods gradually (rolling update)

### Checkpoint Questions
- [ ] What's the difference between a Pod and a Deployment?
- [ ] Why do we need a Service if Pods have IPs?
- [ ] How does HPA know when to scale? (Metrics Server)
- [ ] If a Pod crashes, who restarts it? (Deployment controller)
- [ ] How is `kubectl apply` different from `docker-compose up`?

### Common Gotchas
- **"ImagePullBackOff"**: Check image name and registry auth
- **"CrashLoopBackOff"**: Check logs (`kubectl logs`), likely app error
- **"Pending"**: Not enough resources, check `kubectl describe pod`

### Resources
- [Kubernetes Concepts](https://kubernetes.io/docs/concepts/)
- This repo: [KUBERNETES_REFERENCE.md](KUBERNETES_REFERENCE.md)

---

## Phase 3: Infrastructure as Code (Week 5-6)

### Learning Goals
- Understand Terraform: declarative infrastructure
- Grasp AWS building blocks: VPC, subnets, security groups, IAM
- Know how to provision EKS cluster + node groups

### Reading
- **Book**: "Terraform: Up and Running" by Yevgeniy Brikman (Chapters 1-3)
- **Free**: [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- **This Repo**: Start with [README_INFRASTRUCTURE.md](README_INFRASTRUCTURE.md) - Terraform section

### Setup: Terraform + AWS Account

**Install Terraform:**
```powershell
# Windows
choco install terraform

# Or download from terraform.io
```

**AWS Account:**
- Sign up for AWS Free Tier
- Create IAM user with admin access
- Configure AWS CLI:
```bash
aws configure
# Enter Access Key ID, Secret, Region (us-east-1)
```

### Hands-On Exercises

#### Exercise 3.1: Understand Terraform Structure
Read these files in order:

1. **[terraform/provider.tf](terraform/provider.tf)** - AWS connection config
2. **[terraform/variables.tf](terraform/variables.tf)** - Input parameters
3. **[terraform/vpc.tf](terraform/vpc.tf)** - Network setup
4. **[terraform/eks.tf](terraform/eks.tf)** - Kubernetes cluster
5. **[terraform/batch.tf](terraform/batch.tf)** - Video processing compute

**Key Pattern:**
```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  # This declares "I want a VPC with this IP range"
  # Terraform will create it when you run `terraform apply`
}
```

#### Exercise 3.2: Run Terraform Locally (Dry Run)
```bash
cd terraform

# Initialize (download providers)
terraform init

# Check what would be created
terraform plan -var-file=terraform.dev.tfvars

# Review the output
# How many resources would be created?
# Can you identify: VPC, subnets, EKS cluster, node groups?
```

**Read:** [terraform/terraform.dev.tfvars](terraform/terraform.dev.tfvars) vs [terraform/terraform.prod.tfvars](terraform/terraform.prod.tfvars)

**Understand differences:**
- Dev: Smaller instances, fewer nodes (cost savings)
- Prod: Larger instances, more replicas (reliability)

#### Exercise 3.3: Understand VPC and Networking
**Read:** [terraform/vpc.tf](terraform/vpc.tf)

**Draw it out (on paper or whiteboard):**
```
VPC (10.0.0.0/16)
├─ Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│  └─ Internet Gateway (for load balancers)
└─ Private Subnets (10.0.10.0/24, 10.0.11.0/24)
   └─ NAT Gateway (backend can reach internet)
      └─ EKS Nodes live here
```

**Why private subnets?** Security - backend not directly exposed to internet

**Question to Answer:**
- How do Pods in private subnet access the internet? (NAT Gateway)
- Why multiple subnets? (Multi-AZ for high availability)

#### Exercise 3.4: Understand EKS Node Groups
**Read:** [terraform/eks.tf](terraform/eks.tf) starting at line 165

```hcl
resource "aws_eks_node_group" "main" {
  scaling_config {
    desired_size = var.node_group_desired_size  # Usually 2
    max_size     = var.node_group_max_size      # Usually 10
    min_size     = var.node_group_min_size      # Usually 1
  }
  
  instance_types = var.node_group_instance_types  # e.g., ["t3.medium"]
  capacity_type  = var.node_group_capacity_type   # ON_DEMAND or SPOT
}
```

**Understand:**
- **Node group** = AWS Auto Scaling Group of EC2 instances
- **desired_size** = How many nodes to start with
- **Scaling** = Can grow/shrink based on load
- **instance_types** = Size of machines (CPU/RAM)

**Compare to Heroku:** Heroku picks instance type for you; here you control it

#### Exercise 3.5: Cost Analysis
Open: [terraform/terraform.prod.tfvars](terraform/terraform.prod.tfvars)

**Estimate monthly cost:**
```
EKS Control Plane: $73/month (flat fee)
Node Group (3x t3.medium): 3 × $30/month = $90
MongoDB Atlas (M10): ~$60/month
RDS (if used): ~$50/month
S3 + Bandwidth: ~$20/month
Total: ~$300/month minimum
```

**Why this matters:** Unlike Heroku ($25/month), you pay for running infrastructure

**Cost optimization strategies:**
- Use Spot instances (60-90% cheaper, can be interrupted)
- Use Savings Plans / Reserved Instances (1-3 year commitment)
- Scale down in non-business hours
- Use Fargate for batch jobs (pay per-second)

### Checkpoint Questions
- [ ] What does `terraform plan` do? (Shows changes without applying)
- [ ] What's the difference between public and private subnets?
- [ ] Why do we need IAM roles? (Give AWS services permissions)
- [ ] How does EKS node group scaling work? (Auto Scaling Groups)
- [ ] What happens if you run `terraform destroy`? (Deletes everything!)

### Resources
- [Terraform AWS Examples](https://github.com/hashicorp/terraform-provider-aws/tree/main/examples)
- [AWS VPC Docs](https://docs.aws.amazon.com/vpc/)

---

## Phase 4: Production Deployment (Week 7-8)

### Learning Goals
- Deploy to real AWS environment
- Understand monitoring and observability
- Learn incident response and debugging
- Grasp cost management in production

### Reading
- **Book**: "Site Reliability Engineering" (Google) - Chapters 1-4
- **Free**: [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- **This Repo**: [TASK_EXECUTION_GUIDE.md](TASK_EXECUTION_GUIDE.md) - Infrastructure section

### Prerequisites
- Completed Phase 1-3
- AWS account with billing alerts set up
- Domain name (optional, for custom URLs)

### Hands-On Exercises

#### Exercise 4.1: Deploy to AWS (Staging)
```bash
cd terraform

# Set AWS credentials
export AWS_PROFILE=your-profile

# Deploy staging environment
terraform apply -var-file=terraform.dev.tfvars

# This will create:
# - VPC with subnets
# - EKS cluster (takes 10-15 minutes)
# - Node groups
# - S3 buckets
# - IAM roles

# Watch it build
# Cost: ~$150/month for dev environment
```

**Update kubectl config:**
```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name vidx-dev-cluster
  
# Verify
kubectl get nodes
# You should see your EKS nodes
```

#### Exercise 4.2: Deploy Application to EKS
```bash
# Create namespace
kubectl apply -f k8s/namespace.yaml

# Deploy secrets (update with real values first!)
kubectl apply -f k8s/mongodb-secret.yaml
kubectl apply -f k8s/backend-secret.yaml

# Deploy stateful services
kubectl apply -f k8s/mongodb-statefulset.yaml
kubectl apply -f k8s/rabbitmq-statefulset.yaml

# Wait for them to be ready
kubectl wait --for=condition=ready pod -l app=mongodb -n vidx-prod --timeout=5m

# Deploy backend
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-hpa.yaml

# Deploy workers
kubectl apply -f k8s/worker-deployment.yaml

# Check everything
kubectl get all -n vidx-prod
```

#### Exercise 4.3: Expose Backend to Internet
```bash
# Apply ingress (creates AWS Load Balancer)
kubectl apply -f k8s/ingress.yaml

# Get load balancer URL
kubectl get ingress -n vidx-prod

# Wait for it to be provisioned (5-10 minutes)
# Then access:
curl http://<load-balancer-url>/health
```

**Read:** [k8s/ingress.yaml](k8s/ingress.yaml) to understand routing

#### Exercise 4.4: Monitor Your Cluster

**Install Metrics Server (if not already):**
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Watch resource usage:**
```bash
# Node metrics
kubectl top nodes

# Pod metrics
kubectl top pods -n vidx-prod

# Watch HPA in action
kubectl get hpa -n vidx-prod -w
```

**View logs (CloudWatch):**
```bash
# From AWS CLI
aws logs tail /aws/eks/vidx-dev-cluster/cluster --follow

# Or use kubectl
kubectl logs -f deployment/vidx-backend -n vidx-prod
```

#### Exercise 4.5: Test Scalability
```bash
# Generate load
kubectl run load-test -n vidx-prod --image=williamyeh/hey:latest -- \
  -z 5m -c 50 http://vidx-backend.vidx-prod.svc.cluster.local:8000/health

# Watch in another terminal
watch -n 1 kubectl get hpa -n vidx-prod
watch -n 1 kubectl get pods -n vidx-prod

# Observe:
# - Pods scale up when CPU > 70%
# - Nodes scale up when pods can't be scheduled
# - Pods scale down after 5 minutes of low load
```

#### Exercise 4.6: Simulate Failure (Chaos Engineering)

**Test pod recovery:**
```bash
# Delete a backend pod
kubectl delete pod <backend-pod-name> -n vidx-prod

# Watch Kubernetes recreate it
kubectl get pods -n vidx-prod -w
```

**Test node failure:**
```bash
# Drain a node (simulate node dying)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Watch pods move to other nodes
kubectl get pods -n vidx-prod -o wide

# Uncordon when done
kubectl uncordon <node-name>
```

**Test database failure:**
```bash
# Delete MongoDB pod
kubectl delete pod mongodb-0 -n vidx-prod

# Does StatefulSet recreate it?
# Do backends reconnect automatically?
# Check backend logs for connection retries
```

### Checkpoint Questions
- [ ] How long does it take to provision an EKS cluster? (~15 minutes)
- [ ] What happens if you delete a Pod? (Deployment recreates it)
- [ ] How do you update backend code in production? (Build new image, update deployment)
- [ ] Where are logs stored? (CloudWatch + Pod stdout)
- [ ] How much does this cost per month? (Check AWS billing dashboard)

### Incident Response Playbook

**Backend is down:**
```bash
# 1. Check pod status
kubectl get pods -n vidx-prod

# 2. Check recent events
kubectl get events -n vidx-prod --sort-by='.lastTimestamp'

# 3. Check logs
kubectl logs -l app=vidx-backend -n vidx-prod --tail=100

# 4. Describe failing pod
kubectl describe pod <pod-name> -n vidx-prod

# Common issues:
# - ImagePullBackOff: Wrong image tag or ECR auth issue
# - CrashLoopBackOff: App failing to start (check env vars)
# - Pending: Not enough CPU/RAM (check node resources)
```

**High latency:**
```bash
# Check if HPA is maxed out
kubectl get hpa -n vidx-prod

# Check node resources
kubectl top nodes

# Check pod resources
kubectl top pods -n vidx-prod

# Scale manually if needed
kubectl scale deployment vidx-backend --replicas=5 -n vidx-prod
```

---

## Phase 5: Advanced Topics (Week 9+)

### Multi-Region Architecture

**Reading:**
- "Designing Data-Intensive Applications" - Chapter 5 (Replication)
- "Building Microservices" - Chapter 11 (Resilience)

**Concepts to Learn:**
- **Active-Active** vs **Active-Passive** regions
- **Data consistency**: CAP theorem, eventual consistency
- **Cross-region latency**: 50-100ms+ between regions
- **Cost**: Data transfer between regions is expensive

**Why multi-region?**
1. **Disaster recovery**: If us-east-1 goes down, fail over to eu-west-1
2. **Low latency**: Serve users from closest region
3. **Compliance**: Some data must stay in specific countries (GDPR)

**This repo doesn't implement multi-region yet**, but here's how you would:

```
Region: us-east-1                Region: eu-west-1
┌─────────────────┐             ┌─────────────────┐
│  EKS Cluster    │             │  EKS Cluster    │
│  Backend Pods   │             │  Backend Pods   │
└────────┬────────┘             └────────┬────────┘
         │                               │
         ▼                               ▼
┌─────────────────┐             ┌─────────────────┐
│ MongoDB Replica │◄───────────►│ MongoDB Replica │
│ (Primary)       │   Sync      │ (Secondary)     │
└─────────────────┘             └─────────────────┘
         ▲
         │
    ┌────┴────┐
    │ Route53 │ (DNS-based routing)
    │ Geo     │ (sends EU users to EU region)
    └─────────┘
```

**Challenge:** What happens if a user uploads a video in us-east-1, then queries from eu-west-1 before replication finishes? (Eventual consistency problem)

### Karpenter (Advanced Autoscaling)

**Reading:**
- [Karpenter Docs](https://karpenter.sh/)
- This repo: See discussion in GitHub issues (if created)

**When to consider:**
- High cost from under-utilized nodes
- Need second-level scaling for bursty workloads
- Want more control over instance type selection

**Implementation steps (future):**
1. Install Karpenter controller
2. Create Provisioner resource
3. Migrate batch workloads from AWS Batch to K8s Jobs
4. Monitor cost savings vs operational overhead

### Service Mesh (Istio/Linkerd)

**Why?**
- Observability: Track requests between services
- Security: mTLS between all pods
- Traffic management: Canary deployments, A/B testing

**When to consider:**
- More than 5 microservices
- Need fine-grained traffic control
- Security compliance requires encryption everywhere

### GitOps (ArgoCD/Flux)

**Concept:** Git as source of truth for infrastructure

**Current:** You run `kubectl apply` manually  
**GitOps:** Merge PR → Automated deployment to cluster

**Benefit:** All changes are audited, can rollback easily

---

## Key Concepts Reference

### Consistency Models

| Model | Example | Trade-off |
|-------|---------|-----------|
| **Strong consistency** | Traditional SQL, single-region | Slow, but always correct |
| **Eventual consistency** | Multi-region MongoDB, S3 | Fast, but temporary stale reads |
| **Causal consistency** | Newer NoSQL systems | Middle ground |

**In this repo:** MongoDB Atlas uses eventual consistency for cross-region replication

### CAP Theorem

You can only pick 2 of 3:
- **Consistency**: All nodes see same data
- **Availability**: System always responds
- **Partition tolerance**: System works even if network splits

**AWS choice:** AP (Available + Partition tolerant) - prioritize uptime

### Scalability Patterns

| Pattern | Example in This Repo |
|---------|---------------------|
| **Horizontal scaling** | HPA adds more backend Pods |
| **Vertical scaling** | Increase Pod resource requests |
| **Sharding** | MongoDB sharding (not implemented yet) |
| **Caching** | Redis for session state |
| **Async processing** | Celery + RabbitMQ for video jobs |

### Cost Optimization

**Current monthly cost (estimated):**
```
EKS Control Plane:        $73
3 × t3.medium nodes:      $90
MongoDB Atlas (M10):      $60
S3 (500GB):               $11
Data transfer:            $20
Load Balancer:            $16
CloudWatch:               $10
─────────────────────────────
Total:                   ~$280/month
```

**Optimization opportunities:**
1. **Reserved Instances**: Save 40% on nodes (1-year commit)
2. **Spot Instances**: Save 70% for batch jobs (can be interrupted)
3. **S3 Intelligent-Tiering**: Auto-move old files to Glacier
4. **Right-sizing**: Use t3.small instead of t3.medium if possible

---

## Debugging Cheat Sheet

### Pod Won't Start
```bash
# 1. Describe pod (check events)
kubectl describe pod <pod-name> -n vidx-prod

# 2. Check logs
kubectl logs <pod-name> -n vidx-prod

# 3. Check previous logs (if crashed)
kubectl logs <pod-name> -n vidx-prod --previous

# 4. Check if image exists
kubectl get pod <pod-name> -n vidx-prod -o jsonpath='{.spec.containers[0].image}'

# 5. Exec into pod (if running)
kubectl exec -it <pod-name> -n vidx-prod -- /bin/bash
```

### Service Not Accessible
```bash
# 1. Check if pods are ready
kubectl get pods -n vidx-prod -l app=vidx-backend

# 2. Check service endpoints
kubectl get endpoints vidx-backend -n vidx-prod

# 3. Port forward to test
kubectl port-forward svc/vidx-backend 8000:8000 -n vidx-prod
curl http://localhost:8000/health

# 4. Check ingress
kubectl describe ingress -n vidx-prod
```

### High Memory/CPU
```bash
# Check current usage
kubectl top pods -n vidx-prod

# Check resource requests/limits
kubectl get pod <pod-name> -n vidx-prod -o yaml | grep -A 5 resources

# Check node pressure
kubectl describe node <node-name> | grep -A 10 Conditions
```

---

## Next Steps After This Path

1. **Build a CI/CD pipeline**
   - GitHub Actions → Build Docker image → Push to ECR → Deploy to EKS
   - See: [GitHub Actions for EKS](https://github.com/aws-actions/amazon-eks-action)

2. **Add observability**
   - Metrics: Prometheus + Grafana
   - Logs: ELK Stack or CloudWatch Insights
   - Tracing: Jaeger or AWS X-Ray
   - See: [OBSERVABILITY_TODO.md](OBSERVABILITY_TODO.md)

3. **Implement disaster recovery**
   - Multi-region MongoDB replica set
   - Cross-region S3 replication
   - Route53 health checks + failover

4. **Security hardening**
   - See: [SECURITY_IMPROVEMENTS.md](SECURITY_IMPROVEMENTS.md)
   - Implement network policies (already in `k8s/network-policies.yaml`)
   - Add WAF in front of ALB
   - Rotate secrets automatically

5. **Consider Karpenter**
   - If costs are high or need faster scaling
   - See earlier discussion about AWS Batch vs K8s Jobs

---

## Recommended Books (Ordered by Priority)

### Must Read (Core)
1. **"Designing Data-Intensive Applications"** - Martin Kleppmann
   - The bible of distributed systems
   - Teaches fundamental trade-offs
   
2. **"Kubernetes in Action"** - Marko Lukša
   - Best K8s book for beginners
   - Hands-on and practical

### Highly Recommended
3. **"Site Reliability Engineering"** - Google
   - Free online: [sre.google/books](https://sre.google/books/)
   - Teaches operational excellence
   
4. **"Terraform: Up and Running"** - Yevgeniy Brikman
   - Best practices for IaC
   - AWS-focused examples

### Nice to Have
5. **"Building Microservices"** - Sam Newman
   - When to split services
   - Communication patterns
   
6. **"The Phoenix Project"** - Gene Kim
   - Novel about DevOps transformation
   - Easy, inspiring read

---

## Questions at Each Phase

### After Phase 1 (Docker)
- Can I run the full stack locally? ✅
- Do I understand what each service does? ✅
- Can I debug connection issues? ✅

### After Phase 2 (Kubernetes)
- Can I deploy to local K8s cluster? ✅
- Do I understand Pod lifecycle? ✅
- Can I read YAML and understand resources? ✅

### After Phase 3 (Terraform)
- Can I read Terraform and understand what it creates? ✅
- Do I understand VPC, subnets, IAM? ✅
- Can I estimate AWS costs? ✅

### After Phase 4 (Production)
- Can I deploy to real AWS? ✅
- Can I debug production issues? ✅
- Do I understand monitoring and scaling? ✅

### After Phase 5 (Advanced)
- Do I understand multi-region trade-offs? ✅
- Can I make build-vs-buy decisions (Karpenter, service mesh)? ✅
- Can I design resilient systems? ✅

---

## Getting Help

**Stuck on something?**
1. Check this repo's documentation (most answers are here)
2. Search GitHub Issues for this repo
3. AWS Documentation: [docs.aws.amazon.com](https://docs.aws.amazon.com)
4. Kubernetes Docs: [kubernetes.io/docs](https://kubernetes.io/docs)
5. Stack Overflow (search first, ask later)

**Best practices:**
- Always search before asking
- Include error messages and logs
- Show what you've tried
- Ask specific questions

---

## Final Thoughts

**You're learning 5+ years of cloud evolution in 8-12 weeks.** It will feel overwhelming. That's normal.

**Key mindset shifts:**
- Heroku: "It just works" → Cloud: "You control everything (and must debug everything)"
- Single machine: "Scale up" → Distributed: "Scale out"
- Mutable: "SSH and fix" → Immutable: "Deploy new version"

**The loop:**
1. Run it locally (Phase 1)
2. Understand the concepts (Phase 2-3)
3. Deploy to cloud (Phase 4)
4. Break it and fix it (Phase 4)
5. Repeat with more complex topics (Phase 5)

**Most important:** The infrastructure exists to serve the application. Don't over-optimize for problems you don't have yet. Start simple, iterate.

Good luck! 🚀
