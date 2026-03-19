# Lambda function for automated incident response
resource "aws_lambda_function" "incident_response" {
  filename      = "${path.module}/../lambda-packages/incident-response.zip"
  function_name = "cloud-security-incident-response"
  role          = aws_iam_role.lambda_incident_response.arn
  handler       = "automated-response.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      FORENSICS_BUCKET = aws_s3_bucket.forensics.id
      SNS_TOPIC_ARN    = aws_sns_topic.security_alerts.arn
      AWS_REGION       = var.aws_region
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  tags = {
    Name = "incident-response-lambda"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_incident_response" {
  name = "lambda-incident-response-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_incident_response" {
  name = "lambda-incident-response-policy"
  role = aws_iam_role.lambda_incident_response.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribeVpcs",
          "ec2:DescribeSnapshots",
          "ec2:CreateSnapshot",
          "ec2:CreateSecurityGroup",
          "ec2:CreateNetworkAclEntry",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags",
          "ec2:RevokeSecurityGroupEgress",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "s3:PutObject",
          "s3:GetObject",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 bucket for forensic data
resource "aws_s3_bucket" "forensics" {
  bucket = "cloud-security-forensics-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "forensics-data"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "forensics" {
  bucket = aws_s3_bucket.forensics.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "forensics" {
  bucket = aws_s3_bucket.forensics.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "forensics" {
  bucket = aws_s3_bucket.forensics.id

  rule {
    id     = "forensics-retention"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 2555 # 7 years for compliance
    }
  }
}

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name = "cloud-security-alerts"

  tags = {
    Name = "security-alerts"
  }
}

resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_team_email
}

# EventBridge rule to trigger Lambda from GuardDuty and Security Hub
resource "aws_cloudwatch_event_rule" "security_alerts" {
  name        = "cloud-security-alerts"
  description = "Trigger incident response from GuardDuty and Security Hub findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty", "aws.securityhub"]
    detail-type = ["GuardDuty Finding", "Security Hub Findings - Imported"]
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.security_alerts.name
  target_id = "IncidentResponseLambda"
  arn       = aws_lambda_function.incident_response.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_response.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_alerts.arn
}

# Security group for Lambda
resource "aws_security_group" "lambda" {
  name        = "lambda-incident-response-sg"
  description = "Security group for incident response Lambda"
  vpc_id      = aws_vpc.cloud_security_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lambda-incident-response-sg"
  }
}
