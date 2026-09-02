# LiberaMerkato

Marketplace con 4 subdominios:

| Subdominio | Servicio | Contenido | Deploy |
|---|---|---|---|
| `api.liberamerkato.com` | `api` (php84-fpm) | API Slim (código + Composer vendor) | `git pull` / CI en el VPS |
| `app.liberamerkato.com` | `app` (apache-static) | `dist/` de la SPA Vue | `rsync` |
| `img.liberamerkato.com` | `img` (apache-static) | uploads (imágenes) | escrito por la API |
| `www.liberamerkato.com` | `www` (apache-static) | versión estática SEO | `rsync` |

Archivos en el VPS:

- API: `/var/www/liberamerkato/api`
- App (dist): `/var/www/liberamerkato/app`
- Uploads: `/var/www/liberamerkato/img`
- Sitio estático SEO: `/var/www/liberamerkato/www`

El contenedor `api` también monta `/var/www/liberamerkato/img` (mismo path) para poder escribir los uploads que sirve el contenedor `img`.

Los VirtualHosts ya están definidos en `gateway/sites/liberamerkato.conf` — no hay que configurar nada más ahí.

---

## Primera vez en el VPS

```bash
sudo mkdir -p /var/www/liberamerkato/{app,img,www}
sudo chown ubuntu:ubuntu /var/www/liberamerkato/app /var/www/liberamerkato/img /var/www/liberamerkato/www

# api se clona con git, no se crea vacío
git clone git@github-linkedcode:liberamerkato/api.git /var/www/liberamerkato/api
sudo chown -R ubuntu:ubuntu /var/www/liberamerkato/api
```

```bash
cp /var/www/docker/projects/liberamerkato/env/web.env.example /var/www/docker/projects/liberamerkato/env/web.env
```

Editar `env/web.env` con las credenciales reales (`DB_USER`/`DB_PASS`, `COMPOSER_AUTH`).

---

## Levantar el proyecto

### Camino corto

```bash
/var/www/docker/bin/setup-liberamerkato.sh           # converge el stack
/var/www/docker/bin/setup-liberamerkato.sh --build   # además reconstruye las imágenes
```

Corre en dos fases. Primero chequea, sin tocar nada: env completo, Docker accesible, `shared-mysql` y `shared-gateway` arriba, base accesible con las credenciales del env, y API clonada. Si algo falla, corta ahí sin haber modificado nada y te muestra **todos** los problemas juntos. Recién después crea directorios, redes y levanta los contenedores.

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
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS liberamerkato"

docker exec -i shared-mysql mysql -u root -pPASS -e "
  CREATE USER IF NOT EXISTS 'liberamerkato_user'@'%' IDENTIFIED BY 'CAMBIAR_PASSWORD';
  GRANT ALL PRIVILEGES ON liberamerkato.* TO 'liberamerkato_user'@'%';
  FLUSH PRIVILEGES;
"
```

Usar esas mismas credenciales (`DB_USER`/`DB_PASS`) en `env/web.env`.

#### Importar un schema/dump completo

```bash
docker exec -i shared-mysql mysql -u liberamerkato_user -pPASSWORD liberamerkato < dump.sql
```

O directo desde la máquina local, sin copiar el dump al VPS antes:

```bash
mysqldump -u user -p liberamerkato_local | ssh usuario@IP_DEL_VPS "docker exec -i shared-mysql mysql -u liberamerkato_user -pPASSWORD liberamerkato"
```

### 4. Gateway (si no está corriendo)

```bash
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

### 5. El proyecto

```bash
docker compose --env-file /var/www/docker/projects/liberamerkato/env/web.env \
  -f /var/www/docker/projects/liberamerkato/compose/web.yml up -d --build
```

---

## Hosts locales (en tu máquina)

```text
IP_DEL_VPS liberamerkato.com www.liberamerkato.com api.liberamerkato.com app.liberamerkato.com img.liberamerkato.com
```

---

## Systemd (arranque automático)

```bash
sudo cp /var/www/docker/systemd/docker-liberamerkato.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-liberamerkato.service
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente para los 5 nombres declarados en `MDomain` si:

- los registros DNS de `liberamerkato.com`, `www`, `api`, `app` e `img` apuntan al VPS
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
cd /var/www/liberamerkato/api
git pull
docker exec liberamerkato-api composer install --no-dev
docker exec liberamerkato-api bin/migrate
```

### App (dist de Vue)

```bash
npm run build
rsync -avz --delete dist/ usuario@IP_DEL_VPS:/var/www/liberamerkato/app/
```

La SPA necesita fallback a `index.html` para el history mode del router. Como el `AllowOverride All` ya está habilitado en la imagen `apache-static`, alcanza con un `.htaccess` dentro del `dist/`:

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.html [L]
```

### www (versión estática SEO)

```bash
rsync -avz --delete /ruta/local/al/sitio-seo/ usuario@IP_DEL_VPS:/var/www/liberamerkato/www/
```

No hace falta reiniciar contenedores en ninguno de los dos casos — son bind mounts.
