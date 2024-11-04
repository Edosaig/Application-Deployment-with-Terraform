terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Create a ec2
#resource "aws_instance" "my-server" {
#   ami = "ami-0866a3c8686eaeeba"
#   instance_type = "t2.micro"

#   tags = {
#      Name = "ubuntu"
#   }
#}

#Terraform Project

#1. create a vpc
resource "aws_vpc" "new-vpc" {
  cidr_block = "10.0.0.0/16" 
  tags = {
    Name = "tf-vpc"
  } 
}

#2. create an Internet gateway
resource "aws_internet_gateway" "gw" {
   vpc_id = aws_vpc.new-vpc.id

}

#3 create a custom route table

resource "aws_egress_only_internet_gateway" "ipv6_gw" {
  vpc_id = aws_vpc.new-vpc.id
}

resource "aws_route_table" "new-route_table" {
   vpc_id = aws_vpc.new-vpc.id

   route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_internet_gateway.gw.id
   }

   route {
     ipv6_cidr_block         = "::/0"
     egress_only_gateway_id  = aws_egress_only_internet_gateway.ipv6_gw.id
  }
    tags = {
    Name = "tf-vpc"
  } 
}

#4. create a subnet
resource "aws_subnet" "new-subnet" {
  vpc_id            = aws_vpc.new-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "tf-subnet"
  }
}

#5. Associate subnet with route table
resource "aws_route_table_association" "a" {
   subnet_id = aws_subnet.new-subnet.id
   route_table_id = aws_route_table.new-route_table.id
}

#6. create a security group to allow port 22,80,443
resource "aws_security_group" "allow_web" {
  name = "allow_web_traffic"
  description= "allow web inbound traffic"
  vpc_id            = aws_vpc.new-vpc.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #cos we want it reachable to everyone
  }
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" #-1 represent any protocol
    cidr_blocks = ["0.0.0.0/0"] 
  }

  tags = {
    Name = "allow_web"
  }
}

#7. create a network interface with an ip in the subnet that was created above
resource "aws_network_interface" "web-server-nic" {
   subnet_id = aws_subnet.new-subnet.id
   private_ips = ["10.0.1.50"]
   security_groups = [aws_security_group.allow_web.id]
}

#8. assign an elastic ip to the network interface
resource "aws_eip" "one" {
  domain              = "vpc"
  network_interface   = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip  #prints out the public ip
}

#9. create ubuntu server and install/enable apache2
resource "aws_instance" "web-server-instance" {
   ami = "ami-0866a3c8686eaeeba"
   instance_type = "t2.micro"
   availability_zone = "us-east-1a" #same as subnet
   key_name = "ubuntukey" 

   network_interface {
     device_index = 0
     network_interface_id = aws_network_interface.web-server-nic.id
   }

  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install apache2 -y
    sudo systemctl start apache2
    echo "my very first web server" | sudo tee /var/www/html/index.html
  EOF
 
   tags = {
     Name = "web-server"
    }
}
