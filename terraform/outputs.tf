output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.main.id
}

output "security_hub_arn" {
  description = "Security Hub ARN"
  value       = aws_securityhub_account.main.id
}

output "cloudtrail_bucket" {
  description = "CloudTrail S3 bucket name"
  value       = aws_s3_bucket.cloudtrail.id
}

output "forensics_bucket" {
  description = "Forensics S3 bucket name"
  value       = aws_s3_bucket.forensics.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.cloud_security_vpc.id
}

output "sns_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "crypto_miner_instance_id" {
  description = "Crypto mining attack instance ID"
  value       = aws_instance.crypto_miner.id
}

output "data_exfil_instance_id" {
  description = "Data exfiltration attack instance ID"
  value       = aws_instance.data_exfil.id
}

output "priv_esc_instance_id" {
  description = "Privilege escalation attack instance ID"
  value       = aws_instance.priv_esc.id
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.security_monitoring.dashboard_name}"
}

output "attack_logs_url" {
  description = "Attack simulation logs URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.attack_simulations.name, "/", "$252F")}"
}

output "ml_detection_logs_url" {
  description = "ML detection results URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.ml_detection.name, "/", "$252F")}"
}
