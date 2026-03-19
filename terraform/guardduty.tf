# Enable GuardDuty
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Name        = "cloud-security-guardduty"
    Environment = var.environment
  }
}

# GuardDuty findings to EventBridge
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "guardduty-findings-to-cloudwatch"
  description = "Forward GuardDuty findings to CloudWatch and trigger incident response"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToCloudWatch"
  arn       = aws_lambda_function.guardduty_forwarder.arn
}

# Lambda to forward GuardDuty findings to CloudWatch
resource "aws_lambda_function" "guardduty_forwarder" {
  filename      = "${path.module}/../lambda-packages/guardduty-forwarder.zip"
  function_name = "guardduty-to-cloudwatch"
  role          = aws_iam_role.guardduty_forwarder.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60

  environment {
    variables = {
      CLOUDWATCH_LOG_GROUP = "/aws/lambda/guardduty-forwarder"
    }
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }
}

resource "aws_iam_role" "guardduty_forwarder" {
  name = "guardduty-forwarder-role"

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

resource "aws_iam_role_policy_attachment" "guardduty_forwarder_vpc" {
  role       = aws_iam_role.guardduty_forwarder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_permission" "allow_guardduty" {
  statement_id  = "AllowExecutionFromGuardDuty"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guardduty_forwarder.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings.arn
}
