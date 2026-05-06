# IAM Cloud Lab — Plataforma de Gestión de Identidades con Keycloak
 
Plataforma de gestión de identidades y accesos (IAM) desplegada en dos entornos: **on-premises** con Docker y **cloud** con Terraform en AWS. Implementa autenticación centralizada (SSO), control de acceso basado en roles (RBAC), autenticación multifactor (MFA), federación de identidades y automatización del ciclo de vida de usuarios.
 
---
 
## Arquitectura
 
El proyecto se compone de:
 
- **Keycloak 24.0** como proveedor de identidades (IdP) centralizado
- **PostgreSQL 15** como base de datos (contenedor en local / RDS en AWS)
- **3 aplicaciones Flask** con control de acceso por roles:
  - **Portal** (`:5000`) → accesible por todos los roles
  - **Tickets** (`:5001`) → solo roles `soporte` y `admin`
  - **Admin** (`:5002`) → solo rol `admin`
- **Scripts Python** de auditoría y gestión automatizada de usuarios
---
 
## Funcionalidades implementadas
 
| Funcionalidad | Descripción |
|---|---|
| **SSO (Single Sign-On)** | Autenticación centralizada con OpenID Connect (Authorization Code Flow) |
| **RBAC** | Control de acceso basado en roles: empleado, soporte, admin |
| **MFA/TOTP** | Autenticación multifactor obligatoria con Google Authenticator |
| **Federación** | Login con GitHub como proveedor de identidades externo |
| **Auditoría** | Script de consulta de eventos de login, fallos y acciones administrativas |
| **Automatización** | Gestión del ciclo de vida de usuarios (alta, baja, reactivación, eliminación) vía API REST |
| **IaC** | Despliegue completo en AWS con Terraform (EC2, RDS, VPC, Security Groups) |
| **HTTPS** | Certificado SSL autofirmado para Keycloak en el entorno cloud |
 
---
 
## Estructura del repositorio
 
```
IAM-Cloud-Lab/
├── despliegue_on-premise/         # Código del entorno local
│   ├── docker-compose.yml         # Orquestación de contenedores
│   ├── apps/
│   │   ├── portal/                # App Flask - Portal del empleado
│   │   ├── tickets/               # App Flask - Sistema de tickets
│   │   └── admin/                 # App Flask - Panel de administración
│   └── scripts/
│       ├── audit.py               # Script de auditoría de eventos
│       ├── management.py          # Script de gestión de usuarios
│       └── empleados.json         # Datos de ejemplo para onboarding
│
├── despliegue_cloud/              # Código del entorno AWS
│   ├── main.tf                    # EC2, RDS, Key Pair, AMI
│   ├── network.tf                 # VPC, subnets, Internet Gateway
│   ├── security_groups.tf         # Reglas de firewall
│   ├── variables.tf               # Definición de variables
│   ├── output.tf                  # Outputs del despliegue
│   ├── provider.tf                # Provider de AWS
│   └── scripts/
│       └── setup_keycloak.sh      # Script de despliegue automático
│
├── Images/                        # Capturas para la documentación
├── Installation_on-premises.md    # Guía de instalación on-premises
├── Installation_cloud.md          # Guía de instalación en AWS
└── README.md
```
 
---
 
## Entorno On-Premises
 
Despliegue local en una VM con Ubuntu Server 22.04 LTS usando Docker.
 
**Requisitos:** VirtualBox, 4 GB RAM, 2 CPUs, 25 GB disco.
 
```bash
cd despliegue_on-premise
docker compose up -d
```
 
Acceder a Keycloak en `http://IP_VM:8080` y a las apps en los puertos 5000-5002.
 
[Guía completa de instalación on-premises →](despliegue_on-premise/Installation_on-premises.md)
 
---
 
## Entorno Cloud (AWS)
 
Despliegue automatizado en AWS con Terraform. Un solo comando crea toda la infraestructura y despliega la plataforma completa.
 
**Requisitos:** Cuenta AWS, Terraform, AWS CLI configurado.
 
```bash
cd despliegue_cloud
cp terraform.tfvars.example terraform.tfvars   # Editar con tus valores
terraform init
terraform apply
```
 
**Recursos desplegados:**
 
| Recurso | Tipo | Propósito |
|---|---|---|
| VPC | 10.0.0.0/16 | Red privada virtual |
| EC2 | t3.medium | Keycloak + apps en Docker |
| RDS | db.t3.micro, PostgreSQL 15 | Base de datos gestionada |
| Security Groups | 2 | Firewall EC2 y RDS |
 
[Guía completa de instalación cloud →](despliegue_cloud/Instalación-cloud.md)
 
---
 
## Scripts de automatización
 
### Gestión de usuarios
 
```bash
python3 management.py onboarding              # Alta masiva desde empleados.json
python3 management.py list                     # Listar usuarios
python3 management.py offboarding usuario      # Desactivar usuario
python3 management.py enable usuario           # Reactivar usuario
python3 management.py delete usuario           # Eliminar usuario
python3 management.py --help                   # Ayuda
```
 
### Auditoría
 
```bash
python3 audit.py                               # Informe de eventos
```
 
---
 
## Tecnologías
 
| Tecnología | Uso |
|---|---|
| Keycloak 24.0 | Proveedor de identidades |
| PostgreSQL 15 | Base de datos |
| Docker / Docker Compose | Contenedores |
| Python / Flask | Aplicaciones web |
| Terraform | Infrastructure as Code |
| AWS (EC2, RDS, VPC) | Cloud |
| OpenID Connect / OAuth 2.0 | Protocolos de autenticación |
| TOTP (RFC 6238) | Autenticación multifactor |
| JWT (RFC 7519) | Tokens de acceso |
 
---
 
## Seguridad
 
- Las credenciales se gestionan mediante variables de Terraform (`terraform.tfvars`) y nunca se hardcodean en el código.
- El archivo `terraform.tfvars` está en `.gitignore` y no se sube al repositorio.
- El acceso SSH en AWS está restringido a la IP del administrador.
- La base de datos RDS no es accesible desde internet.
- Keycloak en cloud funciona con HTTPS mediante certificado autofirmado.
---
 
## Autor
 
Pablo Caraballo Fernández
