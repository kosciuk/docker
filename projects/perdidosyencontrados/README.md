# PerdidosYEncontrados

Sitio con 4 subdominios:

| Subdominio | Servicio | Contenido | Deploy |
|---|---|---|---|
| `api.perdidosyencontrados.com.ar` | `api` (php84-fpm) | API Slim (código + Composer vendor) | `git pull` / CI en el VPS |
| `app.perdidosyencontrados.com.ar` | `app` (apache-static) | `dist/` de la SPA Vue | `rsync` |
| `img.perdidosyencontrados.com.ar` | `img` (apache-static) | uploads (imágenes) | escrito por la API |
| `www.perdidosyencontrados.com.ar` | `www` (apache-static) | versión estática SEO | `rsync` |

Archivos en el VPS:

- API: `/var/www/perdidosyencontrados/api`
- App (dist): `/var/www/perdidosyencontrados/app`
- Uploads: `/var/www/perdidosyencontrados/img`
- Sitio estático SEO: `/var/www/perdidosyencontrados/www`

El contenedor `api` también monta `/var/www/perdidosyencontrados/img` (mismo path) para poder escribir los uploads que sirve el contenedor `img`.

Los VirtualHosts ya están definidos en `gateway/sites/perdidosyencontrados.conf` — no hay que configurar nada más ahí.

---

## Primera vez en el VPS

```bash
sudo mkdir -p /var/www/perdidosyencontrados/{app,img,www,logs}
sudo chown ubuntu:ubuntu /var/www/perdidosyencontrados/app /var/www/perdidosyencontrados/img /var/www/perdidosyencontrados/www /var/www/perdidosyencontrados/logs

# api se clona con git, no se crea vacío
git clone git@github-linkedcode:perdidosyencontrados/api.git /var/www/perdidosyencontrados/api
sudo chown -R ubuntu:ubuntu /var/www/perdidosyencontrados/api
```

```bash
cp /var/www/docker/projects/perdidosyencontrados/env/web.env.example /var/www/docker/projects/perdidosyencontrados/env/web.env
```

Editar `env/web.env` con el `COMPOSER_AUTH` real.

La conexión a la base **no va en el env**: la API la lee de `api/config/config.php`, que no se versiona. En el VPS ese archivo tiene que apuntar a `shared-mysql`:

```php
'db' => [
    'host'     => 'shared-mysql',
    'dbname'   => 'perdidosyencontrados',
    'user'     => '...',
    'password' => '...',
],
```

---

## Levantar el proyecto

### Camino corto

```bash
/var/www/docker/bin/setup-perdidosyencontrados.sh           # converge el stack
/var/www/docker/bin/setup-perdidosyencontrados.sh --build   # además reconstruye las imágenes
```

Corre en dos fases. Primero chequea, sin tocar nada: env completo, Docker accesible, `shared-mysql` y `shared-gateway` arriba, base accesible con las credenciales del env, y API clonada. Si algo falla, corta ahí sin haber modificado nada y muestra **todos** los problemas juntos. Recién después crea directorios, redes y levanta los contenedores.

No crea la base de datos ni el DNS. Para eso, y para entender cada paso, seguir el camino largo.

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
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS perdidosyencontrados"

docker exec -i shared-mysql mysql -u root -pPASS -e "
  CREATE USER IF NOT EXISTS 'perdidosyencontrados_user'@'%' IDENTIFIED BY 'CAMBIAR_PASSWORD';
  GRANT ALL PRIVILEGES ON perdidosyencontrados.* TO 'perdidosyencontrados_user'@'%';
  FLUSH PRIVILEGES;
"
```

Usar esas mismas credenciales en `api/config/config.php` (ver arriba), no en el env.

#### Importar un schema/dump completo

```bash
docker exec -i shared-mysql mysql -u perdidosyencontrados_user -pPASSWORD perdidosyencontrados < dump.sql
```

O directo desde la máquina local, sin copiar el dump al VPS antes:

```bash
mysqldump -u user -p perdidosyencontrados_local | ssh usuario@IP_DEL_VPS "docker exec -i shared-mysql mysql -u perdidosyencontrados_user -pPASSWORD perdidosyencontrados"
```

### 4. Gateway (si no está corriendo)

```bash
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

### 5. El proyecto

```bash
docker compose --env-file /var/www/docker/projects/perdidosyencontrados/env/web.env \
  -f /var/www/docker/projects/perdidosyencontrados/compose/web.yml up -d --build
```

---

## Hosts locales (en tu máquina)

```text
IP_DEL_VPS perdidosyencontrados.com.ar www.perdidosyencontrados.com.ar api.perdidosyencontrados.com.ar app.perdidosyencontrados.com.ar img.perdidosyencontrados.com.ar
```

---

## Systemd (arranque automático)

```bash
sudo cp /var/www/docker/systemd/docker-perdidosyencontrados.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-perdidosyencontrados.service
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente para los 5 nombres declarados en `MDomain` si:

- los registros DNS de `perdidosyencontrados.com.ar`, `www`, `api`, `app` e `img` apuntan al VPS
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
cd /var/www/perdidosyencontrados/api
git pull
docker exec perdidosyencontrados-api composer install --no-dev
docker exec perdidosyencontrados-api bin/migrate
```

### App (dist de Vue)

```bash
npm run build
rsync -avz --delete dist/ usuario@IP_DEL_VPS:/var/www/perdidosyencontrados/app/
```

La SPA necesita fallback a `index.html` para el history mode del router. Como el `AllowOverride All` ya está habilitado en la imagen `apache-static`, alcanza con un `.htaccess` dentro del `dist/`:

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.html [L]
```

### www (versión estática SEO)

```bash
rsync -avz --delete /ruta/local/al/sitio-seo/ usuario@IP_DEL_VPS:/var/www/perdidosyencontrados/www/
```

No hace falta reiniciar contenedores en ninguno de los dos casos — son bind mounts.
