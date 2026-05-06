from flask import Flask, redirect, url_for, session, request
from jose import jwt
import requests
 
app = Flask(__name__)
app.secret_key = 'clave-secreta-admin'
 
KEYCLOAK_EXTERNAL = "http://192.168.1.132:8080"
KEYCLOAK_INTERNAL = "http://keycloak:8080"
REALM = "iam-lab"
CLIENT_ID = "admin-app"
CLIENT_SECRET = "KiQ75qpWMSrpOJdlo8VYrbcNUHyMwkBM"
REDIRECT_URI = "http://192.168.1.132:5002/callback"
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
        f"?post_logout_redirect_uri=http://192.168.1.132:5002/"
        f"&client_id={CLIENT_ID}"
    )
    session.clear()
    return redirect(logout_url)
 
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002, debug=True)