# Linkedcode

Proyecto paraguas para los subdominios de `linkedcode.com`.

| Subdominio | Contenedor | Tipo |
|---|---|---|
| `auth.linkedcode.com` | `linkedcode-auth` | PHP (OAuth server) |
| `www.linkedcode.com` | `linkedcode-www` | Estático (Vue compilado) |

- Código fuente auth: `/var/www/linkedcode/auth.linkedcode.com` → git@github-linkedcode:linkedcode/auth.git
- Código fuente www: `/var/www/linkedcode/www.linkedcode.com`
- Prod: `https://auth.linkedcode.com`, `https://www.linkedcode.com`
- `linkedcode.com` redirige a `www.linkedcode.com`

El VirtualHost y los certificados están en `gateway/sites/linkedcode.conf`.

---

## Primera vez en el VPS

```bash
# Auth
git clone git@github-linkedcode:linkedcode/auth.git /var/www/linkedcode/auth.linkedcode.com
# config/config.php no se versiona (ver sección "Configurar envío de mails" más abajo
# y ajustar también ahí los datos de conexión a shared-mysql)
# composer install lo corre solo el entrypoint de la imagen al levantar el contenedor

# www (por ahora estático)
mkdir -p /var/www/linkedcode/www.linkedcode.com
# copiar el build de Vue o un index.html provisional
```

---

## Base de datos (primera vez)

```bash
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS linkedcode_auth"

docker exec -i shared-mysql mysql -u root -pPASS -e "
  CREATE USER IF NOT EXISTS 'auth_user'@'%' IDENTIFIED BY 'CAMBIAR_PASSWORD';
  GRANT ALL PRIVILEGES ON linkedcode_auth.* TO 'auth_user'@'%';
  FLUSH PRIVILEGES;
"

docker exec -i shared-mysql mysql -u root -pPASS linkedcode_auth < /var/www/linkedcode/auth.linkedcode.com/migrations/000_initial_schema.sql
```

`auth_user` / la password elegida son los que van en `DB_USER` / `DB_PASS` de
`projects/linkedcode/env/web.env` y en `db_prod` de `config/config.php` (ver
sección de mails más abajo).

`000_initial_schema.sql` es el esquema completo (generado con Doctrine SchemaTool a
partir de `config/xml/` + la tabla `rate_limit`). Las migraciones `001` a `008` son
histórico incremental sobre bases ya existentes — en una instalación nueva **no** hay
que correrlas, alcanza con `000`.

## Claves RSA del servidor OAuth (primera vez)

`league/oauth2-server` necesita un keypair para firmar tokens. No hay script en el
proyecto que las genere — se crean a mano en el VPS:

```bash
openssl genrsa -out /var/www/linkedcode/auth.linkedcode.com/config/private.key 2048
openssl rsa -in /var/www/linkedcode/auth.linkedcode.com/config/private.key \
  -pubout -out /var/www/linkedcode/auth.linkedcode.com/config/public.key
chmod 644 /var/www/linkedcode/auth.linkedcode.com/config/private.key
```

`644` y no `600`: el archivo se bind-mountea al contenedor y lo lee el proceso
`www-data` de PHP-FPM, con un UID distinto al del usuario que generó el key en el
host — con `600` solo el dueño (el usuario del host) puede leerlo y PHP falla con
`FileCouldNotBeRead`.

---

## Configurar envío de mails (Ember)

`auth.linkedcode.com` envía mails (verificación de cuenta, reset de password, etc.) a
través de [Ember](/var/www/docker/projects/ember/README.md), la API interna de emails.
Requiere que el proyecto `ember` ya esté levantado en el VPS (misma red `shared_services`,
que `auth` ya tiene en `compose/web.yml`).

### 1. Generar la API key del proyecto en Ember

```bash
docker exec -it ember-app php bin/ember.php
# usar el comando de alta de proyecto/API key (ver README de Ember)
```

### 2. Cargar la key en `config/config.php` de auth

`/var/www/linkedcode/auth.linkedcode.com/config/config.php` está en `.gitignore` (es
config local por entorno, no se versiona). Ajustar el bloque `mail_api` para apuntar al
servicio Docker de Ember en vez del valor de desarrollo local:

```php
'mail_api' => [
    'url' => 'http://ember-app',
    'api_key' => '<API_KEY_GENERADA_EN_EL_PASO_1>',
    'verify_ssl' => false, // llamada interna por red Docker, sin TLS
],
```

De paso, revisar también el bloque `db_prod`/`db` de ese mismo archivo — debe apuntar a
`shared-mysql` (host, usuario y password reales), no a los valores de ejemplo.

---

## Deploy

### Auth (actualizar código PHP)

```bash
git -C /var/www/linkedcode/auth.linkedcode.com pull
composer install --no-dev -o --working-dir=/var/www/linkedcode/auth.linkedcode.com
```

No hace falta reiniciar el contenedor — el volumen bind sirve el código directamente.

### www (actualizar sitio estático)

Copiar el build de Vue a `/var/www/linkedcode/www.linkedcode.com`. No hace falta reiniciar.

---

## Dependencias privadas de composer (GitHub token)

`auth.linkedcode.com` depende de varios paquetes privados (`linkedcode/auth-middleware`,
`csrf-middleware`, `notenv`, `jwt-service`, `jwt-contracts`). El `composer install` que
corre el entrypoint de la imagen al levantar el contenedor necesita un token de GitHub
para poder bajarlos — sin esto falla con `404` al intentar descargar el zip.

1. Generar un Personal Access Token en GitHub (classic, scope `repo`, o fine-grained
   con acceso de lectura a los repos de la org `linkedcode`).
2. Completar `COMPOSER_AUTH` en `projects/linkedcode/env/web.env` (ver paso 4 más abajo):
   ```
   COMPOSER_AUTH={"github-oauth":{"github.com":"TOKEN_AQUI"}}
   ```
3. Si el contenedor ya había quedado con el vendor a medio instalar por el 404, limpiar
   el volumen de vendor y recrear:
   ```bash
   docker compose --env-file projects/linkedcode/env/web.env -f projects/linkedcode/compose/web.yml down auth
   docker volume rm linkedcode_linkedcode_auth_vendor
   docker compose --env-file projects/linkedcode/env/web.env -f projects/linkedcode/compose/web.yml up -d auth
   docker logs -f linkedcode-auth
   ```

---

## Levantar el proyecto

### 1. Redes (si no existen)

```bash
docker network create shared_services
docker network create projects_public
```

### 2. MySQL (si no está corriendo)

```bash
cd /var/www/docker
cp services/mysql/.env.example services/mysql/.env
nano services/mysql/.env

docker compose --env-file services/mysql/.env -f services/mysql/compose.yml up -d
```

### 3. Gateway (si no está corriendo)

```bash
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

### 4. El proyecto

```bash
cd /var/www/docker
cp projects/linkedcode/env/web.env.example projects/linkedcode/env/web.env
nano projects/linkedcode/env/web.env

docker compose \
  --env-file projects/linkedcode/env/web.env \
  -f projects/linkedcode/compose/web.yml \
  up -d --build
```

---

## Agregar un nuevo subdominio

1. Sumar el servicio en `projects/linkedcode/compose/web.yml`
2. Agregar el dominio al `MDomain` en `gateway/sites/linkedcode.conf`
3. Agregar el `VirtualHost` correspondiente en el mismo conf
4. Recargar el gateway: `sudo systemctl restart docker-gateway.service`

---

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS auth.linkedcode.com
IP_DEL_VPS www.linkedcode.com
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente para todos los dominios del `MDomain` si:

- los registros DNS apuntan al VPS
- los puertos `80` y `443` están abiertos
- el gateway está corriendo
