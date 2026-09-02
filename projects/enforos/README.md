# Enforos

Sitio con 4 subdominios:

| Subdominio | Servicio | Contenido | Deploy |
|---|---|---|---|
| `api.enforos.net` | `api` (php84-fpm) | API Slim (código + Composer vendor) | `git pull` / CI en el VPS |
| `app.enforos.net` | `app` (apache-static) | `dist/` de la SPA Vue | `rsync` |
| `img.enforos.net` | `img` (apache-static) | uploads (imágenes) | escrito por la API |
| `www.enforos.net` | `www` (apache-static) | versión estática SEO | `rsync` |

Archivos en el VPS:

- API: `/var/www/enforos/api`
- App (dist): `/var/www/enforos/app`
- Uploads: `/var/www/enforos/img`
- Sitio estático SEO: `/var/www/enforos/www`
- Logs: `/var/www/enforos/logs`

El contenedor `api` también monta `/var/www/enforos/img` (mismo path) para poder escribir los uploads que sirve el contenedor `img`. Los límites de `post_max_size` / `upload_max_filesize` están en `config/uploads.ini`.

Los VirtualHosts ya están definidos en `gateway/sites/enforos.conf` — no hay que configurar nada más ahí.

---

## Primera vez en el VPS

```bash
sudo mkdir -p /var/www/enforos/{app,img,www,logs}
sudo chown ubuntu:ubuntu /var/www/enforos/{app,img,www,logs}

# api se clona con git, no se crea vacío
git clone git@github-linkedcode:enforos/api.git /var/www/enforos/api
sudo chown -R ubuntu:ubuntu /var/www/enforos/api
```

```bash
cp /var/www/docker/projects/enforos/env/web.env.example /var/www/docker/projects/enforos/env/web.env
```

Editar `env/web.env` con el `COMPOSER_AUTH` real.

La conexión a la base **no va en el env**: la API la lee de `api/config/config.php`, que no se versiona. En el VPS ese archivo tiene que apuntar a `shared-mysql`:

```php
'db' => [
    'host'     => 'shared-mysql',
    'dbname'   => 'enforos',
    'user'     => '...',
    'password' => '...',
],
```

---

## Levantar el proyecto

### Camino corto

```bash
/var/www/docker/bin/setup-enforos.sh           # converge el stack
/var/www/docker/bin/setup-enforos.sh --build   # además reconstruye las imágenes
```

Crea los directorios, verifica redes / MySQL / gateway y levanta el stack. Se puede correr de nuevo sin romper nada, así que también sirve para aplicar un subdominio nuevo sobre un stack ya andando.

Corre en dos fases. Primero chequea, sin tocar nada: env completo, Docker accesible, `shared-mysql` y `shared-gateway` arriba, base de datos accesible con las credenciales del env, y API clonada. Si algo de eso falla, corta ahí y no modificó nada — te muestra **todos** los problemas juntos, no el primero. Recién superada esa fase crea directorios, redes y levanta los contenedores.

Converge, pero no es idempotente en sentido estricto: si cambió el `compose.yml` los contenedores afectados se recrean (corte breve de la API), y `--build` no reproduce la imagen anterior porque los Dockerfile usan tags móviles y `apt`/`pecl`/`composer` sin versión fija. Por eso el rebuild es opt-in.

No crea la base de datos ni el DNS — para eso, y para entender qué hace cada paso, seguir el camino largo.

### Camino largo

#### 1. Redes (si no existen)

```bash
docker network create shared_services
docker network create projects_public
```

### 2. MySQL compartido (si no está corriendo)

```bash
docker compose --env-file /var/www/docker/services/mysql/.env -f /var/www/docker/services/mysql/compose.yml up -d
```

### 3. Base de datos (primera vez)

```bash
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS enforos"

docker exec -i shared-mysql mysql -u root -pPASS -e "
  CREATE USER IF NOT EXISTS 'enforos_user'@'%' IDENTIFIED BY 'CAMBIAR_PASSWORD';
  GRANT ALL PRIVILEGES ON enforos.* TO 'enforos_user'@'%';
  FLUSH PRIVILEGES;
"
```

Usar esas mismas credenciales en `api/config/config.php` (ver arriba), no en el env.

### 4. Gateway (si no está corriendo)

```bash
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

### 5. El proyecto

```bash
docker compose --env-file /var/www/docker/projects/enforos/env/web.env \
  -f /var/www/docker/projects/enforos/compose/web.yml up -d --build
```

---

## Hosts locales (en tu máquina)

```text
IP_DEL_VPS enforos.net www.enforos.net api.enforos.net app.enforos.net img.enforos.net
```

---

## Systemd (arranque automático)

```bash
sudo cp /var/www/docker/systemd/docker-enforos.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-enforos.service
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente para los 5 nombres declarados en `MDomain` si:

- los registros DNS de `enforos.net`, `www`, `api`, `app` e `img` apuntan al VPS
- los puertos `80` y `443` están abiertos
- el gateway está corriendo

mod_md descarga el certificado en el primer arranque, pero Apache necesita un reinicio para activarlo:

```bash
sudo systemctl restart docker-gateway.service
```

---

## Deploy (con el stack ya levantado)

### API (código versionado, no rsync)

```bash
ssh usuario@IP_DEL_VPS
cd /var/www/enforos/api
git pull
docker exec enforos-api composer install --no-dev
docker exec enforos-api bin/migrate
```

### App (dist de Vue)

```bash
npm run build
rsync -avz --delete dist/ usuario@IP_DEL_VPS:/var/www/enforos/app/
```

La SPA necesita fallback a `index.html` para el history mode del router. Como el `AllowOverride All` ya está habilitado en la imagen `apache-static`, alcanza con un `.htaccess` dentro del `dist/`:

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.html [L]
```

### www (versión estática SEO)

```bash
rsync -avz --delete /ruta/local/al/sitio/ usuario@IP_DEL_VPS:/var/www/enforos/www/
```

Hasta que haya contenido propio, `www.enforos.net` sirve lo que haya en ese directorio: si está vacío, devuelve un índice vacío en vez de redirigir a la app como hacía antes.

No hace falta reiniciar los contenedores — son bind mounts.
