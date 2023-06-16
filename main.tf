# 기본 연결
provider "aws" {
  region     = "ap-northeast-2"
  access_key = ACCESS_KEY
  secret_key = SECRET_KEY
}

# EC2 deploy
# resource "aws_instance" "Utuntu_test" {
#   ami = "ami-0c9c942bd7bf113a2"
#   instance_type = "t2.micro"
#   tags = {
#     Name = "linux"
#   }
# }

#VPC deploy
# resource "aws_vpc" "my-vpc" {
#     cidr_block = "10.0.0.0/16"
#     tags = {
#         Name = "development"
#     }
# }

#Subnet deploy
# resource "aws_subnet" "sub-1" {
#     # 상단에 생성한 VPC를 레퍼런스로 vpc_id를 지정할 수 있음
#     # Codebase Terraform(설정)의 장점
#     vpc_id = aws_vpc.my-vpc.id
#     cidr_block = "10.0.1.0/24"
#     tags = {
#         Name = "development"
#     }
# }

# 실습
# 1. VPC 생성
resource "aws_vpc" "my-vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "development"
  }
}

# 2. 인터넷에서 접속가능한 Gateway 생성
resource "aws_internet_gateway" "gw-test" {
  vpc_id = aws_vpc.my-vpc.id

  tags = {
    Name = "development"
  }
}

# 3. Route Table 생성
resource "aws_route_table" "terra-route" {
  vpc_id = aws_vpc.my-vpc.id

  route {
    # Default Route 설정
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw-test.id
  }

  route {
    # IPv6는 기본으로 Defult Route 설정이 되어 있음
    ipv6_cidr_block = "::/0"
    # IPv4와 동일하게 수정
    gateway_id = aws_internet_gateway.gw-test.id
  }

  tags = {
    Name = "development"
  }
}

# 4. Subnet 생성
resource "aws_subnet" "sub-1" {
  vpc_id     = aws_vpc.my-vpc.id
  cidr_block = "10.0.1.0/24"
  # 사용자가 지정한 특정한 지역(region)에 subnet을 할당 할 수 있음  
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "development"
  }
}

# 5. Route Table에 Subnet 할당
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.sub-1.id
  route_table_id = aws_route_table.terra-route.id
}

# 6. 22, 80, 443 포트 보안그룹에 생성
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.my-vpc.id

  # Inbound 규칙
  ingress {
    description = "HTTPS"
    # 포트 할당 range 설정 가능 443~500
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    # cidr_blocks      = [aws_vpc.main.cidr_block]
    # 실습을 위해 인터넷 모든 트래픽 접속가능으로 허용 (block 해제)
    cidr_blocks = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
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

  # Outbound 규칙
  egress {
    from_port = 0
    to_port   = 0
    # "-1"은 모든 프로토콜 허용을 의미
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    # ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7. Subnet에 해당되는 IP 대역 주소로 네트워크 인터페이스 생성
resource "aws_network_interface" "web-server-nic" {
  subnet_id = aws_subnet.sub-1.id
  # Subnet 대역에서 IP 주소하나 선정
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

  # attachment {
  #   instance     = aws_instance.test.id
  #   device_index = 1
  # }
}

# 8. 생성된 네트워크 인터페이스에 엘라스틱 IP 할당
# 설정순서와 상관없는 Terraform의 특징의 예외
# 엘라스틱 IP 설정을 위해선 반드시 인터넷 게이트웨이 1, 2번이 이미 디플로이 되었거나
# 해당 코드 위에 위치해야 한다
resource "aws_eip" "one" {
  # domain            = "vpc"
  # 기본 레퍼런스에서 추가
  vpc               = true
  network_interface = aws_network_interface.web-server-nic.id
  # 네트워크 인터페이스에 할당된 IP 기재
  # 여러 IP를 한번에 할당 가능하지만 실습에서는 1개만 할당
  associate_with_private_ip = "10.0.1.50"
  # 기본 레퍼런스에서 추가
  # depends_on은 리스트 [ ] 로 지정해야함
  depends_on = [aws_internet_gateway.gw-test]
}

# 9. 우분투 서버 생성 후 apache2 설치 및 활성화
resource "aws_instance" "web_server_instance" {
  ami           = "ami-0c9c942bd7bf113a2"
  instance_type = "t2.micro"
  # Subnet과 동일한 availability_zone으로 하드코딩
  # 미기재 시 때때로 AWS는 availability_zone을 가용가능한 랜덤 지역으로 배정함
  availability_zone = "ap-northeast-2a"
  key_name          = "main-key"

  # 여러 NIC 할당가능
  # Ethernet 0, 1, 2...
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  # Apache 설치 및 활성화
  # 어떤 커맨드라도 가능, EOF 안에 기재
  user_data = <<-EOF
      #!/bin/bash
      sudo apt update -y
      sudo apt install apache2 -y
      sudo systemctl start apache2
      sudo bash -c 'echo my fist web server > /var/www/html/index.html'
    EOF

  tags = {
    Name = "web-server"
  }
}

output "show_ec2_public_ip" {
  value = aws_eip.one.public_ip
}
