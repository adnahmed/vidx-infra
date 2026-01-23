# Kubernetes Deployment Reference

## Quick Commands

### View Resources
```bash
# Get all resources in namespace
kubectl get all -n vidx-prod

# Get pods with details
kubectl get pods -n vidx-prod -o wide

# Get services
kubectl get svc -n vidx-prod

# Get deployments
kubectl get deployment -n vidx-prod

# Get StatefulSets
kubectl get statefulset -n vidx-prod

# Get HPA status
kubectl get hpa -n vidx-prod
```

### View Logs
```bash
# Stream backend logs
kubectl logs -f deployment/vidx-backend -n vidx-prod

# View logs from specific pod
kubectl logs <pod-name> -n vidx-prod

# View previous logs
kubectl logs <pod-name> --previous -n vidx-prod

# Tail logs from multiple pods
kubectl logs -f -l app=vidx-backend -n vidx-prod
```

### Port Forwarding
```bash
# Forward API to local machine
kubectl port-forward svc/vidx-backend 8000:8000 -n vidx-prod

# Forward MongoDB
kubectl port-forward svc/mongodb 27017:27017 -n vidx-prod

# Forward RabbitMQ management
kubectl port-forward svc/rabbitmq 15672:15672 -n vidx-prod
```

### Debugging
```bash
# Describe pod for events and details
kubectl describe pod <pod-name> -n vidx-prod

# Get pod yaml
kubectl get pod <pod-name> -n vidx-prod -o yaml

# Execute command in pod
kubectl exec -it <pod-name> -n vidx-prod -- /bin/bash

# Check resource usage
kubectl top pods -n vidx-prod
kubectl top nodes
```

### Update Configuration
```bash
# Edit secrets
kubectl edit secret vidx-backend-secret -n vidx-prod

# Edit configmap
kubectl edit configmap vidx-backend-config -n vidx-prod

# Apply new image
kubectl set image deployment/vidx-backend \
  vidx-backend=123456789012.dkr.ecr.us-east-1.amazonaws.com/vidx-backend:v1.0 \
  -n vidx-prod
```

### Rollout Management
```bash
# Check rollout status
kubectl rollout status deployment/vidx-backend -n vidx-prod

# Get rollout history
kubectl rollout history deployment/vidx-backend -n vidx-prod

# Rollback to previous version
kubectl rollout undo deployment/vidx-backend -n vidx-prod

# Rollback to specific revision
kubectl rollout undo deployment/vidx-backend --to-revision=2 -n vidx-prod

# Restart deployment
kubectl rollout restart deployment/vidx-backend -n vidx-prod
```

### Scale Resources
```bash
# Manual scale
kubectl scale deployment vidx-backend --replicas=5 -n vidx-prod

# Check HPA
kubectl describe hpa vidx-backend-hpa -n vidx-prod
```

### Delete Resources
```bash
# Delete specific pod
kubectl delete pod <pod-name> -n vidx-prod

# Delete all pods in namespace
kubectl delete pods --all -n vidx-prod

# Delete deployment
kubectl delete deployment vidx-backend -n vidx-prod
```

## Monitoring

### Check Pod Events
```bash
kubectl get events -n vidx-prod --sort-by='.lastTimestamp'
```

### Monitor Resource Usage
```bash
# Pod resource usage
kubectl top pods -n vidx-prod

# Node resource usage
kubectl top nodes

# Continuous monitoring
watch kubectl top pods -n vidx-prod
```

### Check HPA Metrics
```bash
# View HPA status
kubectl get hpa -n vidx-prod -w

# Detailed HPA status
kubectl describe hpa vidx-backend-hpa -n vidx-prod
```

## Networking

### Check DNS
```bash
# Resolve service name
kubectl run -it --rm debug --image=busybox --restart=Never -n vidx-prod -- \
  nslookup vidx-backend

# Resolve external DNS
kubectl run -it --rm debug --image=busybox --restart=Never -n vidx-prod -- \
  nslookup google.com
```

### Check Connectivity
```bash
# Test connection to backend
kubectl run -it --rm debug --image=busybox --restart=Never -n vidx-prod -- \
  wget -O- http://vidx-backend:8000/api/health

# Test connection to MongoDB
kubectl run -it --rm debug --image=mongo --restart=Never -n vidx-prod -- \
  mongosh -u vidx -p vidx mongodb:27017/vidx
```

## Backup & Restore

### MongoDB Backup
```bash
# Export data
kubectl exec -it mongodb-0 -n vidx-prod -- \
  mongodump --out /tmp/backup -u vidx -p vidx --authenticationDatabase admin

# Copy backup to local
kubectl cp vidx-prod/mongodb-0:/tmp/backup ./backup
```

### MongoDB Restore
```bash
# Copy restore data to pod
kubectl cp ./backup vidx-prod/mongodb-0:/tmp/backup

# Restore data
kubectl exec -it mongodb-0 -n vidx-prod -- \
  mongorestore /tmp/backup -u vidx -p vidx --authenticationDatabase admin
```

## Troubleshooting

### Pod Stuck in Pending
```bash
# Check why pod can't be scheduled
kubectl describe pod <pod-name> -n vidx-prod

# Check node availability
kubectl get nodes
kubectl describe nodes
```

### Pod Crashes
```bash
# Check pod status
kubectl describe pod <pod-name> -n vidx-prod

# View error logs
kubectl logs <pod-name> --previous -n vidx-prod
```

### Database Connection Issues
```bash
# Test from pod
kubectl exec -it <pod-name> -n vidx-prod -- \
  python -c "import pymongo; print(pymongo.__version__)"

# Check database service
kubectl get svc mongodb -n vidx-prod
kubectl get endpoints mongodb -n vidx-prod
```

### Network Issues
```bash
# Check network policies
kubectl get networkpolicy -n vidx-prod

# Check service discovery
kubectl get svc -n vidx-prod
kubectl get endpoints -n vidx-prod

# Test DNS
kubectl run -it --rm debug --image=busybox --restart=Never -n vidx-prod -- nslookup vidx-backend
```

## Helm Integration

For production deployments with Helm:

```bash
# Create Helm chart from manifests
helm create vidx-infra

# Install
helm install vidx ./vidx-infra -n vidx-prod

# Upgrade
helm upgrade vidx ./vidx-infra -n vidx-prod

# Rollback
helm rollback vidx -n vidx-prod

# List releases
helm list -n vidx-prod
```
