#!/bin/bash
set -e

sleep 10

apt-get update
apt-get install -y docker.io docker-compose-v2 python3-pip jq
systemctl enable docker
systemctl start docker

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
DB_HOST="${db_host}"
DB_PASS="${db_password}"
DB_USER="${db_username}"
KC_ADMIN="${keycloak_admin}"
KC_ADMIN_PASS="${keycloak_admin_password}"

mkdir -p /home/ubuntu/iam-lab/apps/portal
mkdir -p /home/ubuntu/iam-lab/apps/tickets
mkdir -p /home/ubuntu/iam-lab/apps/admin
mkdir -p /home/ubuntu/iam-lab/scripts
mkdir -p /home/ubuntu/iam-lab/docs
mkdir -p /home/ubuntu/iam-lab/certs

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /home/ubuntu/iam-lab/certs/server.key \
  -out /home/ubuntu/iam-lab/certs/server.crt \
  -subj "/CN=$PUBLIC_IP"
chmod 644 /home/ubuntu/iam-lab/certs/server.key
chmod 644 /home/ubuntu/iam-lab/certs/server.crt

cat > /home/ubuntu/iam-lab/docker-compose.yml <<'COMPOSEFILE'
services:
  keycloak:
    image: quay.io/keycloak/keycloak:24.0
    container_name: iam-keycloak
    environment:
      KC_DB: postgres
      KC_DB_URL: KC_DB_URL_PLACEHOLDER
      KC_DB_USERNAME: KC_DB_USER_PLACEHOLDER
      KC_DB_PASSWORD: KC_DB_PASS_PLACEHOLDER
      KEYCLOAK_ADMIN: KC_ADMIN_PLACEHOLDER
      KEYCLOAK_ADMIN_PASSWORD: KC_ADMIN_PASS_PLACEHOLDER
      KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/conf/server.crt
      KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/conf/server.key
    command: start-dev
    ports:
      - "8443:8443"
      - "8080:8080"
    volumes:
      - "/home/ubuntu/iam-lab/certs/server.crt:/opt/keycloak/conf/server.crt"
      - "/home/ubuntu/iam-lab/certs/server.key:/opt/keycloak/conf/server.key"
    networks:
      - iam-network
    restart: unless-stopped
  portal:
    build: ./apps/portal
    container_name: iam-portal
    ports:
      - "5000:5000"
    depends_on:
      - keycloak
    networks:
      - iam-network
    restart: unless-stopped
  tickets:
    build: ./apps/tickets
    container_name: iam-tickets
    ports:
      - "5001:5001"
    depends_on:
      - keycloak
    networks:
      - iam-network
    restart: unless-stopped
  admin:
    build: ./apps/admin
    container_name: iam-admin
    ports:
      - "5002:5002"
    depends_on:
      - keycloak
    networks:
      - iam-network
    restart: unless-stopped
networks:
  iam-network:
    driver: bridge
COMPOSEFILE

sed -i "s|KC_DB_URL_PLACEHOLDER|jdbc:postgresql://$DB_HOST:5432/keycloak|g" /home/ubuntu/iam-lab/docker-compose.yml
sed -i "s|KC_DB_USER_PLACEHOLDER|$DB_USER|g" /home/ubuntu/iam-lab/docker-compose.yml
sed -i "s|KC_DB_PASS_PLACEHOLDER|$DB_PASS|g" /home/ubuntu/iam-lab/docker-compose.yml
sed -i "s|KC_ADMIN_PLACEHOLDER|$KC_ADMIN|g" /home/ubuntu/iam-lab/docker-compose.yml
sed -i "s|KC_ADMIN_PASS_PLACEHOLDER|$KC_ADMIN_PASS|g" /home/ubuntu/iam-lab/docker-compose.yml


cat > /home/ubuntu/iam-lab/apps/portal/requirements.txt <<'EOF'
flask
python-jose
requests
EOF
cp /home/ubuntu/iam-lab/apps/portal/requirements.txt /home/ubuntu/iam-lab/apps/tickets/requirements.txt
cp /home/ubuntu/iam-lab/apps/portal/requirements.txt /home/ubuntu/iam-lab/apps/admin/requirements.txt

cat > /home/ubuntu/iam-lab/apps/portal/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

cat > /home/ubuntu/iam-lab/apps/tickets/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5001
CMD ["python", "app.py"]
EOF

cat > /home/ubuntu/iam-lab/apps/admin/Dockerfile <<'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5002
CMD ["python", "app.py"]
EOF

cd /home/ubuntu/iam-lab
docker compose up -d keycloak

echo "Esperando a que Keycloak arranque..."
until curl -sf http://localhost:8080/realms/master > /dev/null 2>&1; do
  sleep 5
done
echo "Keycloak listo"

KC_URL="http://localhost:8080"

TOKEN=$(curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=$KC_ADMIN&password=$KC_ADMIN_PASS" \
  | jq -r '.access_token')

curl -sf -X POST "$KC_URL/admin/realms" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"realm":"iam-lab","enabled":true}'

for ROLE in empleado soporte admin; do
  curl -sf -X POST "$KC_URL/admin/realms/iam-lab/roles" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$ROLE\"}"
done

create_user() {
  local username=$1 first=$2 last=$3 email=$4 role=$5
  curl -sf -X POST "$KC_URL/admin/realms/iam-lab/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$username\",\"firstName\":\"$first\",\"lastName\":\"$last\",\"email\":\"$email\",\"enabled\":true,\"credentials\":[{\"type\":\"password\",\"value\":\"password123\",\"temporary\":false}]}"
  USER_ID=$(curl -sf "$KC_URL/admin/realms/iam-lab/users?username=$username&exact=true" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')
  ROLE_DATA=$(curl -sf "$KC_URL/admin/realms/iam-lab/roles/$role" \
    -H "Authorization: Bearer $TOKEN")
  curl -sf -X POST "$KC_URL/admin/realms/iam-lab/users/$USER_ID/role-mappings/realm" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "[$ROLE_DATA]"
}

create_user "jurope" "Juan" "Rodriguez" "juanrodriguezperez@empresa.local" "soporte"
create_user "lajisa" "Laura" "Jimenez" "laurajimenezsanchez@empresa.local" "admin"
create_user "cacaar" "Carlos" "Caballero" "carloscaballeroarcila@empresa.local" "empleado"

create_client() {
  local client_id=$1 port=$2
  curl -sf -X POST "$KC_URL/admin/realms/iam-lab/clients" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"clientId\":\"$client_id\",\"enabled\":true,\"protocol\":\"openid-connect\",\"publicClient\":false,\"serviceAccountsEnabled\":false,\"redirectUris\":[\"http://$PUBLIC_IP:$port/*\"],\"webOrigins\":[\"http://$PUBLIC_IP:$port\"]}"
  CLIENT_UUID=$(curl -sf "$KC_URL/admin/realms/iam-lab/clients?clientId=$client_id" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')
  curl -sf "$KC_URL/admin/realms/iam-lab/clients/$CLIENT_UUID/client-secret" \
    -H "Authorization: Bearer $TOKEN" | jq -r '.value'
}

PORTAL_SECRET=$(create_client "portal-app" 5000)
TICKETS_SECRET=$(create_client "tickets-app" 5001)
ADMIN_SECRET=$(create_client "admin-app" 5002)

cat > /home/ubuntu/iam-lab/apps/portal/app.py <<PYEOF
from flask import Flask, redirect, url_for, session, request
from jose import jwt
import requests

app = Flask(__name__)
app.secret_key = 'clave-secreta-desarrollo'

KEYCLOAK_EXTERNAL = "https://$PUBLIC_IP:8443"
KEYCLOAK_INTERNAL = "http://keycloak:8080"
REALM = "iam-lab"
CLIENT_ID = "portal-app"
CLIENT_SECRET = "$PORTAL_SECRET"
REDIRECT_URI = "http://$PUBLIC_IP:5000/callback"

@app.route('/')
def home():
    if 'token' in session:
        return f"""
        <h1>Portal del empleado</h1>
        <p>Bienvenido, {session.get('username', 'usuario')}</p>
        <p>Roles: {session.get('roles', [])}</p>
        <a href="/logout">Cerrar sesion</a>
        """
    return '<h1>Portal del empleado</h1><a href="/login">Iniciar sesion</a>'

@app.route('/login')
def login():
    auth_url = (
        f"{KEYCLOAK_EXTERNAL}/realms/{REALM}/protocol/openid-connect/auth"
        f"?client_id={CLIENT_ID}"
        f"&response_type=code"
        f"&redirect_uri={REDIRECT_URI}"
        f"&scope=openid"
    )
    return redirect(auth_url)

@app.route('/callback')
def callback():
    code = request.args.get('code')
    if not code:
        return 'Error: no se recibio codigo', 400
    token_url = f"{KEYCLOAK_INTERNAL}/realms/{REALM}/protocol/openid-connect/token"
    data = {
        'grant_type': 'authorization_code',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'code': code,
        'redirect_uri': REDIRECT_URI
    }
    response = requests.post(token_url, data=data)
    token_data = response.json()
    if 'access_token' not in token_data:
        return f'Error al obtener token: {token_data}', 400
    claims = jwt.get_unverified_claims(token_data['access_token'])
    session['token'] = token_data['access_token']
    session['username'] = claims.get('preferred_username', 'desconocido')
    session['roles'] = claims.get('realm_access', {}).get('roles', [])
    return redirect(url_for('home'))

@app.route('/logout')
def logout():
    logout_url = (
        f"{KEYCLOAK_EXTERNAL}/realms/{REALM}/protocol/openid-connect/logout"
        f"?post_logout_redirect_uri=http://$PUBLIC_IP:5000/"
        f"&client_id={CLIENT_ID}"
    )
    session.clear()
    return redirect(logout_url)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
PYEOF

cat > /home/ubuntu/iam-lab/apps/tickets/app.py <<PYEOF
from flask import Flask, redirect, url_for, session, request
from jose import jwt
import requests

app = Flask(__name__)
app.secret_key = 'clave-secreta-tickets'

KEYCLOAK_EXTERNAL = "https://$PUBLIC_IP:8443"
KEYCLOAK_INTERNAL = "http://keycloak:8080"
REALM = "iam-lab"
CLIENT_ID = "tickets-app"
CLIENT_SECRET = "$TICKETS_SECRET"
REDIRECT_URI = "http://$PUBLIC_IP:5001/callback"
ROLES_PERMITIDOS = ["soporte", "admin"]

@app.route('/')
def home():
    if 'token' in session:
        roles = session.get('roles', [])
        tiene_acceso = any(r in ROLES_PERMITIDOS for r in roles)
        if not tiene_acceso:
            return f"""
            <h1>Sistema de tickets</h1>
            <p>Acceso denegado, {session.get('username')}</p>
            <p>Tus roles: {roles}</p>
            <p>Se requiere: {ROLES_PERMITIDOS}</p>
            <a href="/logout">Cerrar sesion</a>
            """, 403
        return f"""
        <h1>Sistema de tickets</h1>
        <p>Bienvenido, {session.get('username')}</p>
        <p>Roles: {roles}</p>
        <a href="/logout">Cerrar sesion</a>
        """
    return '<h1>Sistema de tickets</h1><a href="/login">Iniciar sesion</a>'

@app.route('/login')
def login():
    auth_url = (
        f"{KEYCLOAK_EXTERNAL}/realms/{REALM}/protocol/openid-connect/auth"
        f"?client_id={CLIENT_ID}"
        f"&response_type=code"
        f"&redirect_uri={REDIRECT_URI}"
        f"&scope=openid"
    )
    return redirect(auth_url)

@app.route('/callback')
def callback():
    code = request.args.get('code')
    if not code:
        return 'Error: no se recibio codigo', 400
    token_url = f"{KEYCLOAK_INTERNAL}/realms/{REALM}/protocol/openid-connect/token"
    data = {
        'grant_type': 'authorization_code',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'code': code,
        'redirect_uri': REDIRECT_URI
    }
    response = requests.post(token_url, data=data)
    token_data = response.json()
    if 'access_token' not in token_data:
        return f'Error al obtener token: {token_data}', 400
    claims = jwt.get_unverified_claims(token_data['access_token'])
    session['token'] = token_data['access_token']
    session['username'] = claims.get('preferred_username', 'desconocido')
    session['roles'] = claims.get('realm_access', {}).get('roles', [])
    return redirect(url_for('home'))

@app.route('/logout')
def logout():
    logout_url = (
        f"{KEYCLOAK_EXTERNAL}/realms/{REALM}/protocol/openid-connect/logout"
        f"?post_logout_redirect_uri=http://$PUBLIC_IP:5001/"
        f"&client_id={CLIENT_ID}"
    )
    session.clear()
    return redirect(logout_url)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)
PYEOF

cat > /home/ubuntu/iam-lab/apps/admin/app.py <<PYEOF
from flask import Flask, redirect, url_for, session, request
from jose import jwt
import requests

app = Flask(__name__)
app.secret_key = 'clave-secreta-admin'

KEYCLOAK_EXTERNAL = "https://$PUBLIC_IP:8443"
KEYCLOAK_INTERNAL = "http://keycloak:8080"
REALM = "iam-lab"
CLIENT_ID = "admin-app"
CLIENT_SECRET = "$ADMIN_SECRET"
REDIRECT_URI = "http://$PUBLIC_IP:5002/callback"
ROLES_PERMITIDOS = ["admin"]

@app.route('/')
def home():
    if 'token' in session:
        roles = session.get('roles', [])
        tiene_acceso = any(r in ROLES_PERMITIDOS for r in roles)
        if not tiene_acceso:
            return f"""
            <h1>Panel de administracion</h1>
            <p>Acceso denegado, {session.get('username')}</p>
            <p>Tus roles: {roles}</p>
            <p>Se requiere: {ROLES_PERMITIDOS}</p>
            <a href="/logout">Cerrar sesion</a>
            """, 403
        return f"""
        <h1>Panel de administracion</h1>
        <p>Bienvenido, {session.get('username')}</p>
        <p>Roles: {roles}</p>
        <a href="/logout">Cerrar sesion</a>
        """
    return '<h1>Panel de administracion</h1><a href="/login">Iniciar sesion</a>'

@app.route('/login')
def login():
    auth_url = (
        f"{KEYCLOAK_EXTERNAL}/realms/{REALM}/protocol/openid-connect/auth"
        f"?client_id={CLIENT_ID}"
        f"&response_type=code"
        f"&redirect_uri={REDIRECT_URI}"
        f"&scope=openid"
    )
    return redirect(auth_url)

@app.route('/callback')
def callback():
    code = request.args.get('code')
    if not code:
        return 'Error: no se recibio codigo', 400
    token_url = f"{KEYCLOAK_INTERNAL}/realms/{REALM}/protocol/openid-connect/token"
    data = {
        'grant_type': 'authorization_code',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'code': code,
        'redirect_uri': REDIRECT_URI
    }
    response = requests.post(token_url, data=data)
    token_data = response.json()
    if 'access_token' not in token_data:
        return f'Error al obtener token: {token_data}', 400
    claims = jwt.get_unverified_claims(token_data['access_token'])
    session['token'] = token_data['access_token']
    session['username'] = claims.get('preferred_username', 'desconocido')
    session['roles'] = claims.get('realm_access', {}).get('roles', [])
    return redirect(url_for('home'))

@app.route('/logout')
def logout():
    logout_url = (
        f"{KEYCLOAK_EXTERNAL}/realms/{REALM}/protocol/openid-connect/logout"
        f"?post_logout_redirect_uri=http://$PUBLIC_IP:5002/"
        f"&client_id={CLIENT_ID}"
    )
    session.clear()
    return redirect(logout_url)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002, debug=True)
PYEOF

cat > /home/ubuntu/iam-lab/scripts/audit.py <<'PYEOF'
import requests
import json
from datetime import datetime

KEYCLOAK_URL = "http://localhost:8080"
REALM = "iam-lab"
ADMIN_USER = "admin"
ADMIN_PASS = "password123"

def get_admin_token():
    url = f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token"
    data = {
        'grant_type': 'password',
        'client_id': 'admin-cli',
        'username': ADMIN_USER,
        'password': ADMIN_PASS
    }
    response = requests.post(url, data=data)
    return response.json()['access_token']

def get_events(token, realm):
    url = f"{KEYCLOAK_URL}/admin/realms/{realm}/events"
    headers = {'Authorization': f'Bearer {token}'}
    return requests.get(url, headers=headers).json()

def get_admin_events(token, realm):
    url = f"{KEYCLOAK_URL}/admin/realms/{realm}/admin-events"
    headers = {'Authorization': f'Bearer {token}'}
    return requests.get(url, headers=headers).json()

def show_events(events, tipo_evento, titulo):
    print(f"\n{'=' * 60}")
    print(titulo)
    print("=" * 60)
    filtrados = [e for e in events if e.get('type') == tipo_evento]
    if filtrados:
        for e in filtrados:
            t = datetime.fromtimestamp(e['time'] / 1000).strftime('%Y-%m-%d %H:%M:%S')
            u = e.get('details', {}).get('username', 'desconocido')
            ip = e.get('ipAddress', 'desconocida')
            if tipo_evento == 'LOGIN_ERROR':
                err = e.get('error', 'sin detalle')
                print(f"  [{t}] Usuario: {u} | IP: {ip} | Error: {err}")
            else:
                print(f"  [{t}] Usuario: {u} | IP: {ip}")
    else:
        print("  No hay eventos registrados")

token = get_admin_token()
print("=" * 60)
print("INFORME DE AUDITORIA - IAM LAB")
print(f"Fecha: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
print("=" * 60)

for realm, nombre in [(REALM, "APLICACIONES (iam-lab)"), ("master", "CONSOLA ADMIN (master)")]:
    events = get_events(token, realm)
    print(f"\nTotal eventos {nombre}: {len(events)}")
    tipos = {}
    for e in events:
        t = e.get('type', 'DESCONOCIDO')
        tipos[t] = tipos.get(t, 0) + 1
    if tipos:
        print("Resumen por tipo:")
        for t, c in sorted(tipos.items()):
            print(f"  {t}: {c}")
    show_events(events, 'LOGIN', f"LOGINS EXITOSOS - {nombre}")
    show_events(events, 'LOGIN_ERROR', f"LOGINS FALLIDOS - {nombre}")

admin_events = get_admin_events(token, REALM)
print(f"\n{'=' * 60}")
print(f"EVENTOS ADMINISTRATIVOS ({len(admin_events)})")
print("=" * 60)
if admin_events:
    for a in admin_events:
        t = datetime.fromtimestamp(a['time'] / 1000).strftime('%Y-%m-%d %H:%M:%S')
        op = a.get('operationType', 'desconocida')
        rec = a.get('resourceType', 'desconocido')
        path = a.get('resourcePath', '')
        print(f"  [{t}] {op} {rec} | {path}")
else:
    print("  No hay eventos administrativos registrados")

informe = {
    'fecha': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'eventos_iam_lab': get_events(token, REALM),
    'eventos_master': get_events(token, 'master'),
    'eventos_admin': admin_events
}
with open('/home/ubuntu/iam-lab/docs/audit_report.json', 'w') as f:
    json.dump(informe, f, indent=2)
print(f"\nInforme guardado en docs/audit_report.json")
PYEOF

cat > /home/ubuntu/iam-lab/scripts/audit.py <<'PYEOF'
import requests
import json
import sys

KEYCLOAK_URL = "http://localhost:8080"
REALM = "iam-lab"
ADMIN_USER = "admin"
ADMIN_PASS = "password123"
DEFAULT_PASSWORD = "Temporal123!"

def get_admin_token():
    url = f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token"
    data = {
        'grant_type': 'password',
        'client_id': 'admin-cli',
        'username': ADMIN_USER,
        'password': ADMIN_PASS
    }
    response = requests.post(url, data=data)
    return response.json()['access_token']

def get_headers(token):
    return {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }

def get_role_id(token, role_name):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/roles/{role_name}"
    response = requests.get(url, headers=get_headers(token))
    if response.status_code == 200:
        return response.json()
    return None

def get_user_by_username(token, username):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/users?username={username}&exact=true"
    response = requests.get(url, headers=get_headers(token))
    users = response.json()
    if users:
        return users[0]
    return None

def create_user(token, user_data):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/users"
    payload = {
        'username': user_data['username'],
        'email': user_data['email'],
        'firstName': user_data['firstName'],
        'lastName': user_data['lastName'],
        'enabled': True,
        'credentials': [{
            'type': 'password',
            'value': DEFAULT_PASSWORD,
            'temporary': True
        }]
    }
    response = requests.post(url, headers=get_headers(token), json=payload)
    return response.status_code

def assign_role(token, user_id, role):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/users/{user_id}/role-mappings/realm"
    response = requests.post(url, headers=get_headers(token), json=[role])
    return response.status_code

def disable_user(token, user_id):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/users/{user_id}"
    response = requests.put(url, headers=get_headers(token), json={'enabled': False})
    return response.status_code

def enable_user(token, user_id):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/users/{user_id}"
    response = requests.put(url, headers=get_headers(token), json={'enabled': True})
    return response.status_code

def delete_user(token, user_id):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/users/{user_id}"
    response = requests.delete(url, headers=get_headers(token))
    return response.status_code

def list_users(token):
    url = f"{KEYCLOAK_URL}/admin/realms/{REALM}/users?max=100"
    response = requests.get(url, headers=get_headers(token))
    return response.json()

def onboarding(token, archivo):
    with open(archivo, 'r') as f:
        empleados = json.load(f)

    print("=" * 60)
    print("ONBOARDING - Alta masiva de usuarios")
    print("=" * 60)

    for emp in empleados:
        username = emp['username']
        existing = get_user_by_username(token, username)
        if existing:
            print(f"  [EXISTE] {username} ya esta registrado, omitiendo")
            continue

        status = create_user(token, emp)
        if status == 201:
            user = get_user_by_username(token, username)
            role = get_role_id(token, emp['departamento'])
            if user and role:
                assign_role(token, user['id'], role)
                print(f"  [OK] {username} creado con rol '{emp['departamento']}'")
            else:
                print(f"  [AVISO] {username} creado pero no se pudo asignar rol '{emp['departamento']}'")
        else:
            print(f"  [ERROR] No se pudo crear {username} (status: {status})")

    print(f"\nContrasena temporal para todos: {DEFAULT_PASSWORD}")
    print("Los usuarios deberan cambiarla en su primer login")

def offboarding(token, usernames):
    print("=" * 60)
    print("OFFBOARDING - Desactivacion de usuarios")
    print("=" * 60)

    for username in usernames:
        user = get_user_by_username(token, username)
        if not user:
            print(f"  [ERROR] Usuario {username} no encontrado")
            continue

        status = disable_user(token, user['id'])
        if status == 204:
            print(f"  [OK] {username} desactivado")
        else:
            print(f"  [ERROR] No se pudo desactivar {username} (status: {status})")

def show_users(token):
    users = list_users(token)
    print("=" * 60)
    print(f"USUARIOS REGISTRADOS ({len(users)})")
    print("=" * 60)
    for u in users:
        estado = "activo" if u.get('enabled', False) else "desactivado"
        print(f"  {u['username']:20s} | {u.get('email', 'sin email'):30s} | {estado}")

def show_help():
    print("=" * 60)
    print("GESTION DE USUARIOS - IAM LAB")
    print("=" * 60)
    print("")
    print("Uso: python3 management.py [comando] [argumentos]")
    print("")
    print("Comandos disponibles:")
    print("  onboarding [archivo]    Alta masiva de usuarios desde un fichero JSON")
    print("                          Por defecto usa empleados.json")
    print("  offboarding <usuarios>  Desactivar uno o varios usuarios")
    print("  enable <usuario>        Reactivar un usuario desactivado")
    print("  delete <usuarios>       Eliminar uno o varios usuarios")
    print("  list                    Listar todos los usuarios y su estado")
    print("  help                    Mostrar esta ayuda")
    print("")
    print("Ejemplos:")
    print("  python3 management.py onboarding")
    print("  python3 management.py onboarding datos.json")
    print("  python3 management.py list")
    print("  python3 management.py offboarding pedro.garcia elena.ruiz")
    print("  python3 management.py enable pedro.garcia")
    print("  python3 management.py delete pedro.garcia")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        show_help()
        sys.exit(1)

    comando = sys.argv[1]

    if comando in ['help', '--help', '-h']:
        show_help()
        sys.exit(0)

    token = get_admin_token()

    if comando == 'onboarding':
        archivo = sys.argv[2] if len(sys.argv) > 2 else 'empleados.json'
        onboarding(token, archivo)
    elif comando == 'offboarding':
        if len(sys.argv) < 3:
            print("Indica los usuarios a desactivar")
            sys.exit(1)
        offboarding(token, sys.argv[2:])
    elif comando == 'list':
        show_users(token)
    elif comando == 'enable':
        if len(sys.argv) < 3:
            print("Indica el usuario a reactivar")
            sys.exit(1)
        user = get_user_by_username(token, sys.argv[2])
        if user:
            enable_user(token, user['id'])
            print(f"  [OK] {sys.argv[2]} reactivado")
        else:
            print(f"  [ERROR] Usuario {sys.argv[2]} no encontrado")
    elif comando == 'delete':
        if len(sys.argv) < 3:
            print("Indica el usuario a eliminar")
            sys.exit(1)
        for username in sys.argv[2:]:
            user = get_user_by_username(token, username)
            if user:
                status = delete_user(token, user['id'])
                if status == 204:
                    print(f"  [OK] {username} eliminado")
                else:
                    print(f"  [ERROR] No se pudo eliminar {username} (status: {status})")
            else:
                print(f"  [ERROR] Usuario {username} no encontrado")
    else:
        show_help()
PYEOF

touch /home/ubuntu/iam-lab/docs/empleados.json

cd /home/ubuntu/iam-lab
docker compose up -d --build

chown -R ubuntu:ubuntu /home/ubuntu/iam-lab

echo "=== IAM LAB DESPLEGADO ==="
