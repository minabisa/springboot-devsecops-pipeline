resource "aws_vpc" "devsecops" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "devsecops-vpc"
  }
}

resource "aws_internet_gateway" "devsecops" {
  vpc_id = aws_vpc.devsecops.id

  tags = {
    Name = "devsecops-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.devsecops.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "devsecops-public-subnet-a"

    "kubernetes.io/role/elb" = "1"
  }

}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.devsecops.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "devsecops-public-subnet-b"

    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.devsecops.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.devsecops.id
  }

  tags = {
    Name = "devsecops-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
