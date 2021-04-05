provider "aws" {
    region      = var.region
    access_key  = var.access_key
    secret_key  = var.secret_key
}

variable "region" {
  default = "us-east-2"
}

variable "access_key" {
  default = ""
}

variable "secret_key" {
  default = ""
}

variable "ec2_ami" {
    default = "ami-05d72852800cbf29e"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "subnet_cidrs_public" {
  description = "Subnet CIDRs for public subnets (length must match configured availability_zones)"
  # this could be further simplified / computed using cidrsubnet() etc.
  # https://www.terraform.io/docs/configuration/interpolation.html#cidrsubnet-iprange-newbits-netnum-
  default = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  type = list
}

variable "availability_zones" {
  description = "AZs in this region to use"
  default = ["us-east-2a", "us-east-2b", "us-east-2c"]
  type = list
}


# 1. Create VPC

resource "aws_vpc" "prod-vpc" {
    cidr_block = var.vpc_cidr
    tags = {
        Name = "production"
    }
}

# 2. Create Internet Gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
}

# 3. Create Custom Route Table

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    # Send all traffic to internet gateway
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

# 4. Create subnets
# ref: https://stackoverflow.com/a/51741614

resource "aws_subnet" "public" {
  count = length(var.subnet_cidrs_public)

  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = var.subnet_cidrs_public[count.index]
  availability_zone = var.availability_zones[count.index]
}

# 5. Associate subnets with Route table

resource "aws_route_table_association" "public" {
  count = length(var.subnet_cidrs_public)

  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.prod-route-table.id
}

# 6. Create a security group

resource "aws_security_group" "allow_web" {
    name        = "allow_web_traffic"
    description = "Allow TLS inbound traffic"
    vpc_id      = aws_vpc.prod-vpc.id

    ingress {
        description = "HTTPS"
        from_port = 443
        to_port   = 443
        protocol  = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        description = "SSH"
        from_port = 22
        to_port   = 22
        protocol  = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port   = 0
        protocol  = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags = {
        Name = "allow_web"
    }
}

# 7. Create a network interface with an IP in the subnet created in step 4
resource "aws_network_interface" "server-nic" {
  subnet_id       = element(aws_subnet.public.*.id, 0)
  private_ips     = ["10.0.10.50"]
  security_groups = [aws_security_group.allow_web.id]
}

# 8. Assign an elastic IP to the NIC created in step 7

resource "aws_eip" "lb" {
  instance = aws_instance.server-instance.id
  vpc      = true
  network_interface = aws_network_interface.server-nic.id
  associate_with_private_ip = "10.0.10.50"
  depends_on = [aws_internet_gateway.gw]
}

# 9. Create server
resource "aws_instance" "server-instance" {
    ami = var.ec2_ami
    instance_type = "t2.micro"
    availability_zone = var.availability_zones[0]
    key_name = var.key_name

    network_interface {
        device_index = 0
        network_interface_id = aws_network_interface.server-nic.id
    }
}

resource "aws_iam_service_linked_role" "es" {
  aws_service_name = "es.amazonaws.com"
}

module "elasticsearch" {
  source  = "cloudposse/elasticsearch/aws"
  version = "0.30.0"
  namespace               = "eg"
  stage                   = "prod"
  name                    = "youtube"
  security_groups         = [aws_security_group.allow_web.id]
  vpc_id                  = aws_vpc.prod-vpc.id
  subnet_ids              = slice(aws_subnet.public.*.id, 0, 2)
  zone_awareness_enabled  = "true"
  elasticsearch_version   = "7.9"
  instance_type           = "t2.small.elasticsearch"
  create_iam_service_linked_role = false
  instance_count          = 4
  ebs_volume_size         = 10
  iam_role_arns           = ["*"]
  iam_actions             = ["es:*"]
  encrypt_at_rest_enabled = false
  kibana_subdomain_name   = "kibana-es"
  depends_on              = [aws_iam_service_linked_role.es]
}


