# Task Execution Quick Reference

## For API Developers

### Submitting a Video Merge Task

```python
from vidx.services.celery.tasks import merge_videos

# Submit task
task_id = merge_videos.delay(
    videos={
        "/path/to/video1.mp4": 30.0,  # path -> duration
        "/path/to/video2.mp4": 45.0,
    },
    audio="/path/to/audio.mp3",
    video_mime="video/mp4",
    video_resolution=(1920, 1080),
    audio_duration=75.0,
    transition="crossfade",
    user_tier="premium",  # basic, premium, or enterprise
)

# Get result
result = task_id.get(timeout=3600)  # Returns output file path
```

### Tracking Task Status

```python
from vidx.services.celery.tasks import merge_videos

task = merge_videos.delay(...)

# Check status
status = task.status  # PENDING, STARTED, SUCCESS, FAILURE

# Get result when ready
if task.ready():
    if task.successful():
        output_path = task.result
    else:
        error = task.result  # Exception details
```

## For Infrastructure Engineers

### Deploy AWS Batch

```bash
# Navigate to terraform directory
cd terraform

# Apply production configuration
terraform apply -var-file=terraform.prod.tfvars

# Verify resources created
aws batch describe-compute-environments
aws batch describe-job-queues
aws batch describe-job-definitions
```

### Monitor Running Jobs

```bash
# List recent jobs
aws batch list-jobs --job-queue vidx-processing-queue

# Get detailed job info
aws batch describe-jobs --jobs <job-id>

# Follow logs
aws logs tail /aws/batch/vidx-production --follow
```

### Scale Compute Resources

```bash
# Update max vCPUs
aws batch update-compute-environment \
  --compute-environment vidx-processing-env \
  --compute-resources maxvCpus=512

# Adjust Spot bid percentage
terraform apply -var="batch_spot_bid_percentage=50"
```

## For Testing

### Local Development Environment

```bash
# Start LocalStack with all AWS services
docker-compose -f docker-compose.localstack.yml up -d

# Wait for initialization (automatic)
# LocalStack init script creates Batch resources

# Set environment variables
export AWS_ENDPOINT_URL=http://localhost:4566
export TASK_EXECUTION_STRATEGY=local  # Use local execution
```

### Testing Video Processing

```python
import asyncio
from vidx.services.task_execution import (
    ExecutionStrategyFactory,
    TaskExecutionManager,
)

# Create local executor for testing
strategy = ExecutionStrategyFactory.create_strategy(
    environment="localstack",
    ffmpeg_binary="/usr/bin/ffmpeg"
)
manager = TaskExecutionManager(strategy)

# Submit test task
task_id = asyncio.run(manager.submit_merge_task(
    videos={
        "test1.mp4": 10.0,
        "test2.mp4": 15.0,
    },
    audio=None,
    video_mime="video/mp4",
    video_resolution=(1280, 720),
    audio_duration=None,
    transition="crossfade",
    user_tier="basic"
))

# Check status
status = asyncio.run(manager.get_task_status(task_id))
print(status)  # {status: 'completed', output_path: '/tmp/...', ...}
```

## Environment Variables

### Core Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `TASK_EXECUTION_STRATEGY` | `auto` | Executor selection: `auto`, `aws-batch`, `local` |
| `BATCH_ENABLED` | `false` | Enable AWS Batch integration |
| `ENVIRONMENT` | `dev` | Environment: `dev`, `localstack`, `staging`, `prod` |

### AWS Credentials

| Variable | Default | Purpose |
|----------|---------|---------|
| `AWS_ACCESS_KEY_ID` | (env) | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | (env) | AWS secret key |
| `AWS_DEFAULT_REGION` | `us-east-1` | AWS region |
| `AWS_ENDPOINT_URL` | (none) | LocalStack endpoint: `http://localhost:4566` |

### Batch Configuration

| Variable | Default | Purpose |
|----------|---------|---------|
| `BATCH_JOB_QUEUE` | `vidx-processing-queue` | Job queue name |
| `BATCH_JOB_DEFINITION` | `vidx-video-merge` | Job definition name |
| `AWS_S3_BUCKET` | (required) | S3 bucket for video storage |

### FFmpeg

| Variable | Default | Purpose |
|----------|---------|---------|
| `FFMPEG_BINARY` | `ffmpeg` | Path to ffmpeg binary |
| `FFPROBE_BINARY` | `ffprobe` | Path to ffprobe binary |

## Common Errors & Solutions

### Error: "Cannot submit to AWS Batch: credentials not configured"

**Solution:**
```bash
# Set AWS credentials
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
export AWS_DEFAULT_REGION=us-east-1
```

### Error: "Task execution strategy not available"

**Solution:**
```python
# Check available strategies
from vidx.services.task_execution import ExecutionStrategyFactory
strategies = ExecutionStrategyFactory.get_available_strategies()
for s in strategies:
    print(f"{s.get_name()}: available={s.is_available()}")
```

### Error: "Container image not found in ECR"

**Solution:**
```bash
# Build and push Docker image
cd backend
docker build -t vidx-backend:latest .
docker tag vidx-backend:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/vidx-backend:latest
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/vidx-backend:latest

# Update Terraform
# Set batch_job_image variable in tfvars
```

## Code Examples

### Adding a New Feature (e.g., Watermarking)

1. **Create a new task:**

```python
@celery.task(name="vidx.tasks.add_watermark")
def add_watermark(
    video_path: str,
    watermark_path: str,
    position: str = "bottom-right",
    opacity: float = 0.8,
    user_tier: str = "basic",
) -> str:
    manager = get_execution_manager()
    
    task_id = asyncio.run(manager.submit_merge_task(
        videos={video_path: get_duration(video_path)},
        audio=None,
        video_mime="video/mp4",
        video_resolution=(1920, 1080),
        audio_duration=None,
        transition="none",  # Not applicable for watermark
        user_tier=user_tier,
    ))
    return task_id
```

2. **No infrastructure changes needed!**
   - The strategy pattern handles routing
   - Works with both local and AWS Batch execution
   - Automatically scales with workload

### Using Ray for Parallel Processing (Future)

```python
from vidx.services.task_execution.ray_executor import RayExecutor

# When Ray executor is available
strategy = ExecutionStrategyFactory.create_strategy(
    environment="prod-distributed",
    # ... other params ...
)

# Manager automatically uses Ray for parallelization
manager = TaskExecutionManager(strategy)
```

## Performance Benchmarks

### Local Execution
- **100MB video**: ~10-30 seconds
- **Throughput**: Single file at a time
- **Cost**: Included in worker pod

### AWS Batch (EC2)
- **100MB video**: ~5-10 seconds (faster hardware)
- **Throughput**: 10+ concurrent jobs
- **Cost**: ~$0.05-0.10 per job

### AWS Batch (VT1 - Optimized)
- **100MB video**: ~2-5 seconds
- **Throughput**: 64+ concurrent 1080p streams
- **Cost**: ~$0.03-0.05 per job (75% cheaper)

## References

- [Architecture Diagram](./ARCHITECTURE_DIAGRAMS.md)
- [AWS Batch Setup Guide](./BATCH_SETUP.md)
- [Infrastructure Index](./IMPLEMENTATION_INDEX.md)
