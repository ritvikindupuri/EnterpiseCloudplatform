# CloudWatch Log Group for Attack Simulations
resource "aws_cloudwatch_log_group" "attack_simulations" {
  name              = "/aws/ec2/attack-simulations"
  retention_in_days = 7

  tags = {
    Name    = "attack-simulation-logs"
    Purpose = "security-testing"
  }
}

# CloudWatch Log Group for ML Detection Results
resource "aws_cloudwatch_log_group" "ml_detection" {
  name              = "/aws/ml-detection/results"
  retention_in_days = 30

  tags = {
    Name    = "ml-detection-results"
    Purpose = "threat-detection"
  }
}

# CloudWatch Dashboard for Security Monitoring
resource "aws_cloudwatch_dashboard" "security_monitoring" {
  dashboard_name = "Cloud-Security-Attack-Monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/ec2/attack-simulations' | fields @timestamp, @message | filter @message like /attack/ | sort @timestamp desc | limit 100"
          region  = var.aws_region
          title   = "Real-Time Attack Simulations"
          stacked = false
        }
        x      = 0
        y      = 0
        width  = 12
        height = 6
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/ec2/attack-simulations' | fields @timestamp, @message | filter @message like /GuardDuty/ | sort @timestamp desc | limit 50"
          region  = var.aws_region
          title   = "Expected GuardDuty Findings"
          stacked = false
        }
        x      = 12
        y      = 0
        width  = 12
        height = 6
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/ml-detection/results' | fields @timestamp, threat_type, confidence, severity | sort @timestamp desc | limit 50"
          region  = var.aws_region
          title   = "ML Detection Results"
          stacked = false
        }
        x      = 0
        y      = 6
        width  = 12
        height = 6
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average", label = "Crypto Miner CPU" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Attack Instance CPU Usage"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
        x      = 12
        y      = 6
        width  = 12
        height = 6
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/ec2/attack-simulations' | fields @timestamp, @message | filter @message like /crypto/ or @message like /mining/ | stats count() by bin(5m)"
          region  = var.aws_region
          title   = "Crypto Mining Activity"
          stacked = false
        }
        x      = 0
        y      = 12
        width  = 8
        height = 6
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/ec2/attack-simulations' | fields @timestamp, @message | filter @message like /exfiltration/ or @message like /bucket/ | stats count() by bin(5m)"
          region  = var.aws_region
          title   = "Data Exfiltration Activity"
          stacked = false
        }
        x      = 8
        y      = 12
        width  = 8
        height = 6
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '/aws/ec2/attack-simulations' | fields @timestamp, @message | filter @message like /privilege/ or @message like /escalation/ | stats count() by bin(5m)"
          region  = var.aws_region
          title   = "Privilege Escalation Attempts"
          stacked = false
        }
        x      = 16
        y      = 12
        width  = 8
        height = 6
      }
    ]
  })
}

# Metric filter for crypto mining detection
resource "aws_cloudwatch_log_metric_filter" "crypto_mining" {
  name           = "CryptoMiningDetection"
  log_group_name = aws_cloudwatch_log_group.attack_simulations.name
  pattern        = "[time, request_id, event_type = *mining* || event_type = *crypto*]"

  metric_transformation {
    name      = "CryptoMiningEvents"
    namespace = "SecurityAttacks"
    value     = "1"
  }
}

# Metric filter for data exfiltration
resource "aws_cloudwatch_log_metric_filter" "data_exfiltration" {
  name           = "DataExfiltrationDetection"
  log_group_name = aws_cloudwatch_log_group.attack_simulations.name
  pattern        = "[time, request_id, event_type = *exfiltration* || event_type = *download*]"

  metric_transformation {
    name      = "DataExfiltrationEvents"
    namespace = "SecurityAttacks"
    value     = "1"
  }
}

# Metric filter for privilege escalation
resource "aws_cloudwatch_log_metric_filter" "privilege_escalation" {
  name           = "PrivilegeEscalationDetection"
  log_group_name = aws_cloudwatch_log_group.attack_simulations.name
  pattern        = "[time, request_id, event_type = *privilege* || event_type = *escalation*]"

  metric_transformation {
    name      = "PrivilegeEscalationEvents"
    namespace = "SecurityAttacks"
    value     = "1"
  }
}

# CloudWatch Alarm for crypto mining
resource "aws_cloudwatch_metric_alarm" "crypto_mining_alarm" {
  alarm_name          = "crypto-mining-detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CryptoMiningEvents"
  namespace           = "SecurityAttacks"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Crypto mining activity detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
}
