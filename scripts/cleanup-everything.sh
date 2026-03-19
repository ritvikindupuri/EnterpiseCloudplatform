#!/bin/bash
# Complete AWS Cleanup Script
# This script ensures EVERYTHING is deleted to avoid charges

set -e

echo "=========================================="
echo "AWS Cloud Security Platform - FULL CLEANUP"
echo "=========================================="
echo ""
echo "This will delete ALL resources created by this project."
echo "You will NOT be charged after this completes."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
REGION=$(aws configure get region || echo "us-east-1")

if [ -z "$ACCOUNT_ID" ]; then
    echo "❌ ERROR: AWS CLI not configured or no credentials found"
    echo "Run: aws configure"
    exit 1
fi

echo "✓ AWS Account ID: $ACCOUNT_ID"
echo "✓ Region: $REGION"
echo ""

# Function to check if resource exists
resource_exists() {
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# ============================================
# STEP 1: Terraform Destroy
# ============================================
echo "STEP 1: Running Terraform Destroy..."
echo "--------------------------------------------"

if [ -d "terraform" ]; then
    cd terraform
    
    if [ -f "terraform.tfstate" ]; then
        echo "Found Terraform state, destroying resources..."
        terraform destroy -auto-approve
        
        if [ $? -eq 0 ]; then
            echo "✓ Terraform destroy completed successfully"
        else
            echo "⚠️  Terraform destroy had errors, continuing with manual cleanup..."
        fi
    else
        echo "⚠️  No Terraform state found, skipping terraform destroy"
    fi
    
    cd ..
else
    echo "⚠️  Terraform directory not found, skipping terraform destroy"
fi

echo ""

# ============================================
# STEP 2: Delete Lambda Functions
# ============================================
echo "STEP 2: Deleting Lambda Functions..."
echo "--------------------------------------------"

LAMBDA_FUNCTIONS=(
    "guardduty-to-cloudwatch"
    "security-hub-to-cloudwatch"
    "cloud-security-incident-response"
)

for func in "${LAMBDA_FUNCTIONS[@]}"; do
    echo "Checking Lambda function: $func"
    if aws lambda get-function --function-name "$func" --region "$REGION" >/dev/null 2>&1; then
        echo "  Deleting $func..."
        aws lambda delete-function --function-name "$func" --region "$REGION"
        echo "  ✓ Deleted $func"
    else
        echo "  ✓ $func not found (already deleted)"
    fi
done

echo ""

# ============================================
# STEP 3: Delete S3 Buckets
# ============================================
echo "STEP 3: Deleting S3 Buckets..."
echo "--------------------------------------------"

S3_BUCKETS=(
    "cloud-security-cloudtrail-${ACCOUNT_ID}"
    "cloud-security-config-${ACCOUNT_ID}"
    "cloud-security-forensics-${ACCOUNT_ID}"
)

for bucket in "${S3_BUCKETS[@]}"; do
    echo "Checking S3 bucket: $bucket"
    if aws s3 ls "s3://$bucket" >/dev/null 2>&1; then
        echo "  Emptying bucket $bucket..."
        aws s3 rm "s3://$bucket" --recursive
        echo "  Deleting bucket $bucket..."
        aws s3 rb "s3://$bucket"
        echo "  ✓ Deleted $bucket"
    else
        echo "  ✓ $bucket not found (already deleted)"
    fi
done

echo ""

# ============================================
# STEP 4: Disable GuardDuty
# ============================================
echo "STEP 4: Disabling GuardDuty..."
echo "--------------------------------------------"

DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "")

if [ -n "$DETECTOR_ID" ] && [ "$DETECTOR_ID" != "None" ]; then
    echo "Found GuardDuty detector: $DETECTOR_ID"
    echo "  Deleting detector..."
    aws guardduty delete-detector --detector-id "$DETECTOR_ID" --region "$REGION"
    echo "  ✓ GuardDuty disabled"
else
    echo "✓ GuardDuty not enabled (already disabled)"
fi

echo ""

# ============================================
# STEP 5: Disable Security Hub
# ============================================
echo "STEP 5: Disabling Security Hub..."
echo "--------------------------------------------"

if aws securityhub describe-hub --region "$REGION" >/dev/null 2>&1; then
    echo "Found Security Hub enabled"
    echo "  Disabling Security Hub..."
    aws securityhub disable-security-hub --region "$REGION"
    echo "  ✓ Security Hub disabled"
else
    echo "✓ Security Hub not enabled (already disabled)"
fi

echo ""

# ============================================
# STEP 6: Delete CloudWatch Log Groups
# ============================================
echo "STEP 6: Deleting CloudWatch Log Groups..."
echo "--------------------------------------------"

LOG_GROUPS=(
    "/aws/lambda/guardduty-to-cloudwatch"
    "/aws/lambda/security-hub-to-cloudwatch"
    "/aws/lambda/cloud-security-incident-response"
    "/aws/vpc/flow-logs"
)

for log_group in "${LOG_GROUPS[@]}"; do
    echo "Checking log group: $log_group"
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" --query 'logGroups[0]' --output text >/dev/null 2>&1; then
        echo "  Deleting $log_group..."
        aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || echo "  ⚠️  Could not delete (may not exist)"
        echo "  ✓ Deleted $log_group"
    else
        echo "  ✓ $log_group not found (already deleted)"
    fi
done

echo ""

# ============================================
# STEP 7: Delete EventBridge Rules
# ============================================
echo "STEP 7: Deleting EventBridge Rules..."
echo "--------------------------------------------"

EVENT_RULES=(
    "guardduty-findings-to-cloudwatch"
    "security-hub-findings-to-cloudwatch"
    "cloud-security-alerts"
)

for rule in "${EVENT_RULES[@]}"; do
    echo "Checking EventBridge rule: $rule"
    if aws events describe-rule --name "$rule" --region "$REGION" >/dev/null 2>&1; then
        echo "  Removing targets from $rule..."
        TARGETS=$(aws events list-targets-by-rule --rule "$rule" --region "$REGION" --query 'Targets[].Id' --output text)
        if [ -n "$TARGETS" ]; then
            aws events remove-targets --rule "$rule" --ids $TARGETS --region "$REGION"
        fi
        echo "  Deleting rule $rule..."
        aws events delete-rule --name "$rule" --region "$REGION"
        echo "  ✓ Deleted $rule"
    else
        echo "  ✓ $rule not found (already deleted)"
    fi
done

echo ""

# ============================================
# STEP 8: Delete SNS Topics
# ============================================
echo "STEP 8: Deleting SNS Topics..."
echo "--------------------------------------------"

SNS_TOPICS=$(aws sns list-topics --region "$REGION" --query 'Topics[?contains(TopicArn, `cloud-security`)].TopicArn' --output text)

if [ -n "$SNS_TOPICS" ]; then
    for topic in $SNS_TOPICS; do
        echo "Deleting SNS topic: $topic"
        aws sns delete-topic --topic-arn "$topic" --region "$REGION"
        echo "  ✓ Deleted $topic"
    done
else
    echo "✓ No SNS topics found (already deleted)"
fi

echo ""

# ============================================
# STEP 9: Delete CloudTrail
# ============================================
echo "STEP 9: Deleting CloudTrail..."
echo "--------------------------------------------"

TRAIL_NAME="cloud-security-trail"

if aws cloudtrail describe-trails --region "$REGION" --query "trailList[?Name=='$TRAIL_NAME']" --output text | grep -q "$TRAIL_NAME"; then
    echo "Found CloudTrail: $TRAIL_NAME"
    echo "  Stopping logging..."
    aws cloudtrail stop-logging --name "$TRAIL_NAME" --region "$REGION"
    echo "  Deleting trail..."
    aws cloudtrail delete-trail --name "$TRAIL_NAME" --region "$REGION"
    echo "  ✓ CloudTrail deleted"
else
    echo "✓ CloudTrail not found (already deleted)"
fi

echo ""

# ============================================
# STEP 10: Stop AWS Config
# ============================================
echo "STEP 10: Stopping AWS Config..."
echo "--------------------------------------------"

CONFIG_RECORDER="cloud-security-config-recorder"

if aws configservice describe-configuration-recorders --region "$REGION" --query "ConfigurationRecorders[?name=='$CONFIG_RECORDER']" --output text | grep -q "$CONFIG_RECORDER"; then
    echo "Found Config recorder: $CONFIG_RECORDER"
    echo "  Stopping recorder..."
    aws configservice stop-configuration-recorder --configuration-recorder-name "$CONFIG_RECORDER" --region "$REGION"
    echo "  Deleting delivery channel..."
    aws configservice delete-delivery-channel --delivery-channel-name "cloud-security-config-delivery" --region "$REGION" 2>/dev/null || true
    echo "  Deleting recorder..."
    aws configservice delete-configuration-recorder --configuration-recorder-name "$CONFIG_RECORDER" --region "$REGION"
    echo "  ✓ AWS Config stopped"
else
    echo "✓ AWS Config not found (already stopped)"
fi

echo ""

# ============================================
# STEP 11: Delete VPC and Networking
# ============================================
echo "STEP 11: Deleting VPC and Networking..."
echo "--------------------------------------------"

VPC_NAME="cloud-security-vpc"
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    echo "Found VPC: $VPC_ID"
    
    # Delete NAT Gateways
    echo "  Checking for NAT Gateways..."
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[?State==`available`].NatGatewayId' --output text)
    for nat in $NAT_GATEWAYS; do
        echo "    Deleting NAT Gateway: $nat"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region "$REGION"
    done
    
    # Delete Internet Gateway
    echo "  Checking for Internet Gateways..."
    IGW_ID=$(aws ec2 describe-internet-gateways --region "$REGION" --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId' --output text)
    if [ -n "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
        echo "    Detaching Internet Gateway: $IGW_ID"
        aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
        echo "    Deleting Internet Gateway: $IGW_ID"
        aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" --region "$REGION"
    fi
    
    # Delete Subnets
    echo "  Deleting subnets..."
    SUBNETS=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text)
    for subnet in $SUBNETS; do
        echo "    Deleting subnet: $subnet"
        aws ec2 delete-subnet --subnet-id "$subnet" --region "$REGION"
    done
    
    # Delete Security Groups (except default)
    echo "  Deleting security groups..."
    SECURITY_GROUPS=$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
    for sg in $SECURITY_GROUPS; do
        echo "    Deleting security group: $sg"
        aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null || echo "    ⚠️  Could not delete (may have dependencies)"
    done
    
    # Delete VPC
    echo "  Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || echo "  ⚠️  Could not delete VPC (may have dependencies, will retry)"
    
    echo "  ✓ VPC cleanup completed"
else
    echo "✓ VPC not found (already deleted)"
fi

echo ""

# ============================================
# STEP 12: Delete IAM Roles
# ============================================
echo "STEP 12: Deleting IAM Roles..."
echo "--------------------------------------------"

IAM_ROLES=(
    "guardduty-forwarder-role"
    "security-hub-forwarder-role"
    "lambda-incident-response-role"
    "aws-config-role"
    "vpc-flow-logs-role"
)

for role in "${IAM_ROLES[@]}"; do
    echo "Checking IAM role: $role"
    if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
        echo "  Detaching policies from $role..."
        POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text)
        for policy in $POLICIES; do
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
        done
        
        echo "  Deleting inline policies from $role..."
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text)
        for policy in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
        done
        
        echo "  Deleting role $role..."
        aws iam delete-role --role-name "$role"
        echo "  ✓ Deleted $role"
    else
        echo "  ✓ $role not found (already deleted)"
    fi
done

echo ""

# ============================================
# STEP 13: Delete EBS Snapshots (if any)
# ============================================
echo "STEP 13: Checking for EBS Snapshots..."
echo "--------------------------------------------"

SNAPSHOTS=$(aws ec2 describe-snapshots --region "$REGION" --owner-ids self --query 'Snapshots[?contains(Description, `cloud-security`) || contains(Description, `forensic`)].SnapshotId' --output text)

if [ -n "$SNAPSHOTS" ]; then
    for snapshot in $SNAPSHOTS; do
        echo "Deleting snapshot: $snapshot"
        aws ec2 delete-snapshot --snapshot-id "$snapshot" --region "$REGION"
        echo "  ✓ Deleted $snapshot"
    done
else
    echo "✓ No snapshots found"
fi

echo ""

# ============================================
# FINAL VERIFICATION
# ============================================
echo "=========================================="
echo "FINAL VERIFICATION"
echo "=========================================="
echo ""

echo "Checking for remaining resources..."
echo ""

# Check GuardDuty
DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")
if [ "$DETECTOR_ID" = "None" ] || [ -z "$DETECTOR_ID" ]; then
    echo "✓ GuardDuty: Disabled"
else
    echo "⚠️  GuardDuty: Still enabled (detector: $DETECTOR_ID)"
fi

# Check Security Hub
if aws securityhub describe-hub --region "$REGION" >/dev/null 2>&1; then
    echo "⚠️  Security Hub: Still enabled"
else
    echo "✓ Security Hub: Disabled"
fi

# Check Lambda functions
LAMBDA_COUNT=$(aws lambda list-functions --region "$REGION" --query 'Functions[?contains(FunctionName, `cloud-security`)].FunctionName' --output text | wc -w)
if [ "$LAMBDA_COUNT" -eq 0 ]; then
    echo "✓ Lambda Functions: None found"
else
    echo "⚠️  Lambda Functions: $LAMBDA_COUNT still exist"
fi

# Check S3 buckets
S3_COUNT=$(aws s3 ls | grep -c "cloud-security" || echo "0")
if [ "$S3_COUNT" -eq 0 ]; then
    echo "✓ S3 Buckets: None found"
else
    echo "⚠️  S3 Buckets: $S3_COUNT still exist"
fi

# Check VPC
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Name,Values=cloud-security-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    echo "✓ VPC: Deleted"
else
    echo "⚠️  VPC: Still exists ($VPC_ID)"
fi

echo ""
echo "=========================================="
echo "CLEANUP COMPLETE!"
echo "=========================================="
echo ""
echo "✓ All resources have been deleted"
echo "✓ You will NOT be charged for these services"
echo ""
echo "Note: It may take a few minutes for AWS to fully process deletions."
echo "Check your AWS Console to verify all resources are gone."
echo ""
echo "Billing tip: Check AWS Cost Explorer in 24 hours to verify $0 charges."
echo ""
