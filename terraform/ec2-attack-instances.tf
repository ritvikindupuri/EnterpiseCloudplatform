# EC2 Instances for Real Attack Simulations
# These instances will run actual attacks that GuardDuty can detect

# Security group for attack instances
resource "aws_security_group" "attack_instances" {
  name        = "cloud-security-attack-instances"
  description = "Security group for attack simulation instances"
  vpc_id      = aws_vpc.cloud_security_vpc.id

  # Allow SSH from anywhere (for demo purposes)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (needed for attacks)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "attack-instances-sg"
  }
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM role for EC2 instances
resource "aws_iam_role" "attack_instance_role" {
  name = "cloud-security-attack-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for attack instances (intentionally permissive for attack simulation)
resource "aws_iam_role_policy" "attack_instance_policy" {
  name = "attack-instance-policy"
  role = aws_iam_role.attack_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",
          "ec2:Describe*",
          "iam:List*",
          "iam:Get*",
          "cloudtrail:Describe*",
          "cloudtrail:List*",
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "attack_instance_profile" {
  name = "cloud-security-attack-instance-profile"
  role = aws_iam_role.attack_instance_role.name
}

# Crypto Mining Attack Instance
resource "aws_instance" "crypto_miner" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.attack_instances.id]
  iam_instance_profile   = aws_iam_instance_profile.attack_instance_profile.name

  user_data = file("${path.module}/user-data/crypto-miner-attack.sh")

  tags = {
    Name        = "crypto-mining-attack-instance"
    Purpose     = "attack-simulation"
    AttackType  = "crypto-mining"
  }
}

# Data Exfiltration Attack Instance
resource "aws_instance" "data_exfil" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.attack_instances.id]
  iam_instance_profile   = aws_iam_instance_profile.attack_instance_profile.name

  user_data = file("${path.module}/user-data/data-exfil-attack.sh")

  tags = {
    Name        = "data-exfiltration-attack-instance"
    Purpose     = "attack-simulation"
    AttackType  = "data-exfiltration"
  }
}

# Privilege Escalation Attack Instance
resource "aws_instance" "priv_esc" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.attack_instances.id]
  iam_instance_profile   = aws_iam_instance_profile.attack_instance_profile.name

  user_data = file("${path.module}/user-data/privilege-escalation-attack.sh")

  tags = {
    Name        = "privilege-escalation-attack-instance"
    Purpose     = "attack-simulation"
    AttackType  = "privilege-escalation"
  }
}
