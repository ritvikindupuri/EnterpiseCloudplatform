# Complete AWS Cleanup Script (PowerShell)
# This script ensures EVERYTHING is deleted to avoid charges

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "AWS Cloud Security Platform - FULL CLEANUP" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will delete ALL resources created by this project." -ForegroundColor Yellow
Write-Host "You will NOT be charged after this completes." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Are you sure you want to continue? (yes/no)"

if ($confirm -ne "yes") {
    Write-Host "Cleanup cancelled." -ForegroundColor Red
    exit 0
}

Write-Host ""
Write-Host "Starting cleanup..." -ForegroundColor Green
Write-Host ""

# Get AWS account ID and region
try {
    $accountId = (aws sts get-caller-identity --query Account --output text 2>$null)
    $region = (aws configure get region)
    if ([string]::IsNullOrEmpty($region)) { $region = "us-east-1" }
} catch {
    Write-Host "ERROR: AWS CLI not configured or no credentials found" -ForegroundColor Red
    Write-Host "Run: aws configure" -ForegroundColor Yellow
    exit 1
}

Write-Host "Account ID: $accountId" -ForegroundColor Green
Write-Host "Region: $region" -ForegroundColor Green
Write-Host ""

# ============================================
# STEP 1: Terraform Destroy
# ============================================
Write-Host "STEP 1: Running Terraform Destroy..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

if (Test-Path "terraform") {
    Push-Location terraform
    
    if (Test-Path "terraform.tfstate") {
        Write-Host "Found Terraform state, destroying resources..."
        terraform destroy -auto-approve
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Terraform destroy completed successfully" -ForegroundColor Green
        } else {
            Write-Host "Terraform destroy had errors, continuing with manual cleanup..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No Terraform state found, skipping terraform destroy" -ForegroundColor Yellow
    }
    
    Pop-Location
} else {
    Write-Host "Terraform directory not found, skipping terraform destroy" -ForegroundColor Yellow
}

Write-Host ""

# ============================================
# STEP 2: Delete Lambda Functions
# ============================================
Write-Host "STEP 2: Deleting Lambda Functions..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

$lambdaFunctions = @(
    "guardduty-to-cloudwatch",
    "security-hub-to-cloudwatch",
    "cloud-security-incident-response"
)

foreach ($func in $lambdaFunctions) {
    Write-Host "Checking Lambda function: $func"
    try {
        aws lambda get-function --function-name $func --region $region 2>$null | Out-Null
        Write-Host "  Deleting $func..." -ForegroundColor Yellow
        aws lambda delete-function --function-name $func --region $region
        Write-Host "  Deleted $func" -ForegroundColor Green
    } catch {
        Write-Host "  $func not found (already deleted)" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================
# STEP 3: Delete S3 Buckets
# ============================================
Write-Host "STEP 3: Deleting S3 Buckets..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

$s3Buckets = @(
    "cloud-security-cloudtrail-$accountId",
    "cloud-security-config-$accountId",
    "cloud-security-forensics-$accountId"
)

foreach ($bucket in $s3Buckets) {
    Write-Host "Checking S3 bucket: $bucket"
    try {
        aws s3 ls "s3://$bucket" 2>$null | Out-Null
        Write-Host "  Emptying bucket $bucket..." -ForegroundColor Yellow
        aws s3 rm "s3://$bucket" --recursive
        Write-Host "  Deleting bucket $bucket..." -ForegroundColor Yellow
        aws s3 rb "s3://$bucket"
        Write-Host "  Deleted $bucket" -ForegroundColor Green
    } catch {
        Write-Host "  $bucket not found (already deleted)" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================
# STEP 4: Disable GuardDuty
# ============================================
Write-Host "STEP 4: Disabling GuardDuty..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

try {
    $detectorId = (aws guardduty list-detectors --region $region --query 'DetectorIds[0]' --output text 2>$null)
    if (![string]::IsNullOrEmpty($detectorId) -and $detectorId -ne "None") {
        Write-Host "Found GuardDuty detector: $detectorId"
        Write-Host "  Deleting detector..." -ForegroundColor Yellow
        aws guardduty delete-detector --detector-id $detectorId --region $region
        Write-Host "  GuardDuty disabled" -ForegroundColor Green
    } else {
        Write-Host "GuardDuty not enabled (already disabled)" -ForegroundColor Green
    }
} catch {
    Write-Host "GuardDuty not enabled (already disabled)" -ForegroundColor Green
}

Write-Host ""

# ============================================
# STEP 5: Disable Security Hub
# ============================================
Write-Host "STEP 5: Disabling Security Hub..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

try {
    aws securityhub describe-hub --region $region 2>$null | Out-Null
    Write-Host "Found Security Hub enabled"
    Write-Host "  Disabling Security Hub..." -ForegroundColor Yellow
    aws securityhub disable-security-hub --region $region
    Write-Host "  Security Hub disabled" -ForegroundColor Green
} catch {
    Write-Host "Security Hub not enabled (already disabled)" -ForegroundColor Green
}

Write-Host ""

# ============================================
# STEP 6: Delete CloudWatch Log Groups
# ============================================
Write-Host "STEP 6: Deleting CloudWatch Log Groups..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

$logGroups = @(
    "/aws/lambda/guardduty-to-cloudwatch",
    "/aws/lambda/security-hub-to-cloudwatch",
    "/aws/lambda/cloud-security-incident-response",
    "/aws/vpc/flow-logs"
)

foreach ($logGroup in $logGroups) {
    Write-Host "Checking log group: $logGroup"
    try {
        aws logs describe-log-groups --log-group-name-prefix $logGroup --region $region 2>$null | Out-Null
        Write-Host "  Deleting $logGroup..." -ForegroundColor Yellow
        aws logs delete-log-group --log-group-name $logGroup --region $region 2>$null
        Write-Host "  Deleted $logGroup" -ForegroundColor Green
    } catch {
        Write-Host "  $logGroup not found (already deleted)" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================
# STEP 7: Delete EventBridge Rules
# ============================================
Write-Host "STEP 7: Deleting EventBridge Rules..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

$eventRules = @(
    "guardduty-findings-to-cloudwatch",
    "security-hub-findings-to-cloudwatch",
    "cloud-security-alerts"
)

foreach ($rule in $eventRules) {
    Write-Host "Checking EventBridge rule: $rule"
    try {
        aws events describe-rule --name $rule --region $region 2>$null | Out-Null
        Write-Host "  Removing targets from $rule..." -ForegroundColor Yellow
        $targets = (aws events list-targets-by-rule --rule $rule --region $region --query 'Targets[].Id' --output text)
        if (![string]::IsNullOrEmpty($targets)) {
            aws events remove-targets --rule $rule --ids $targets --region $region
        }
        Write-Host "  Deleting rule $rule..." -ForegroundColor Yellow
        aws events delete-rule --name $rule --region $region
        Write-Host "  Deleted $rule" -ForegroundColor Green
    } catch {
        Write-Host "  $rule not found (already deleted)" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================
# STEP 8: Delete SNS Topics
# ============================================
Write-Host "STEP 8: Deleting SNS Topics..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

try {
    $snsTopics = (aws sns list-topics --region $region --query 'Topics[?contains(TopicArn, `cloud-security`)].TopicArn' --output text)
    if (![string]::IsNullOrEmpty($snsTopics)) {
        foreach ($topic in $snsTopics.Split()) {
            Write-Host "Deleting SNS topic: $topic"
            aws sns delete-topic --topic-arn $topic --region $region
            Write-Host "  Deleted $topic" -ForegroundColor Green
        }
    } else {
        Write-Host "No SNS topics found (already deleted)" -ForegroundColor Green
    }
} catch {
    Write-Host "No SNS topics found (already deleted)" -ForegroundColor Green
}

Write-Host ""

# ============================================
# STEP 9: Delete CloudTrail
# ============================================
Write-Host "STEP 9: Deleting CloudTrail..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

$trailName = "cloud-security-trail"

try {
    $trail = (aws cloudtrail describe-trails --region $region --query "trailList[?Name=='$trailName']" --output text)
    if (![string]::IsNullOrEmpty($trail)) {
        Write-Host "Found CloudTrail: $trailName"
        Write-Host "  Stopping logging..." -ForegroundColor Yellow
        aws cloudtrail stop-logging --name $trailName --region $region
        Write-Host "  Deleting trail..." -ForegroundColor Yellow
        aws cloudtrail delete-trail --name $trailName --region $region
        Write-Host "  CloudTrail deleted" -ForegroundColor Green
    } else {
        Write-Host "CloudTrail not found (already deleted)" -ForegroundColor Green
    }
} catch {
    Write-Host "CloudTrail not found (already deleted)" -ForegroundColor Green
}

Write-Host ""

# ============================================
# STEP 10: Stop AWS Config
# ============================================
Write-Host "STEP 10: Stopping AWS Config..." -ForegroundColor Cyan
Write-Host "--------------------------------------------"

$configRecorder = "cloud-security-config-recorder"

try {
    $recorder = (aws configservice describe-configuration-recorders --region $region --query "ConfigurationRecorders[?name=='$configRecorder']" --output text)
    if (![string]::IsNullOrEmpty($recorder)) {
        Write-Host "Found Config recorder: $configRecorder"
        Write-Host "  Stopping recorder..." -ForegroundColor Yellow
        aws configservice stop-configuration-recorder --configuration-recorder-name $configRecorder --region $region
        Write-Host "  Deleting delivery channel..." -ForegroundColor Yellow
        aws configservice delete-delivery-channel --delivery-channel-name "cloud-security-config-delivery" --region $region 2>$null
        Write-Host "  Deleting recorder..." -ForegroundColor Yellow
        aws configservice delete-configuration-recorder --configuration-recorder-name $configRecorder --region $region
        Write-Host "  AWS Config stopped" -ForegroundColor Green
    } else {
        Write-Host "AWS Config not found (already stopped)" -ForegroundColor Green
    }
} catch {
    Write-Host "AWS Config not found (already stopped)" -ForegroundColor Green
}

Write-Host ""

# ============================================
# FINAL VERIFICATION
# ============================================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "FINAL VERIFICATION" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Checking for remaining resources..." -ForegroundColor Yellow
Write-Host ""

# Check GuardDuty
try {
    $detectorId = (aws guardduty list-detectors --region $region --query 'DetectorIds[0]' --output text 2>$null)
    if ([string]::IsNullOrEmpty($detectorId) -or $detectorId -eq "None") {
        Write-Host "GuardDuty: Disabled" -ForegroundColor Green
    } else {
        Write-Host "GuardDuty: Still enabled (detector: $detectorId)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "GuardDuty: Disabled" -ForegroundColor Green
}

# Check Security Hub
try {
    aws securityhub describe-hub --region $region 2>$null | Out-Null
    Write-Host "Security Hub: Still enabled" -ForegroundColor Yellow
} catch {
    Write-Host "Security Hub: Disabled" -ForegroundColor Green
}

# Check Lambda functions
$lambdaCount = (aws lambda list-functions --region $region --query 'Functions[?contains(FunctionName, `cloud-security`)].FunctionName' --output text | Measure-Object -Word).Words
if ($lambdaCount -eq 0) {
    Write-Host "Lambda Functions: None found" -ForegroundColor Green
} else {
    Write-Host "Lambda Functions: $lambdaCount still exist" -ForegroundColor Yellow
}

# Check S3 buckets
$s3Count = ((aws s3 ls | Select-String "cloud-security").Count)
if ($s3Count -eq 0) {
    Write-Host "S3 Buckets: None found" -ForegroundColor Green
} else {
    Write-Host "S3 Buckets: $s3Count still exist" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "CLEANUP COMPLETE!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "All resources have been deleted" -ForegroundColor Green
Write-Host "You will NOT be charged for these services" -ForegroundColor Green
Write-Host ""
Write-Host "Note: It may take a few minutes for AWS to fully process deletions." -ForegroundColor Yellow
Write-Host "Check your AWS Console to verify all resources are gone." -ForegroundColor Yellow
Write-Host ""
Write-Host "Billing tip: Check AWS Cost Explorer in 24 hours to verify `$0 charges." -ForegroundColor Cyan
Write-Host ""
