# Jenkins Pipeline Setup for pg-dbre-stack

## Install Required Jenkins Plugins

Navigate to:

```text
Manage Jenkins
 └── Plugins
      └── Available Plugins
```

Install:
- Pipeline (workflow-aggregator)
- Pipeline: Stage View

---

# Create Pipeline Job

Dashboard → New Item

Job Name:

```text
pg-dbre-stack
```

Job Type:

```text
Pipeline
```

---

# Jenkinsfile

```groovy
pipeline {
    agent any

    stages {

        stage("Cleanup") {
            steps {
                sh "sudo bash /var/lib/jenkins/cleanup.sh"
            }
        }

        stage("Deploy") {
            steps {
                sh "sudo bash /var/lib/jenkins/monitoring.sh"
            }
        }

        stage("Verify") {
            steps {
                sh "curl -sf http://localhost:9090/-/healthy"
                sh "curl -sf http://localhost:3000/api/health"
                sh "curl -sf http://localhost:9093/-/healthy"
                sh 'curl -s http://localhost:9187/metrics | grep -q "^pg_up 1$"'
            }
        }
    }

    post {
        success {
            echo "pg-dbre-stack deployed successfully"
        }

        failure {
            echo "Deployment failed"
        }
    }
}
```

---

# Expected Flow

```text
Cleanup
   ↓
Deploy Monitoring Stack
   ↓
Verify Components
```

## DevOps for DBAs

- Infrastructure Automation
- CI/CD Pipelines
- Repeatable Deployments
- Automated Validation

## DBRE Concepts

- Observability
- Monitoring
- Alerting
- Incident Detection
- Reliability Verification

---

# Architecture

```text
Git Repository
      ↓
Jenkins Pipeline
      ↓
Cleanup
      ↓
Deploy Monitoring Stack
      ↓
Prometheus
      ↓
Grafana
      ↓
Alertmanager
      ↓
Verify Health
      ↓
Production Ready Monitoring
```
