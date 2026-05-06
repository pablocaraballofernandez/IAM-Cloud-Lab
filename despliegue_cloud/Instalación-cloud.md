# Instalación en AWS — Plataforma IAM con Keycloak

## Índice

1. [Introducción](#1-introducción)
2. [Requisitos previos](#2-requisitos-previos)
3. [Arquitectura en AWS](#3-arquitectura-en-aws)
4. [Estructura del proyecto Terraform](#4-estructura-del-proyecto-terraform)
5. [Descripción de los archivos](#5-descripción-de-los-archivos)
6. [Despliegue con Terraform](#6-despliegue-con-terraform)
7. [Verificación del despliegue](#7-verificación-del-despliegue)
8. [Despliegue](#8-despliegue)

---

## 1. Introducción

En esta fase del proyecto se migra la plataforma IAM desplegada en local a la nube de AWS, automatizando toda la infraestructura con **Terraform (Infrastructure as Code)**. El objetivo es que con un solo comando (`terraform apply`) se despliegue automáticamente toda la infraestructura necesaria: red, base de datos, servidor, certificado SSL, Keycloak configurado con realm, roles, usuarios, clientes, y las tres aplicaciones web.

Esto demuestra competencias en **cloud computing (AWS)**, **Infrastructure as Code (Terraform)** y **automatización de despliegues**, además de los conocimientos de IAM ya demostrados en la fase on-premises.

---

## 2. Requisitos previos

| Requisito | Descripción |
|---|---|
| Cuenta de AWS | Con permisos de administrador o al menos EC2, RDS, VPC e IAM |
| AWS CLI | Instalado y configurado con `aws configure` (Access Key + Secret Key) |
| Terraform | Instalado en el equipo local |
| Key Pair SSH | Clave pública/privada para acceder a la instancia EC2 |
| IP pública | Conocer nuestra IP pública para restringir el acceso SSH |

---

## 3. Arquitectura en AWS

La infraestructura desplegada se compone de los siguientes recursos:

| Recurso AWS | Configuración | Propósito |
|---|---|---|
| **VPC** | CIDR 10.0.0.0/16 | Red privada virtual |
| **Subnet pública** | 10.0.1.0/24 (AZ a) | Aloja la instancia EC2 |
| **Subnets privadas** | 10.0.2.0/24 (AZ a), 10.0.3.0/24 (AZ b) | Alojan la base de datos RDS |
| **Internet Gateway** | Asociado a la VPC | Acceso a internet desde la subnet pública |
| **EC2** | t3.medium, Ubuntu 22.04 | Ejecuta Keycloak y las apps en Docker |
| **RDS PostgreSQL** | db.t3.micro, PostgreSQL 15 | Base de datos de Keycloak |
| **Security Group EC2** | Puertos 22, 8080, 8443, 5000-5002 | Firewall de la instancia |
| **Security Group RDS** | Puerto 5432 (solo desde EC2) | Firewall de la base de datos |
| **Key Pair** | ED25519 | Acceso SSH a la EC2 |

**Flujo de red:**

- El usuario accede a Keycloak y a las aplicaciones a través del Internet Gateway.
- La EC2 se comunica con el RDS a través de la red interna de la VPC (puerto 5432).
- El acceso SSH está restringido exclusivamente a la IP del administrador.
- El RDS no es accesible desde internet.

---

## 4. Estructura del proyecto Terraform

```
Proyecto IAM/
├── provider.tf              # Configuración del provider de AWS
├── variables.tf             # Definición de variables
├── terraform.tfvars         # Valores de las variables (NO subir al repo)
├── main.tf                  # Instancia EC2, RDS, Key Pair, AMI
├── network.tf               # VPC, subnets, Internet Gateway, route tables
├── security_groups.tf       # Security groups de EC2 y RDS
├── output.tf                # Outputs (IP pública, endpoint RDS, enlaces)
├── docker-compose.yml       # Referencia del docker-compose generado
├── scripts/
│   └── setup_keycloak.sh    # Script de despliegue automático (user_data)
├── terraform.tfstate        # Estado de Terraform (NO subir al repo)
└── .terraform.lock.hcl      # Lock de providers
```
---

## 5. Descripción de los archivos

### 5.1 provider.tf

Define el proveedor cloud que vamos a utilizar. En este caso, AWS. Indica a Terraform qué plugin necesita descargar para poder crear recursos en AWS. La región se recibe como variable para poder cambiarla sin modificar el código.

### 5.2 variables.tf

Declara todas las variables que utiliza el proyecto, especificando su nombre, tipo y descripción. Las variables sensibles se marcan con `sensitive = true` para que Terraform no las muestre en la terminal durante la ejecución. Las variables declaradas son:

| Variable | Tipo | Descripción |
|---|---|---|
| `db_password` | string (sensitive) | Contraseña de la base de datos RDS |
| `db_username` | string (sensitive) | Usuario de la base de datos |
| `region` | string | Región de AWS (ej: eu-west-1) |
| `instance_keycloak` | string | Tipo de instancia EC2 (ej: t3.medium) |
| `key_name` | string | Ruta del key pair SSH local |
| `ssh_key` | string | Clave pública SSH para importar en AWS |
| `admin_IP` | list(string) | IP del administrador con máscara /32 para restringir SSH |
| `keycloak_admin` | string (sensitive) | Usuario administrador de Keycloak |
| `keycloak_admin_password` | string (sensitive) | Contraseña del administrador de Keycloak |

### 5.3 terraform.tfvars

Contiene los valores concretos de cada variable declarada en `variables.tf`. Este archivo es el único que tiene las credenciales reales y **nunca debe subirse al repositorio**. Cada persona que clone el proyecto debe crear su propio `terraform.tfvars` con sus valores.

### 5.4 network.tf

Define toda la infraestructura de red necesaria:

- **VPC:** la red privada virtual con rango 10.0.0.0/16 que aísla nuestros recursos del resto de AWS. Se habilita el soporte DNS para que los contenedores puedan resolver nombres internamente.
- **Subnet pública:** donde se aloja la EC2. Tiene habilitada la asignación automática de IP pública y está en la zona de disponibilidad "a" de la región.
- **Subnets privadas:** dos subnets en zonas de disponibilidad diferentes ("a" y "b"), necesarias para el RDS. AWS exige mínimo dos AZs distintas para garantizar alta disponibilidad de la base de datos.
- **Internet Gateway:** permite que la EC2 en la subnet pública acceda a internet y que los usuarios accedan a las aplicaciones desde el exterior.
- **Route Table:** tabla de rutas que dirige el tráfico con destino a internet (0.0.0.0/0) a través del Internet Gateway. Se asocia a la subnet pública.
- **DB Subnet Group:** agrupa las dos subnets privadas para indicar a AWS dónde puede colocar la base de datos RDS.

> **¿Por qué dos zonas de disponibilidad para el RDS?** Las AZs son centros de datos físicamente separados dentro de la misma región. Si una AZ sufre un fallo, la otra sigue operativa. AWS exige esta redundancia como requisito para crear un DB Subnet Group.

### 5.5 security_groups.tf

Define las reglas de firewall para cada recurso. Contiene dos security groups:

**Security Group de la EC2** — controla qué tráfico puede entrar y salir de la instancia:

| Puerto | Protocolo | Origen | Propósito |
|---|---|---|---|
| 22 | TCP | Solo IP del admin | Acceso SSH |
| 8080 | TCP | Cualquiera | Keycloak HTTP |
| 8443 | TCP | Cualquiera | Keycloak HTTPS |
| 5000-5002 | TCP | Cualquiera | Aplicaciones web |
| Todo | Todo | Cualquiera (salida) | Tráfico de salida |

**Security Group del RDS** — solo permite una regla de entrada:

| Puerto | Protocolo | Origen | Propósito |
|---|---|---|---|
| 5432 | TCP | Security Group de la EC2 | PostgreSQL |

> **Buenas prácticas:** El acceso SSH está restringido a una sola IP. El RDS solo acepta conexiones desde la EC2 usando referencia entre Security Groups (no IPs), lo que es más seguro y dinámico.

### 5.6 main.tf

Es el archivo principal donde se definen los recursos de computación y base de datos:

- **Data source de AMI:** busca dinámicamente la última imagen de Ubuntu Server 22.04 LTS publicada por Canonical, evitando hardcodear un ID de AMI que puede variar entre regiones o caducar con el tiempo.
- **Key Pair:** importa la clave pública SSH a AWS para poder acceder a la EC2 por SSH. La clave pública se recibe como variable.
- **Instancia EC2:** lanza una instancia del tipo especificado con la AMI de Ubuntu en la subnet pública. Se le asigna el security group de la EC2 y el key pair para SSH. El campo `user_data_base64` recibe el script `setup_keycloak.sh` comprimido con gzip (porque el script supera el límite de 16KB de user_data). Este script se ejecuta automáticamente al arrancar la instancia y despliega toda la plataforma.
- **Instancia RDS:** crea una base de datos PostgreSQL 15 gestionada por AWS en las subnets privadas. No es accesible desde internet y solo permite conexiones desde la EC2. Se crea automáticamente con la base de datos `keycloak` lista para usar.

### 5.7 output.tf

Define los valores que Terraform muestra tras completar el despliegue. Incluye la IP pública de la EC2, el endpoint del RDS, y los enlaces directos para acceder a Keycloak y a cada aplicación. Estos outputs se pueden consultar en cualquier momento con `terraform output`.

### 5.8 scripts/setup_keycloak.sh

Es el script que se ejecuta automáticamente en la EC2 al arrancar por primera vez (user_data de cloud-init). Recibe las variables sensibles desde Terraform mediante `templatefile()` y realiza todo el proceso de despliegue:

1. **Instalación de dependencias:** instala Docker, Docker Compose, Python pip y jq.
2. **Obtención de la IP pública:** consulta el servicio de metadatos de la instancia EC2 para obtener su IP pública dinámica.
3. **Generación del certificado SSL:** crea un certificado autofirmado con OpenSSL para que Keycloak funcione por HTTPS.
4. **Creación del docker-compose.yml:** genera el archivo con los servicios de Keycloak y las tres aplicaciones, inyectando las variables de conexión a la base de datos RDS. Utiliza placeholders que se sustituyen con `sed` para evitar problemas de indentación YAML.
5. **Arranque de Keycloak:** levanta el contenedor de Keycloak y espera en bucle a que esté operativo consultando su endpoint de salud.
6. **Configuración de Keycloak vía API REST:** usando curl y jq, crea automáticamente el realm, los tres roles (empleado, soporte, admin), los tres usuarios de prueba con sus contraseñas y roles asignados, y los tres clientes (portal-app, tickets-app, admin-app) obteniendo los client secrets generados.
7. **Creación de las aplicaciones Flask:** genera los archivos app.py de cada aplicación con la IP pública correcta y el client secret correspondiente, incluyendo la lógica de control de acceso (RBAC).
8. **Despliegue completo:** construye las imágenes Docker de las tres apps y levanta todos los contenedores.

> **Nota:** Las credenciales nunca se hardcodean en el script. Se reciben como variables de Terraform, que a su vez las lee de `terraform.tfvars`.

### 5.9 docker-compose.yml

El archivo `docker-compose.yml` del repositorio es una referencia de la estructura que genera automáticamente el script `setup_keycloak.sh` dentro de la EC2. A diferencia de la versión on-premises, esta versión no incluye un servicio de PostgreSQL porque la base de datos está gestionada por AWS RDS de forma externa.

---

## 6. Despliegue con Terraform

El proceso de despliegue se realiza en tres comandos:

```
terraform init       # Descarga los plugins del provider de AWS
terraform plan       # Muestra qué recursos se van a crear (sin crear nada)
terraform apply      # Crea toda la infraestructura (pide confirmación)
```

El `terraform apply` tardará unos 10-15 minutos, ya que el RDS tarda varios minutos en crearse. Después, la EC2 ejecuta el script de despliegue que necesita otros 5-10 minutos para descargar imágenes Docker, arrancar Keycloak y configurar todo.

Para consultar los datos del despliegue:

```
terraform output     # Muestra IP pública, endpoint RDS y enlaces
```

Para conectarse a la EC2 por SSH:

```
ssh -i clave_privada ubuntu@IP_PUBLICA
```

Para verificar el progreso del script de despliegue dentro de la EC2:

```
cloud-init status                          # done = terminado
tail -f /var/log/cloud-init-output.log     # Ver progreso en tiempo real
```

Para destruir toda la infraestructura cuando no se necesite:

```
terraform destroy    # Elimina todos los recursos (pide confirmación)
```

---

## 7. Verificación del despliegue

Una vez que el script de despliegue finaliza, verificamos que todo funciona:

| Servicio | URL | Credenciales |
|---|---|---|
| Keycloak Admin | `https://IP_PUBLICA:8443` | admin / (la configurada en tfvars) |
| Portal | `http://IP_PUBLICA:5000` | Cualquier usuario del realm |
| Tickets | `http://IP_PUBLICA:5001` | Solo usuarios con rol soporte o admin |
| Admin | `http://IP_PUBLICA:5002` | Solo usuarios con rol admin |

**Comprobaciones recomendadas:**

1. Acceder a la consola de Keycloak y verificar que el realm `iam-lab` existe con los roles, usuarios y clientes configurados.
2. Iniciar sesión en cada aplicación con usuarios de distintos roles para verificar el RBAC.
3. Comprobar que el SSO funciona: al autenticarse en una app, las demás reconocen la sesión.
4. Verificar que el certificado SSL funciona en Keycloak (el navegador avisará que es autofirmado, lo cual es esperado).

## 8. Despliegue

Desplegamos la instancia:

![Imágenes](Images/Cloud/1.png)

![Imágenes](Images/Cloud/2.png)

![Imágenes](Images/Cloud/3.png)


Y como vemos están todos los usuarios que creamos y todo debería de funcionar tal y como en el on-premise:

![Imágenes](Images/Cloud/4.png)

Ahora vamos a hacer un inicio de sesion:

![Imágenes](Images/Cloud/5.png)

![Imágenes](Images/Cloud/6.png)

![Imágenes](Images/Cloud/7.png)

![Imágenes](Images/Cloud/8.png)

Y ahora vamos a comprobar ese inicio de sesión en el script de audit.py: 

![Imágenes](Images/Cloud/9.png)

Y ahora vamos a comprobar que el script de management.py nos lista los usuarios:

![Imágenes](Images/Cloud/10.png)







