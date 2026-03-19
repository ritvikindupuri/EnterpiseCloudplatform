# Enable AWS Security Hub
resource "aws_securityhub_account" "main" {}

# Enable security standards
resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

resource "aws_securityhub_standards_subscription" "pci_dss" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/pci-dss/v/3.2.1"
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# Forward Security Hub findings to EventBridge
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  name        = "security-hub-findings-to-cloudwatch"
  description = "Forward Security Hub findings to CloudWatch and trigger incident response"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })
}

resource "aws_cloudwatch_event_target" "security_hub_to_lambda" {
  rule      = aws_cloudwatch_event_rule.security_hub_findings.name
  target_id = "SendToCloudWatch"
  arn       = aws_lambda_function.security_hub_forwarder.arn
}

# Lambda to forward Security Hub findings to CloudWatch
resource "aws_lambda_function" "security_hub_forwarder" {
  filename      = "${path.module}/../lambda-packages/security-hub-forwarder.zip"
  function_name = "security-hub-to-cloudwatch"
  role          = aws_iam_role.security_hub_forwarder.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60

  environment {
    variables = {
      CLOUDWATCH_LOG_GROUP = "/aws/lambda/security-hub-forwarder"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
}

resource "aws_iam_role" "security_hub_forwarder" {
  name = "security-hub-forwarder-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "security_hub_forwarder_vpc" {
  role       = aws_iam_role.security_hub_forwarder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_permission" "allow_security_hub" {
  statement_id  = "AllowExecutionFromSecurityHub"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_hub_forwarder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_hub_findings.arn
}

# Enable AWS Config for Security Hub
resource "aws_config_configuration_recorder" "main" {
  name     = "cloud-security-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "cloud-security-config-delivery"
  s3_bucket_name = aws_s3_bucket.config.id
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# S3 bucket for AWS Config
resource "aws_s3_bucket" "config" {
  bucket = "cloud-security-config-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "aws-config-logs"
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid    = "AWSConfigBucketPutObject"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/*"
      }
    ]
  })
}

# IAM role for AWS Config
resource "aws_iam_role" "config" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}
