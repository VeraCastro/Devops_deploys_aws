# Proveedor de AWS
provider "aws" {
  region = "us-east-1" # Cambia la región si es necesario
}

# Crear un par de claves para SSH
resource "tls_private_key" "phpmyfaq" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "private_key" {
  content  = tls_private_key.phpmyfaq.private_key_pem
  filename = "${path.module}/private_key.pem"
}

resource "aws_key_pair" "deployer" {
  key_name   = "terraform-key"
  public_key = tls_private_key.phpmyfaq.public_key_openssh
}

# Crear un grupo de seguridad
resource "aws_security_group" "allow_ssh_http" {
  name_prefix = "allow_ssh_http"
  vpc_id      = "vpc-0b2dc583d71393c47"
  # Regla para permitir SSH (puerto 22)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Permitir desde cualquier IP
  }

  # Regla para permitir HTTP (puerto 80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Permitir desde cualquier IP
  }

  # Reglas de salida (egress) para permitir todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "phpmyfaq_server" {
  ami           = "ami-0150ccaf51ab55a51" # Amazon Linux 2 AMI (Free Tier)
  instance_type = "t2.micro"              # Instancia gratuita

  key_name               = aws_key_pair.deployer.key_name
  #security_groups        = [aws_security_group.allow_ssh_http.name]
  vpc_security_group_ids = [aws_security_group.allow_ssh_http.id]
  associate_public_ip_address = true

  # Script de usuario
  user_data = file("phpmyfaq_user_data.sh")

  tags = {
    Name = "phpMyFAQ-Server"
  }
}

# Salidas
output "instance_ip" {
  value = aws_instance.phpmyfaq_server.public_ip
}

output "private_key_path" {
  value = local_file.private_key.filename
}
