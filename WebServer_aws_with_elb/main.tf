#---------------------------------------------------------
# Provision Highly Available Web in any Region Default VPC
# Create:
#       - Security Group for Web server
#       - Launch Conf with Auto AMI Lookup
#       - Auto Sceling Group with 2 Availability Zones
#       - Classic Load Balancer in 2 Availability Zones
# Made by Sergey Evdokimovich
#----------------------------------------------------------

# The default provider configuration
provider "aws" {
  region = "eu-central-1"
  }
data "aws_availability_zones" "available" {
    state = "available"
  }
data "aws_ami" "latest_aws_linux" {
    owners = ["137112412989"]
    most_recent = true
    filter {
      name = "name"
      values = ["amzn2-ami-hvm-2.0.*.0-x86_64-gp2"]
    }
  }
#----------------------------------------------------------
# Create Security group
resource "aws_security_group" "my_webserver" {
  name        = "Dynamic security group"
  description = "Allow inbound traffic"

 dynamic "ingress" {
    for_each = ["80", "22", "443"]
  content {
    from_port = ingress.value
    to_port = ingress.value
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Dynamic Security Group"
    Owner = "Sergey Evdokimovich"
  }
}
#-----------------------------------------------------
# Create launch configuration
resource "aws_launch_configuration" "web" {
  name_prefix   = "WebServer_HA-"
  image_id      = data.aws_ami.latest_aws_linux.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.my_webserver.id]
  user_data = file("user_data.sh")

lifecycle {
    create_before_destroy = true
  }
}
#------------------------------------------------------
# Create AutoSceling group
resource "aws_autoscaling_group" "web" {
  name                      = "WebServer_ASG-${aws_launch_configuration.web.name}"
  max_size                  = 2
  min_size                  = 2
  launch_configuration      = aws_launch_configuration.web.name
  min_elb_capacity          = 2
  vpc_zone_identifier       = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  health_check_type         = "ELB"
  load_balancers            = [aws_elb.web.name]

  dynamic "tag" {
    for_each = {
      Name = "Server in ASG"
      Owner = "Sergey Evdokimovich"
      TAGKEY = "TAGVALUE"
    }
    content {
      key = tag.key
      value = tag.value
      propagate_at_launch = true
    }
}
lifecycle {
  create_before_destroy = true
      }
 }
#-----------------------------------------------
# Create load balancer
resource "aws_elb" "web" {
    name               = "WebServer-elb"
    availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
    security_groups = [aws_security_group.my_webserver.id]
    listener {
      instance_port = 80
      instance_protocol = "http"
      lb_port = 80
      lb_protocol = "http"
}
      health_check {
        healthy_threshold = 2
        unhealthy_threshold = 2
        timeout = 3
        target = "HTTP:80/"
        interval = 10
  }
  tags = {
     Name = "WebServer_HA_ASG"
  }
}
resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available.names[0]
}
resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.available.names[1]
}
#-------------------------------------------------------------------
output "web_LB-DNS" {
  value = aws_elb.web.dns_name
}
