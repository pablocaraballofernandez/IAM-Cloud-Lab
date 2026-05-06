terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
            version = "~> 3.0"        
    }
  }
}

resource "aws_instance" "keycloak" {
    ami = data.aws_ami.ubuntu.id
    instance_type = var.instance_keycloak
    subnet_id = aws_subnet.public.id
    vpc_security_group_ids = [aws_security_group.ec2_sg.id]
    key_name = aws_key_pair.deployer.key_name

    user_data = base64gzip(templatefile("${path.module}/scripts/setup_keycloak.sh", {
        db_host     = split(":", aws_db_instance.keycloak_db.endpoint)[0]
        db_password = var.db_password
        db_username             = var.db_username
        keycloak_admin          = var.keycloak_admin
        keycloak_admin_password = var.keycloak_admin_password
    }))
}

resource "aws_key_pair" "deployer" {
  key_name   = "honeycloud-admin"
  public_key = var.ssh_key
}

resource "aws_db_instance" "keycloak_db" {
    allocated_storage = 20
    name = "keycloak"
    engine = "postgres"
    engine_version = "15"
    instance_class = "db.t3.micro"
    username = var.db_username
    password = var.db_password
    skip_final_snapshot = true
    identifier = "iam-lab-db"
    publicly_accessible = false
    vpc_security_group_ids = [aws_security_group.rds_sg.id]
    db_subnet_group_name = aws_db_subnet_group.keycloak.id
}

resource "aws_vpc" "public" {
    cidr_block = "10.0.0.0/16"
    enable_dns_support = true
    enable_dns_hostnames = true
}

resource "aws_subnet" "public" {
    vpc_id = aws_vpc.public.id
    cidr_block = "10.0.1.0/24"
    map_public_ip_on_launch = true
    availability_zone = "${var.region}a"
}

resource "aws_subnet" "private_a" {
    vpc_id = aws_vpc.public.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "${var.region}a"
}

resource "aws_subnet" "private_b" {
    vpc_id = aws_vpc.public.id
    cidr_block = "10.0.3.0/24"
    availability_zone = "${var.region}b"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
