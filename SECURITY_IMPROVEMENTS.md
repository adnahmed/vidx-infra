# SECURITY IMPROVEMENTS & HARDENING

## Implemented Security Measures

### 1. **Kubernetes Network Policies** ✅
- **File**: `k8s/network-policies.yaml`
- **What it does:**
  - Restricts backend to only talk to MongoDB, RabbitMQ, Redis, and AWS APIs
  - Workers can't receive inbound traffic (only make outbound requests)
  - MongoDB locked down to only accept connections from backend/workers
  - DNS allowed for all pods (required for AWS API calls)

**Impact**: Prevents lateral movement if a pod is compromised.

---

### 2. **Resource Limits** ✅
- **Files**: `k8s/backend-deployment.yaml`, `k8s/worker-deployment.yaml`
- **What it does:**
  - CPU/memory requests and limits prevent:
    - Resource exhaustion attacks
    - One user's video processing hogging all resources
    - OOM kills affecting other pods
  - Backend: 500m-2000m CPU, 1-4Gi memory
  - Workers: 1000m-4000m CPU, 2-8Gi memory

**Impact**: Prevents DoS via resource starvation.

---

### 3. **Pod Security Context** ✅
- **Applied to**: All deployments
- **What it does:**
  - `runAsNonRoot: true` - Containers can't run as root
  - `allowPrivilegeEscalation: false` - Can't gain root privileges
  - `capabilities.drop: ALL` - Removes all Linux capabilities
  - `readOnlyRootFilesystem: false` - FFmpeg needs /tmp (TODO: use tmpfs)

**Impact**: Reduces attack surface if container is compromised.

---

### 4. **Pod Security Standards** ✅
- **File**: `k8s/network-policies.yaml` (namespace label)
- **What it does:**
  - Enforces "restricted" pod security standard
  - Kubernetes automatically blocks insecure pod specs
  - Enforced at namespace level

**Impact**: Prevents accidental deployment of insecure containers.

---

### 5. **Persistent State Management** ✅
- **File**: `backend/vidx/services/task_execution/state_manager.py`
- **What it does:**
  - Job state stored in Redis (not in-memory)
  - Survives pod restarts
  - Prevents job loss on crashes

**Impact**: Jobs don't disappear, better auditability.

---

## 🚨 CRITICAL MISSING SECURITY (TODO)

### 1. **IAM Roles for Service Accounts (IRSA)** ❌
**Problem**: AWS credentials hardcoded in environment variables
```yaml
# CURRENT (INSECURE):
env:
  - name: AWS_ACCESS_KEY_ID
    value: "AKIAIOSFODNN7EXAMPLE"  # ❌ Visible in pod spec
```

**Solution**: Use IRSA (IAM Roles for Service Accounts)
```yaml
# SECURE:
serviceAccountName: vidx-backend
# No credentials in env vars - automatic via IRSA
```

**How to implement:**
1. Create IAM role with Batch/S3 permissions
2. Annotate Kubernetes ServiceAccount with IAM role ARN
3. Remove AWS credentials from env vars
4. AWS SDK automatically uses pod identity

**Priority**: **CRITICAL** - Credentials can be extracted from pod.

---

### 2. **Input Validation & Rate Limiting** ❌
**Problem**: No limits on video uploads
```python
# CURRENT: No validation
async def submit_merge_task(videos: Dict[str, float]):
    # User could upload 1TB video
    # User could submit 1000 jobs simultaneously
```

**Solution**:
```python
# File size validation
MAX_VIDEO_SIZE = 1024 * 1024 * 1024  # 1GB
if file_size > MAX_VIDEO_SIZE:
    raise ValueError("Video too large")

# Rate limiting (per user)
@rate_limit(max_requests=10, window_seconds=60)
async def submit_merge_task(...):
    ...
```

**Priority**: **HIGH** - Can rack up massive AWS bills.

---

### 3. **Secret Management (Kubernetes Secrets)** ❌
**Problem**: Secrets in ConfigMaps or plain env vars
```yaml
# INSECURE:
env:
  - name: VIDX_DB_PASS
    value: "vidx"  # Visible to anyone with kubectl access
```

**Solution**: Use Kubernetes Secrets + AWS Secrets Manager
```yaml
env:
  - name: VIDX_DB_PASS
    valueFrom:
      secretKeyRef:
        name: vidx-secrets
        key: db-password
```

**Better**: Use AWS Secrets Manager + External Secrets Operator
- Secrets never stored in K8s etcd
- Auto-rotation supported
- Centralized secret management

**Priority**: **HIGH** - Database credentials exposed.

---

### 4. **TLS/mTLS for Internal Services** ❌
**Problem**: MongoDB, RabbitMQ connections are unencrypted
```python
# CURRENT:
mongodb://vidx:vidx@mongodb:27017/admin  # No TLS
```

**Solution**: Enable TLS for all internal connections
```python
mongodb://vidx:vidx@mongodb:27017/admin?tls=true&tlsCAFile=/certs/ca.pem
```

**Priority**: **MEDIUM** - Traffic can be sniffed within cluster.

---

### 5. **Image Scanning & Signing** ❌
**Problem**: Docker images not scanned for vulnerabilities

**Solution**:
1. **Scan images**: Use Trivy, Clair, or AWS ECR scanning
   ```bash
   trivy image vidx-backend:latest
   ```
2. **Sign images**: Use Cosign or Notary
   ```bash
   cosign sign vidx-backend:latest
   ```
3. **Verify signatures** in K8s admission controller

**Priority**: **MEDIUM** - Could deploy vulnerable base images.

---

### 6. **Audit Logging** ❌
**Problem**: No audit trail of who did what

**Solution**: Enable Kubernetes audit logging
```yaml
# kube-apiserver config
--audit-log-path=/var/log/kubernetes/audit.log
--audit-policy-file=/etc/kubernetes/audit-policy.yaml
```

Log:
- Who submitted jobs
- Who accessed secrets
- Failed authentication attempts
- Resource modifications

**Priority**: **HIGH** - Can't investigate security incidents.

---

### 7. **AWS Batch Job Validation** ❌
**Problem**: No validation of Batch job parameters
```python
# CURRENT: No checks
container_overrides = {"vcpus": 9999, "memory": 999999}  # Could exceed limits
```

**Solution**: Validate before submission
```python
MAX_VCPUS = 16
MAX_MEMORY = 32768

if vcpus > MAX_VCPUS or memory > MAX_MEMORY:
    raise ValueError("Resource request exceeds limits")
```

**Priority**: **HIGH** - Can exceed budget.

---

### 8. **Cost Budgets & Alerts** ❌
**Problem**: No protection against runaway AWS costs

**Solution**: AWS Budgets + CloudWatch Alarms
```terraform
resource "aws_budgets_budget" "vidx" {
  name              = "vidx-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "500"
  limit_unit        = "USD"
  time_period_start = "2026-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator = "GREATER_THAN"
    threshold           = 80
    threshold_type      = "PERCENTAGE"
    notification_type   = "FORECASTED"
    subscriber_email_addresses = ["admin@example.com"]
  }
}
```

**Priority**: **CRITICAL** - Financial risk.

---

## Security Quick Wins (Implement Now)

### 1. **Update `kustomization.yaml`** to include network policies:
```yaml
resources:
  - namespace.yaml
  - network-policies.yaml  # ADD THIS
  - backend-deployment.yaml
  - worker-deployment.yaml
  ...
```

### 2. **Create secrets properly:**
```bash
kubectl create secret generic vidx-secrets \
  --from-literal=db-password="$(openssl rand -base64 32)" \
  --from-literal=rabbitmq-password="$(openssl rand -base64 32)" \
  -n vidx-prod
```

### 3. **Add admission controller** (validates security policies):
```bash
# Install OPA Gatekeeper
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
```

### 4. **Enable AWS GuardDuty** (threat detection):
```bash
aws guardduty create-detector --enable
```

---

## Compliance Checklist

- [ ] IAM roles instead of hardcoded credentials
- [ ] All secrets in Kubernetes Secrets or AWS Secrets Manager
- [ ] Network policies applied and tested
- [ ] Resource limits on all pods
- [ ] TLS enabled for MongoDB, RabbitMQ
- [ ] Image scanning in CI/CD
- [ ] Audit logging enabled
- [ ] Cost budgets and alerts configured
- [ ] Rate limiting per user
- [ ] Input validation for file uploads

---

## References

- **AWS EKS Security Best Practices**: https://aws.github.io/aws-eks-best-practices/security/docs/
- **CNCF Kubernetes Security**: https://kubernetes.io/docs/concepts/security/
- **OWASP Kubernetes Top 10**: https://owasp.org/www-project-kubernetes-top-ten/
- **Pod Security Standards**: https://kubernetes.io/docs/concepts/security/pod-security-standards/
