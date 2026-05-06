import requests
import json
import sys

KEYCLOAK_URL = "http://192.168.1.132:8080"
REALM = "iam-lab"
ADMIN_USER = "admin"
ADMIN_PASS = "admin123"
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
    print("Uso: python3 user_management.py [comando] [argumentos]")
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
    print("  python3 user_management.py onboarding")
    print("  python3 user_management.py onboarding datos.json")
    print("  python3 user_management.py list")
    print("  python3 user_management.py offboarding pedro.garcia elena.ruiz")
    print("  python3 user_management.py enable pedro.garcia")
    print("  python3 user_management.py delete pedro.garcia")

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
        archivo = sys.argv[2] if len(sys.argv) > 2 else '/home/vboxuser/iam-lab/docs/empleados.json'
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
    elif comando in ['help', '--help', '-h']:
        show_help()
    else:
        show_help()