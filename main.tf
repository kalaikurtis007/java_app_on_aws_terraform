#create vpc for workspacepro app
module "workspacepro_vpc" {
  source                       = "terraform-aws-modules/vpc/aws"
  name                         = "workspacepro-vpc"
  cidr                         = "10.0.0.0/16"
  azs                          = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets              = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets               = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  #database_subnets             = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
  create_database_subnet_group = true

  enable_nat_gateway = true
  single_nat_gateway = true
  #one_nat_gateway_per_az = true

  enable_ipv6                                   = false
  public_subnet_assign_ipv6_address_on_creation = false

  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = {
    "Name" = "workspacepro-vpc", "created-by" = "terraform", Environment = "dev"
  }
}


#create security group for load balancer
module "sg_workspacepro_elb" {
  source                            = "terraform-aws-modules/security-group/aws"
  name                              = "app-loadbalancer"
  description                       = "Security group for app load balancer"
  vpc_id                            = module.workspacepro_vpc.vpc_id
  computed_ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      description = "default http ports"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "default https port"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  number_of_computed_ingress_with_cidr_blocks = 2
  egress_rules                                = ["all-all"]
  tags                                        = {
    "Name" = "sg_workspacepro_elb", "created-by" = "terraform", Environment = "dev"
  }
}

#create security group for tomcat app in ec2
module "sg_workspacepro_app" {
  source                                         = "terraform-aws-modules/security-group/aws"
  name                                           = "app01"
  description                                    = "Security group for app"
  vpc_id                                         = module.workspacepro_vpc.vpc_id
  computed_ingress_with_source_security_group_id = [
    {
      #rule                     = "http-8080-tcp"
      rule                     = "grafana-tcp"
      source_security_group_id = module.sg_workspacepro_elb.security_group_id
    }
  ]

  number_of_computed_ingress_with_source_security_group_id = 1

  computed_ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "default ssh ports"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      description = "default tomcat port access ipv4 from anywhere to trouble shoot"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      description = "default node port access ipv4 from anywhere to trouble shoot"
      cidr_blocks = "0.0.0.0/0"
    }

  ]
  number_of_computed_ingress_with_cidr_blocks = 3


  egress_rules = ["all-all"]
  tags         = {
    "Name" = "sg_workspacepro_app", "created-by" = "terraform", Environment = "dev"
  }
}

#create security group for mysql/memcache/rabbitmq in ec2
module "sg_workspacepro_backend" {
  source                                         = "terraform-aws-modules/security-group/aws"
  name                                           = "db01"
  description                                    = "Security group for db"
  vpc_id                                         = module.workspacepro_vpc.vpc_id
  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.sg_workspacepro_app.security_group_id
    },
    {
      rule                     = "memcached-tcp"
      source_security_group_id = module.sg_workspacepro_app.security_group_id
    },
    {
      rule                     = "rabbitmq-5672-tcp"
      source_security_group_id = module.sg_workspacepro_app.security_group_id
    },
    {
      rule                     = "all-all"
      source_security_group_id = module.sg_workspacepro_backend.security_group_id
    }
  ]

  number_of_computed_ingress_with_source_security_group_id = 4

  computed_ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "default ssh ports"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  number_of_computed_ingress_with_cidr_blocks = 1

  egress_rules = ["all-all"]
  tags         = {
    "Name" = "sg_workspacepro_backend", "created-by" = "terraform", Environment = "dev"
  }
}

#create key with rsa 4096
resource "tls_private_key" "rsa_4096" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#create key pair using generated key
resource "aws_key_pair" "key_pair" {
  key_name   = var.encrypt_key
  public_key = tls_private_key.rsa_4096.public_key_openssh
}

#write private key in local
resource "local_file" "private_key" {
  filename = var.encrypt_key
  content  = tls_private_key.rsa_4096.private_key_pem
  provisioner "local-exec" {
    command = "chmod 400 ${var.encrypt_key}"
  }
}

#create db instance
resource "aws_instance" "workspacepro_backend_db" {
  ami                    = "ami-0df2a11dd1fe1f8e3"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.key_pair.key_name
  vpc_security_group_ids = [module.sg_workspacepro_backend.security_group_id]
  tags                   = {
    "Name" = "workspacepro_backend_db", "created-by" = "terraform", Environment = "dev"
  }
  subnet_id = module.workspacepro_vpc.public_subnets[0]
  root_block_device {
    volume_size = 10
    volume_type = "gp2"
  }
  associate_public_ip_address = true
  user_data                   = "${file("user_data_files/mysql.sh")}"

}

#create memcache in ec2 instance
module "memcache_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                        = "memcache01-instance"
  ami                         = "ami-0df2a11dd1fe1f8e3"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.key_pair.key_name
  monitoring                  = true
  subnet_id                   = module.workspacepro_vpc.public_subnets[0]
  vpc_security_group_ids      = [module.sg_workspacepro_backend.security_group_id]
  associate_public_ip_address = true
  tags                        = {
    "Name" = "ec2_memcache_instance", "created-by" = "terraform", Environment = "dev"
  }
  user_data = "${file("user_data_files/memcache.sh")}"
}

#create rabbitmq in ec2 instance
module "rabbitmq_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                        = "rabitmq01-instance"
  ami                         = "ami-0df2a11dd1fe1f8e3"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.key_pair.key_name
  monitoring                  = true
  subnet_id                   = module.workspacepro_vpc.public_subnets[0]
  vpc_security_group_ids      = [module.sg_workspacepro_backend.security_group_id]
  associate_public_ip_address = true
  tags                        = {
    "Name" = "ec2_rabbitmq_instance", "created-by" = "terraform", Environment = "dev"
  }
  user_data = "${file("user_data_files/rabbitmq.sh")}"
}

#create tomcat in ec2 instance
module "tomcat_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name                        = "tomcat-instance"
  ami                         = "ami-053b0d53c279acc90"
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.key_pair.key_name
  monitoring                  = true
  subnet_id                   = module.workspacepro_vpc.public_subnets[0]
  vpc_security_group_ids      = [module.sg_workspacepro_app.security_group_id]
  associate_public_ip_address = true

  tags = {
    "Name" = "ec2_tomcat_instance", "created-by" = "terraform", Environment = "dev"
  }
  user_data = "${file("user_data_files/tomcat.sh")}"
}


#create Route53 zone
resource "aws_route53_zone" "easy_aws" {
  name = "workspacePro.in"
  vpc {
    vpc_id = module.workspacepro_vpc.vpc_id
  }
  tags = {
    "Name" = "sg_route53", "created-by" = "terraform", Environment = "dev"
  }
}

#create a route 53 for db
resource "aws_route53_record" "workspacepro_db01_record" {
  zone_id    = aws_route53_zone.easy_aws.id
  depends_on = [aws_route53_zone.easy_aws]
  name       = "db01"
  type       = "A"
  ttl        = "300"
  records    = [aws_instance.workspacepro_backend_db.private_ip]
}

#create a route53 for a memcache
resource "aws_route53_record" "workspacepro_memcache_record" {
  zone_id    = aws_route53_zone.easy_aws.id
  depends_on = [aws_route53_zone.easy_aws]
  name       = "memcache01"
  type       = "A"
  ttl        = "300"
  records    = [module.memcache_instance.private_ip]
}

#create a route53 record for rabbitmq
resource "aws_route53_record" "workspacepro_rabbitmq_record" {
  zone_id    = aws_route53_zone.easy_aws.id
  depends_on = [aws_route53_zone.easy_aws]
  name       = "rabbitmq01"
  type       = "A"
  ttl        = "300"
  records    = [module.rabbitmq_instance.private_ip]
}


module "workspacepro_alb" {
  source = "terraform-aws-modules/alb/aws"
  name   = "workspaceproalb"

  load_balancer_type = "application"

  vpc_id  = module.workspacepro_vpc.vpc_id
  subnets = [
    module.workspacepro_vpc.public_subnets[0], module.workspacepro_vpc.public_subnets[1],
    module.workspacepro_vpc.public_subnets[2]
  ]
  security_groups = [module.sg_workspacepro_elb.security_group_id]
  /*access_logs = {
    bucket = "my-alb-logs-workspacepro"
  }*/

  target_groups = [
    {
      #name_prefix      = "pref-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      targets          = {
        #app_tomcat = {
        # target_id = module.tomcat_instance.id
        # port      = 8080
        #},
        app_node = {
          target_id = module.tomcat_instance.id
          port      = 3000

        }
      }
    }
  ]
  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = var.certificate_arn
      target_group_index = 0
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    "Name" = "alb-for-tomcat-app", "created-by" = "terraform", Environment = "dev"
  }
}

output "cname" {
  value = module.workspacepro_alb
}