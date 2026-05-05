Primero vamos a desplegar nuestra máquina de ubuntu server y actualizamos repositorios:

![Imágenes](Images/1.png)

Ahora voy a conectarme por ssh desde mi ordenador principal por la comodidad de la terminal:

![Imágenes](Images/2.png)

Ahora vamos a instalar docker y docker compose

![Imágenes](Images/3.png)

Asignamos unusuario para docker:

![Imágenes](Images/4.png)

Instalamos git y pip de python, y luego instalamos la librería requests con pip:

![Imágenes](Images/5.png)

Verificamos versiones de los servicios para ver si se han instalado correctamente y en su última versión:

![Imágenes](Images/6.png)

No olivdeis habilitar docker e iniciarlo con systemct enable docker y systemctl start docker

Creamos la estructura de directorios y el docker-compose.yml (el archivo esta en el repo):

![Imágenes](Images/7.png)

Este docker-compose.yml le dice a Docker: levántame un PostgreSQL con esta contraseña, un Keycloak conectado a ese PostgreSQL, y tres apps Flask conectadas a Keycloak, todos en la misma red interna para que puedan hablar entre ellos. También define qué puertos exponer al exterior y que si un contenedor se cae, se reinicie automáticamente.

Lanzamos el docker-compose:

![Imágenes](Images/8.png)

Ahora verificaremos que los servicios estan corriendo en los puertos deseados, y como podemos ver, keycloak esta corriendo en el puerto 8080:

![Imágenes](Images/9.png)

Ahora vamos a pasar al proceso de gestión de keycloak.

Iniciamos sesión con las credenciales de administrador que hayamos designado.

Creamos un realm y lo llamamos como queramos: 

![Imágenes](Images/10.png)

Ahora crearemos lo roles en los que queramos clasificar a nuestros usuarios. En este caso he creado tres roles (admin, soporte y empleado).

IMPORTANTE, no borrar los roles por defecto de keycloak, ya que estos roles realizan funciones que al borrarlas podrían generar problemas:

![Imágenes](Images/11.png)

Ahora crearemos los usuarios, recordad crear contraseñas para los usuarios y quitar que sean temporales para este laboratorio ya que solo queremos comprobar el funcionamiento. También asignar el rol que quereis que ejerza:

![Imágenes](Images/12.png)

![Imágenes](Images/13.png)

![Imágenes](Images/22.png)


Ahora crearemos el cliente. En Keycloak, un cliente es cualquier aplicación o servicio que quiere usar Keycloak para autenticar usuarios y/o autorizar acceso:

![Imágenes](Images/14.png)

![Imágenes](Images/15.png)

![Imágenes](Images/16.png)

De los clientes debemos de coger el token secreto e introducrilo en el código de cada app, por ejemplo, el token de admin-app lo introduciremos en admin/app.py. 

¿Qué es este código?

Cuando registras una aplicación en Keycloak como "cliente confidencial" (Client authentication: ON), Keycloak le genera un Client Secret, que es una contraseña única para esa aplicación.
Funciona así: cuando un usuario inicia sesión en tu app y Keycloak le devuelve un código de autorización, tu app necesita intercambiar ese código por un token JWT. Para hacerlo, tu app llama al endpoint de tokens de Keycloak enviando el código, su Client ID y su Client Secret. Keycloak comprueba que el secret coincide con el que tiene guardado para ese cliente, y solo entonces devuelve el token.
Es básicamente una forma de que Keycloak verifique que la petición viene realmente de tu aplicación y no de alguien que interceptó el código de autorización. Sin el secret correcto, Keycloak rechaza la petición con el error "Invalid client credentials" que viste antes.
Cada cliente tiene su propio secret independiente. Si lo cambias en Keycloak, tienes que actualizarlo también en el app.py correspondiente, porque si no coinciden, la app no podrá obtener tokens.

![Imágenes](Images/27.png)

Ahora crearemos la aplicación Portal para los usuarios, en este caso voy a crear con python algo superbásico solo para comrpobar que todo funciona y haré lo mismo con la aplicación de tickets y de admin:

![Imágenes](Images/17.png)

Ahora modificamos el docker-compose.yml y añadimos los dockerfiles a los directorios de las apps:

![Imágenes](Images/18.png)

Ahora visitaremos cada una de las apps que hemos creado:

Portal

![Imágenes](Images/19.png)

Tickets

![Imágenes](Images/20.png)

Admin

![Imágenes](Images/21.png)

Ahora accederemos como cada uno de los usuarios designados para cada rol:

Portal

![Imágenes](Images/24.png)

Tickets

![Imágenes](Images/23.png)

Admin

![Imágenes](Images/25.png)

Ahora vamos a probar a acceder al panel de administración desde un usuario con otro rol:

![Imágenes](Images/26.png)








