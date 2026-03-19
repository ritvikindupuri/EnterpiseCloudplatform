terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC for Cloud Security Platform
resource "aws_vpc" "cloud_security_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "cloud-security-vpc"
    Environment = var.environment
    Project     = "cloud-security"
  }
}

# Public subnet for NAT Gateway
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.cloud_security_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "cloud-security-public-subnet"
  }
}

# Private subnet for Lambda functions
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.cloud_security_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "cloud-security-private-subnet"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.cloud_security_vpc.id

  tags = {
    Name = "cloud-security-igw"
  }
}

# Route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.cloud_security_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "cloud-security-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
