variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "cluster_name" {
  description = "Security cluster name"
  type        = string
  default     = "aws-security-cluster"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Kibana"
  type        = list(string)
  default     = ["10.0.0.0/8"] # Internal only
}

variable "security_team_email" {
  description = "Email address for security team notifications"
  type        = string
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 90
}

variable "forensics_retention_days" {
  description = "Forensic data retention in days"
  type        = number
  default     = 2555 # 7 years
}
