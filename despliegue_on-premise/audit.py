import requests
import json
from datetime import datetime
 
KEYCLOAK_URL = "http://localhost:8080"
REALM = "iam-lab"
ADMIN_USER = "admin"
ADMIN_PASS = "admin123"
 
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
with open('/home/vboxuser/iam-lab/docs/audit_report.json', 'w') as f:
    json.dump(informe, f, indent=2)
print(f"\nInforme guardado en docs/audit_report.json")