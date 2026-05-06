resource "aws_internet_gateway" "gateway" {
    vpc_id = aws_vpc.public.id 
}

resource "aws_route_table" "router" {
    vpc_id = aws_vpc.public.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.gateway.id
    } 
}

resource "aws_route_table_association" "public" {
    route_table_id = aws_route_table.router.id
    subnet_id = aws_subnet.public.id
}

resource "aws_db_subnet_group" "keycloak" {
    name = "iam-lab-db-subnet"
    subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  
}