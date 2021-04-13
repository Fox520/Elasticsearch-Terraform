region      = "us-east-2"
access_key  = ""
secret_key  = ""
ec2_ami     = "ami-05d72852800cbf29e"
key_name = "MY_KEY_PAIR"
vpc_cidr = "10.0.0.0/16"
# Count must match availability zones
subnet_cidrs_public = ["10.0.10.0/24", "10.0.20.0/24"]
availability_zones = ["us-east-2a", "us-east-2b"]
