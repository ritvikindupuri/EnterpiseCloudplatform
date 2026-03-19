# Lambda function for ML-based threat detection
resource "aws_lambda_function" "ml_detector" {
  filename      = "${path.module}/../lambda-packages/ml-detector.zip"
  function_name = "cloud-security-ml-detector"
  role          = aws_iam_role.ml_detector_role.arn
  handler       = "ml_detector.lambda_handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  environment {
    variables = {
      LOG_GROUP_NAME = aws_cloudwatch_log_group.ml_detection.name
    }
  }

  tags = {
    Name = "ml-threat-detector"
  }
}

# IAM role for ML detector Lambda
resource "aws_iam_role" "ml_detector_role" {
  name = "cloud-security-ml-detector-role"

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

resource "aws_iam_role_policy" "ml_detector_policy" {
  name = "ml-detector-policy"
  role = aws_iam_role.ml_detector_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule to trigger ML detection every 5 minutes
resource "aws_cloudwatch_event_rule" "ml_detection_schedule" {
  name                = "ml-detection-schedule"
  description         = "Trigger ML detection every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "ml_detector" {
  rule      = aws_cloudwatch_event_rule.ml_detection_schedule.name
  target_id = "MLDetectorLambda"
  arn       = aws_lambda_function.ml_detector.arn
}

resource "aws_lambda_permission" "allow_eventbridge_ml" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ml_detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ml_detection_schedule.arn
}
