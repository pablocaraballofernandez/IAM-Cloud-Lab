output "public_ip" {
    description = "Ip pública de keycloak"
    value = aws_instance.keycloak.public_ip
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos RDS"
  value       = aws_db_instance.keycloak_db.endpoint
}

output "Enlace_panel_Keycloak" {
  description = "Enlace del pnael de administración" 
  value = "https://${aws_instance.keycloak.public_ip}:8443"
}

output "Portal_empleados" {
  description = "Enlace portal de empleados"
  value = "http://${aws_instance.keycloak.public_ip}:5000"
}

output "SSH" {
  description = "Conectarse por ssh"
  value = "ssh -i ~/.ssh/${aws_instance.keycloak.key_name} ubuntu@${aws_instance.keycloak.public_ip}"
}

output "Tickets" {
  description = "Tickets"
  value = "http://${aws_instance.keycloak.public_ip}:5001"
}

output "Panel_de_administración" {
  description = "Administración"
  value = "http://${aws_instance.keycloak.public_ip}:5002"
  
}