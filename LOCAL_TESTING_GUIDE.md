# LOCAL TESTING QUICKSTART

**Goal**: Run and test the video processing system locally before AWS deployment.

**Time**: 15-20 minutes

---

## Prerequisites

✅ Docker Desktop running (8GB+ RAM)  
✅ Docker Compose v2.0+  
✅ Ports available: 4566, 8000, 5672, 6379, 27017  
✅ PowerShell or Bash terminal

---

## Quick Start (5 minutes)

### 1. Start all services
```powershell
# From project root
docker-compose -f docker-compose.localstack.yml up -d

# Wait for services (30-60 seconds)
docker-compose -f docker-compose.localstack.yml ps
```

**Services started:**
- LocalStack (mock AWS on port 4566)
- MongoDB (port 27017)
- RabbitMQ (port 5672)
- Redis (port 6379) - **for persistent state**

### 2. Initialize AWS resources in LocalStack
```powershell
# Run initialization script
bash localstack-init.sh

# Or manually:
aws --endpoint-url=http://localhost:4566 s3 mb s3://vidx-video-storage
```

### 3. Start backend and workers
```powershell
docker-compose up -d api celery

# Check health
curl http://localhost:8000/api/health
```

**Done!** System is running.

---

## Test Video Processing

### Submit a test job
```powershell
# Using Python
python -c "
import requests
resp = requests.post('http://localhost:8000/api/videos/merge', json={
    'videos': [{'path': '/tmp/v1.mp4', 'duration': 10}, {'path': '/tmp/v2.mp4', 'duration': 10}],
    'transition': 'fade',
    'user_tier': 'basic'
})
print('Task ID:', resp.json()['task_id'])
"

# Or curl
curl -X POST http://localhost:8000/api/videos/merge \
  -H "Content-Type: application/json" \
  -d '{"videos":[{"path":"/tmp/v1.mp4","duration":10}],"transition":"fade","user_tier":"basic"}'
```

### Check task status
```powershell
# Replace TASK_ID with actual ID from above
curl http://localhost:8000/api/tasks/TASK_ID

# Expected response:
# {"status": "RUNNING", "job_id": "...", "output_path": null, "error": null}
```

---

## Test State Persistence (Redis)

### Verify state survives pod restart
```powershell
# 1. Submit a task (get task_id)
curl -X POST http://localhost:8000/api/videos/merge ...
# Note the task_id: abc-123

# 2. Restart worker
docker-compose restart celery

# 3. Check task status - should still exist!
curl http://localhost:8000/api/tasks/abc-123
# ✅ Status still returned = state persistence works
```

### Inspect Redis directly
```powershell
# Connect to Redis
docker exec -it $(docker ps -qf "name=redis") redis-cli

# List all tasks
127.0.0.1:6379> KEYS vidx:task:*
# Output: 1) "vidx:task:abc-123"

# Get task state
127.0.0.1:6379> GET vidx:task:abc-123
# Output: {"task_id":"abc-123","status":"RUNNING",...}
```

---

## Test AWS Batch Mode (LocalStack)

### Switch executor to AWS Batch
```powershell
# Stop workers
docker-compose stop celery

# Set environment variable
# Edit docker-compose.yml:
# environment:
#   TASK_EXECUTION_STRATEGY: aws-batch

# Restart
docker-compose up -d celery
```

### Verify Batch job submission
```powershell
# Submit task
curl -X POST http://localhost:8000/api/videos/merge ...

# Check LocalStack Batch
aws --endpoint-url=http://localhost:4566 batch list-jobs --job-queue vidx-processing-queue

# Should see job submitted
```

**Note**: LocalStack Batch jobs won't actually execute. Use local mode for real testing.

---

## View Logs

```powershell
# All services
docker-compose logs -f

# Just worker
docker-compose logs -f celery

# Just backend
docker-compose logs -f api

# Filter errors
docker-compose logs celery | grep ERROR
```

---

## Architecture (Local Mode)

```
Your PC
  │
  ├─ FastAPI (port 8000) ──► MongoDB
  │                       └► Redis (state)
  │
  └─ Celery Worker
       │
       ├─ TaskExecutionManager
       │    └─ LocalProcessExecutor
       │         └─ FFmpeg (direct execution)
       │
       └─ State stored in Redis ✅
            (survives pod restarts)
```

---

## Troubleshooting

**Issue**: "Connection refused localhost:6379"
```powershell
# Redis not running - add to docker-compose.localstack.yml:
redis:
  image: redis:7-alpine
  ports:
    - "6379:6379"
```

**Issue**: "Task not found after restart"
```powershell
# State manager not initialized
# Check celery logs:
docker-compose logs celery | grep state_manager
```

**Issue**: "Worker not processing tasks"
```powershell
# Check RabbitMQ connection
docker-compose logs celery | grep "Connected to amqp"
```

---

## Cleanup

```powershell
# Stop all services
docker-compose down
docker-compose -f docker-compose.localstack.yml down

# Remove volumes (full reset)
docker-compose down -v
docker-compose -f docker-compose.localstack.yml down -v
```

---

## Next Steps

### For Development:
1. ✅ Test locally with sample videos
2. ✅ Verify state persistence works
3. ✅ Check logs for errors
4. → Read [DEPLOYMENT_QUICKSTART.md](DEPLOYMENT_QUICKSTART.md) for AWS deployment

### For Production:
1. Deploy infrastructure: `cd terraform && terraform apply`
2. Deploy K8s: `kubectl apply -k k8s/`
3. Switch to `aws-batch` executor
4. Enable monitoring (see [OBSERVABILITY_TODO.md](OBSERVABILITY_TODO.md))

---

## Success Checklist

- [ ] LocalStack healthy: `curl http://localhost:4566/_localstack/health`
- [ ] Backend running: `curl http://localhost:8000/api/health`
- [ ] Task submitted successfully
- [ ] Task status returns valid response
- [ ] State persists after worker restart
- [ ] Redis contains task data
- [ ] No errors in logs

**All checks pass? Ready for production!**
