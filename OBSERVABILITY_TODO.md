# OBSERVABILITY & MONITORING TODO

## Current State
**Status**: ❌ Observability is MISSING

The application has basic logging but:
- No centralized log aggregation
- No metrics collection
- No distributed tracing
- No alerting
- No dashboards

---

## Phase 1: Basic Logging (1-2 days)

### 1.1 Structured Logging
**Priority**: HIGH  
**Effort**: 2 hours

**What to do:**
```python
# Replace all logging with structured logging
import structlog

logger = structlog.get_logger()

# Instead of:
logger.info(f"Task {task_id} submitted")

# Do this:
logger.info("task_submitted", task_id=task_id, user_tier=user_tier, video_count=len(videos))
```

**Files to update:**
- `backend/vidx/services/task_execution/*.py`
- `backend/vidx/services/celery/tasks.py`
- `backend/vidx/web/api/router.py`

**Benefits:**
- Searchable logs (can query by task_id, user_tier, etc.)
- JSON format for easy parsing

---

### 1.2 Centralized Log Aggregation
**Priority**: HIGH  
**Effort**: 1 day

**Options:**

#### Option A: AWS CloudWatch Logs (Easy)
```yaml
# k8s/backend-deployment.yaml
annotations:
  fluentbit.io/parser: json
```

**Setup:**
1. Install Fluent Bit DaemonSet on EKS
2. Configure CloudWatch Logs group: `/aws/eks/vidx-prod`
3. Query logs in CloudWatch Insights

**Cost**: ~$0.50-$5/month

#### Option B: ELK Stack (Self-hosted)
```bash
# Install Elasticsearch, Logstash, Kibana
helm install elasticsearch elastic/elasticsearch
helm install kibana elastic/kibana
helm install filebeat elastic/filebeat
```

**Setup:**
1. Deploy ELK stack in K8s
2. Configure Filebeat to ship logs
3. Create Kibana dashboards

**Cost**: ~$50-$200/month (EC2 instances)

#### Option C: Grafana Loki (Lightweight)
```bash
helm install loki grafana/loki-stack
```

**Recommended**: Start with CloudWatch, migrate to Loki later.

---

## Phase 2: Metrics Collection (2-3 days)

### 2.1 Application Metrics
**Priority**: HIGH  
**Effort**: 4 hours

**Add Prometheus metrics:**
```python
# backend/vidx/web/api/monitoring.py
from prometheus_client import Counter, Histogram, Gauge

# Counters
tasks_submitted = Counter("vidx_tasks_submitted_total", "Total tasks submitted", ["user_tier"])
tasks_failed = Counter("vidx_tasks_failed_total", "Total tasks failed", ["error_type"])

# Histograms
task_duration = Histogram("vidx_task_duration_seconds", "Task execution time", ["user_tier"])

# Gauges
active_tasks = Gauge("vidx_active_tasks", "Currently running tasks")

# Usage:
tasks_submitted.labels(user_tier="premium").inc()
with task_duration.labels(user_tier="premium").time():
    await execute_task()
```

**Expose metrics endpoint:**
```python
# In FastAPI app
from prometheus_fastapi_instrumentator import Instrumentator

Instrumentator().instrument(app).expose(app, endpoint="/metrics")
```

---

### 2.2 Infrastructure Metrics
**Priority**: MEDIUM  
**Effort**: 1 day

**Deploy Prometheus + Grafana:**
```bash
# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

**Collects:**
- Pod CPU/memory usage
- Node metrics
- Kubernetes events
- Container restarts

**Access Grafana:**
```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Open http://localhost:3000
```

---

### 2.3 AWS Batch Metrics
**Priority**: MEDIUM  
**Effort**: 2 hours

**CloudWatch Metrics to monitor:**
```python
# backend/vidx/services/task_execution/aws_batch.py
import boto3

cloudwatch = boto3.client('cloudwatch')

# Publish custom metrics
cloudwatch.put_metric_data(
    Namespace='VidX/Batch',
    MetricData=[
        {
            'MetricName': 'JobSubmitted',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [
                {'Name': 'UserTier', 'Value': user_tier},
                {'Name': 'Environment', 'Value': 'production'}
            ]
        }
    ]
)
```

**Metrics to track:**
- Jobs submitted
- Jobs succeeded/failed
- Job duration
- Cost per job

---

## Phase 3: Distributed Tracing (3-4 days)

### 3.1 OpenTelemetry Integration
**Priority**: MEDIUM  
**Effort**: 2 days

**Add OpenTelemetry:**
```python
# backend/vidx/__init__.py
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Setup tracing
trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter(endpoint="http://tempo:4317")
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))

tracer = trace.get_tracer(__name__)
```

**Instrument code:**
```python
# backend/vidx/services/celery/tasks.py
@celery.task
@tracer.start_as_current_span("merge_videos")
def merge_videos(...):
    with tracer.start_as_current_span("upload_to_s3"):
        s3_client.upload_file(...)
    
    with tracer.start_as_current_span("submit_batch_job"):
        batch_client.submit_job(...)
```

**Deploy Grafana Tempo:**
```bash
helm install tempo grafana/tempo
```

**Benefits:**
- See full request flow (API → Celery → Batch → S3)
- Identify bottlenecks
- Debug failures with full context

---

### 3.2 AWS X-Ray Integration
**Priority**: LOW  
**Effort**: 1 day

**Alternative to OpenTelemetry (AWS-native):**
```python
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

patch_all()  # Auto-instrument boto3, requests, etc.

@xray_recorder.capture('merge_videos')
async def merge_videos(...):
    ...
```

**Benefits:**
- Native AWS integration
- Automatic boto3 instrumentation
- Service map in AWS Console

---

## Phase 4: Alerting (1-2 days)

### 4.1 CloudWatch Alarms
**Priority**: HIGH  
**Effort**: 4 hours

**Critical alarms:**
```terraform
# terraform/monitoring.tf
resource "aws_cloudwatch_metric_alarm" "batch_job_failure_rate" {
  alarm_name          = "vidx-batch-high-failure-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FailedJobs"
  namespace           = "AWS/Batch"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Batch job failure rate too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "pod_cpu_high" {
  alarm_name          = "vidx-backend-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EKS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Backend CPU usage too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_sns_topic" "alerts" {
  name = "vidx-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "alerts@example.com"
}
```

**Alarms to create:**
- High CPU/memory usage
- High error rate
- Batch job failures
- Cost exceeds threshold
- Pod restart count

---

### 4.2 Prometheus Alertmanager
**Priority**: MEDIUM  
**Effort**: 4 hours

**Alert rules:**
```yaml
# k8s/prometheus-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: vidx-alerts
  namespace: monitoring
spec:
  groups:
    - name: vidx
      interval: 30s
      rules:
        - alert: HighTaskFailureRate
          expr: rate(vidx_tasks_failed_total[5m]) > 0.1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High task failure rate"
            description: "{{ $value }} tasks failing per second"
        
        - alert: NoTasksProcessed
          expr: rate(vidx_tasks_submitted_total[10m]) == 0
          for: 10m
          labels:
            severity: critical
          annotations:
            summary: "No tasks processed in 10 minutes"
            description: "System may be down"
```

---

## Phase 5: Dashboards (2-3 days)

### 5.1 Grafana Dashboards
**Priority**: MEDIUM  
**Effort**: 1 day

**Dashboards to create:**

1. **Application Overview**
   - Tasks submitted/completed/failed (24h)
   - Success rate %
   - Average task duration
   - Active tasks gauge

2. **Infrastructure Health**
   - Pod CPU/memory usage
   - Node resource usage
   - Pod restart count
   - Network traffic

3. **AWS Batch**
   - Job queue depth
   - Running jobs
   - Spot instance usage
   - Cost per hour

4. **User Analytics**
   - Tasks by user tier
   - Peak usage times
   - Average video size

**Export dashboards as JSON** for version control.

---

### 5.2 AWS Cost Dashboard
**Priority**: HIGH  
**Effort**: 2 hours

**Use AWS Cost Explorer:**
1. Tag all resources with `Project=vidx`
2. Create cost allocation report
3. Set up daily email reports

**Or use Terraform:**
```terraform
resource "aws_ce_cost_category" "vidx" {
  name         = "VidX"
  rule_version = "CostCategoryExpression.v1"
  
  rule {
    value = "VideoProcessing"
    rule {
      tags {
        key    = "Service"
        values = ["Batch", "S3", "EKS"]
      }
    }
  }
}
```

---

## Implementation Priority

| Phase | Priority | Effort | Impact | Order |
|-------|----------|--------|--------|-------|
| Structured Logging | HIGH | 2h | HIGH | 1 |
| CloudWatch Logs | HIGH | 1d | HIGH | 2 |
| Application Metrics | HIGH | 4h | HIGH | 3 |
| CloudWatch Alarms | HIGH | 4h | HIGH | 4 |
| Prometheus/Grafana | MEDIUM | 1d | HIGH | 5 |
| Dashboards | MEDIUM | 1d | MEDIUM | 6 |
| Distributed Tracing | MEDIUM | 2d | MEDIUM | 7 |
| AWS X-Ray | LOW | 1d | LOW | 8 |

**Total effort**: ~7-9 days for full observability stack.

---

## Quick Start (Day 1)

1. **Enable CloudWatch Logs** (2 hours):
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml
   ```

2. **Add structured logging** (2 hours):
   ```bash
   poetry add structlog
   # Update logger calls in critical files
   ```

3. **Create CloudWatch dashboard** (1 hour):
   - Go to AWS Console → CloudWatch → Dashboards
   - Add widgets for EKS metrics, Batch metrics

4. **Set up cost alarm** (30 minutes):
   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name vidx-daily-cost \
     --comparison-operator GreaterThanThreshold \
     --evaluation-periods 1 \
     --metric-name EstimatedCharges \
     --namespace AWS/Billing \
     --period 86400 \
     --statistic Maximum \
     --threshold 50
   ```

**Total: 5.5 hours for basic observability.**

---

## Tools Comparison

| Tool | Pros | Cons | Cost |
|------|------|------|------|
| CloudWatch | Easy, AWS-native | Limited queries | $0.50/GB |
| ELK Stack | Powerful queries | Heavy, expensive | $100+/mo |
| Grafana Loki | Lightweight, cheap | Less mature | $20/mo |
| Prometheus | Industry standard | Requires setup | Free |
| Datadog | All-in-one | Expensive | $15+/host/mo |

**Recommendation**: CloudWatch + Prometheus + Grafana (cost: ~$20-50/mo).

---

## Files to Create

- [ ] `backend/vidx/observability/__init__.py` - Metrics definitions
- [ ] `backend/vidx/observability/tracing.py` - OpenTelemetry setup
- [ ] `terraform/monitoring.tf` - CloudWatch alarms
- [ ] `k8s/prometheus-alerts.yaml` - Alert rules
- [ ] `k8s/grafana-dashboards/` - Dashboard JSONs
- [ ] `docs/RUNBOOK.md` - How to respond to alerts

---

## References

- **Prometheus Best Practices**: https://prometheus.io/docs/practices/naming/
- **Grafana Dashboards**: https://grafana.com/grafana/dashboards/
- **OpenTelemetry Docs**: https://opentelemetry.io/docs/
- **AWS CloudWatch Insights**: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html
