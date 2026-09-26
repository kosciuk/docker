# Consultarte

Sitio con 4 subdominios:

| Subdominio | Servicio | Contenido | Deploy |
|---|---|---|---|
| `api.consultarte.com.ar` | `api` (php84-fpm) | API Slim (código + Composer vendor) | `git pull` / CI en el VPS |
| `app.consultarte.com.ar` | `app` (apache-static) | `dist/` de la SPA Vue | `rsync` |
| `img.consultarte.com.ar` | `img` (apache-static) | uploads (imágenes) | escrito por la API |
| `www.consultarte.com.ar` | `www` (apache-static) | versión estática SEO | `rsync` |

Archivos en el VPS:

- API: `/var/www/consultarte/api`
- App (dist): `/var/www/consultarte/app`
- Uploads: `/var/www/consultarte/img`
- Sitio estático SEO: `/var/www/consultarte/www`

El contenedor `api` también monta `/var/www/consultarte/img` (mismo path) para poder escribir los uploads que sirve el contenedor `img`.

Los VirtualHosts ya están definidos en `gateway/sites/consultarte.conf` — no hay que configurar nada más ahí.

---

## Primera vez en el VPS

```bash
sudo mkdir -p /var/www/consultarte/{app,img,www,logs}
sudo chown ubuntu:ubuntu /var/www/consultarte/app /var/www/consultarte/img /var/www/consultarte/www /var/www/consultarte/logs

# api se clona con git, no se crea vacío
git clone git@github-linkedcode:consultarte/api.git /var/www/consultarte/api
sudo chown -R ubuntu:ubuntu /var/www/consultarte/api
```

```bash
cp /var/www/docker/projects/consultarte/env/web.env.example /var/www/docker/projects/consultarte/env/web.env
```

Editar `env/web.env` con las credenciales reales (`DB_USER`/`DB_PASS`, `COMPOSER_AUTH`).

---

## Levantar el proyecto

### Camino corto

```bash
/var/www/docker/bin/consultarte.sh           # converge el stack
/var/www/docker/bin/consultarte.sh --build   # además reconstruye las imágenes
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
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS consultarte"

docker exec -i shared-mysql mysql -u root -pPASS -e "
  CREATE USER IF NOT EXISTS 'consultarte_user'@'%' IDENTIFIED BY 'CAMBIAR_PASSWORD';
  GRANT ALL PRIVILEGES ON consultarte.* TO 'consultarte_user'@'%';
  FLUSH PRIVILEGES;
"
```

Usar esas mismas credenciales (`DB_USER`/`DB_PASS`) en `env/web.env`.

#### Importar un schema/dump completo

```bash
docker exec -i shared-mysql mysql -u consultarte_user -pPASSWORD consultarte < dump.sql
```

O directo desde la máquina local, sin copiar el dump al VPS antes:

```bash
mysqldump -u user -p consultarte_local | ssh usuario@IP_DEL_VPS "docker exec -i shared-mysql mysql -u consultarte_user -pPASSWORD consultarte"
```

### 4. Gateway (si no está corriendo)

```bash
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

### 5. El proyecto

```bash
docker compose --env-file /var/www/docker/projects/consultarte/env/web.env \
  -f /var/www/docker/projects/consultarte/compose/web.yml up -d --build
```

---

## Hosts locales (en tu máquina)

```text
IP_DEL_VPS consultarte.com.ar www.consultarte.com.ar api.consultarte.com.ar app.consultarte.com.ar img.consultarte.com.ar
```

---

## Systemd (arranque automático)

```bash
sudo cp /var/www/docker/systemd/docker-consultarte.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-consultarte.service
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente para los 5 nombres declarados en `MDomain` si:

- los registros DNS de `consultarte.com.ar`, `www`, `api`, `app` e `img` apuntan al VPS
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
cd /var/www/consultarte/api
git pull
docker exec consultarte-api composer install --no-dev
docker exec consultarte-api bin/migrate
```

### App (dist de Vue)

```bash
npm run build
rsync -avz --delete dist/ usuario@IP_DEL_VPS:/var/www/consultarte/app/
```

La SPA necesita fallback a `index.html` para el history mode del router. Como el `AllowOverride All` ya está habilitado en la imagen `apache-static`, alcanza con un `.htaccess` dentro del `dist/`:

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.html [L]
```

### www (versión estática SEO)

```bash
rsync -avz --delete /ruta/local/al/sitio-seo/ usuario@IP_DEL_VPS:/var/www/consultarte/www/
```

No hace falta reiniciar contenedores en ninguno de los dos casos — son bind mounts.
