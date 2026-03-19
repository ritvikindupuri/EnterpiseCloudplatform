#!/bin/bash
# Verify all AWS resources are deleted

REGION=$(aws configure get region || echo "us-east-1")
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

echo "=========================================="
echo "AWS Resource Verification"
echo "=========================================="
echo "Account: $ACCOUNT_ID"
echo "Region: $REGION"
echo ""

ISSUES=0

# Check GuardDuty
echo -n "GuardDuty: "
DETECTOR=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds[0]' --output text 2>/dev/null)
if [ -z "$DETECTOR" ] || [ "$DETECTOR" = "None" ]; then
    echo "✓ Disabled"
else
    echo "⚠️  STILL ENABLED (Detector: $DETECTOR)"
    ISSUES=$((ISSUES + 1))
fi

# Check Security Hub
echo -n "Security Hub: "
if aws securityhub describe-hub --region "$REGION" >/dev/null 2>&1; then
    echo "⚠️  STILL ENABLED"
    ISSUES=$((ISSUES + 1))
else
    echo "✓ Disabled"
fi

# Check Lambda
echo -n "Lambda Functions: "
LAMBDA_COUNT=$(aws lambda list-functions --region "$REGION" --query 'Functions[?contains(FunctionName, `cloud-security`)].FunctionName' --output text | wc -w)
if [ "$LAMBDA_COUNT" -eq 0 ]; then
    echo "✓ None found"
else
    echo "⚠️  $LAMBDA_COUNT STILL EXIST"
    ISSUES=$((ISSUES + 1))
fi

# Check S3
echo -n "S3 Buckets: "
S3_COUNT=$(aws s3 ls | grep -c "cloud-security" || echo "0")
if [ "$S3_COUNT" -eq 0 ]; then
    echo "✓ None found"
else
    echo "⚠️  $S3_COUNT STILL EXIST"
    ISSUES=$((ISSUES + 1))
fi

# Check VPC
echo -n "VPC: "
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Name,Values=cloud-security-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
    echo "✓ Deleted"
else
    echo "⚠️  STILL EXISTS ($VPC_ID)"
    ISSUES=$((ISSUES + 1))
fi

# Check CloudTrail
echo -n "CloudTrail: "
TRAIL=$(aws cloudtrail describe-trails --region "$REGION" --query "trailList[?Name=='cloud-security-trail']" --output text)
if [ -z "$TRAIL" ]; then
    echo "✓ Deleted"
else
    echo "⚠️  STILL EXISTS"
    ISSUES=$((ISSUES + 1))
fi

# Check AWS Config
echo -n "AWS Config: "
CONFIG=$(aws configservice describe-configuration-recorders --region "$REGION" --query "ConfigurationRecorders[?name=='cloud-security-config-recorder']" --output text)
if [ -z "$CONFIG" ]; then
    echo "✓ Stopped"
else
    echo "⚠️  STILL RUNNING"
    ISSUES=$((ISSUES + 1))
fi

echo ""
echo "=========================================="
if [ $ISSUES -eq 0 ]; then
    echo "✓ ALL CLEAN - No resources found"
    echo "✓ You will NOT be charged"
else
    echo "⚠️  WARNING: $ISSUES resource(s) still exist"
    echo "Run: ./scripts/cleanup-everything.sh"
fi
echo "=========================================="
