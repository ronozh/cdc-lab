# --- Network for EMR Serverless --------------------------------------------------------------------
# An EMR Serverless application without a VPC can't reach the internet, and Horizon is a public endpoint. So: private
# subnets + NAT gateway. The VPC is free; the NAT gateway (hourly) exists only while var.aws_readers_on.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "readers" {
  cidr_block           = "10.20.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "cdc-lab-readers" }
}

resource "aws_internet_gateway" "readers" {
  vpc_id = aws_vpc.readers.id
  tags   = { Name = "cdc-lab-readers" }
}

resource "aws_subnet" "public" { # holds only the NAT gateway
  vpc_id            = aws_vpc.readers.id
  cidr_block        = "10.20.0.0/28"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "cdc-lab-readers-public" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.readers.id
  cidr_block        = cidrsubnet("10.20.0.0/24", 2, count.index + 1) # 10.20.0.64/26, 10.20.0.128/26
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "cdc-lab-readers-private-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.readers.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.readers.id
  }
  tags = { Name = "cdc-lab-readers-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.readers.id
  tags   = { Name = "cdc-lab-readers-private" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_eip" "nat" {
  count  = var.aws_readers_on ? 1 : 0
  domain = "vpc"
  tags   = { Name = "cdc-lab-readers-nat" }
}

resource "aws_nat_gateway" "readers" {
  count         = var.aws_readers_on ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "cdc-lab-readers" }

  depends_on = [aws_internet_gateway.readers]
}

resource "aws_route" "private_nat" {
  count                  = var.aws_readers_on ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.readers[0].id
}

# Free gateway endpoint: S3 traffic (table files, scripts, logs) skips the NAT gateway and its per-GB charge.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.readers.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "cdc-lab-readers-s3" }
}

resource "aws_security_group" "emr" {
  name        = "cdc-lab-emr-serverless"
  description = "EMR Serverless workers: outbound only"
  vpc_id      = aws_vpc.readers.id

  egress {
    description = "HTTPS: Horizon, S3, Secrets Manager"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
