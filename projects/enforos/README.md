# Enforos

Sitio con 3 subdominios:

| Subdominio | Servicio | Contenido | Deploy |
|---|---|---|---|
| `api.enforos.net` | `api` (php84-fpm) | API Slim (código + Composer vendor) | `git pull` / CI en el VPS |
| `app.enforos.net` | `app` (apache-static) | `dist/` de la SPA Vue | `rsync` |
| `www.enforos.net` | `www` (apache-static) | por ahora, solo redirige a `app.enforos.net` | ya configurado, no requiere deploy |

Archivos en el VPS:

- API: `/var/www/enforos/api`
- App (dist): `/var/www/enforos/app`
- Logs: `/var/www/enforos/logs`

El servicio `www` no sirve archivos: es un Apache que solo aplica un `RewriteRule` a `app.enforos.net`, definido en `config/www-redirect.conf`. El día que haya un sitio estático propio, se le agrega el volumen con los archivos igual que en `app`.

Los VirtualHosts ya están definidos en `gateway/sites/enforos.conf` — no hay que configurar nada más ahí.

---

## Primera vez en el VPS

```bash
sudo mkdir -p /var/www/enforos/{app,logs}
sudo chown ubuntu:ubuntu /var/www/enforos/app /var/www/enforos/logs

# api se clona con git, no se crea vacío
git clone git@github-linkedcode:enforos/api.git /var/www/enforos/api
sudo chown -R ubuntu:ubuntu /var/www/enforos/api
```

```bash
cp /var/www/docker/projects/enforos/env/web.env.example /var/www/docker/projects/enforos/env/web.env
```

Editar `env/web.env` con las credenciales reales (`DB_USER`/`DB_PASS`, `COMPOSER_AUTH`).

---

## Levantar el proyecto

### 1. Redes (si no existen)

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

Usar esas mismas credenciales (`DB_USER`/`DB_PASS`) en `env/web.env`.

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
IP_DEL_VPS enforos.net www.enforos.net api.enforos.net app.enforos.net
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

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente para los 4 nombres declarados en `MDomain` si:

- los registros DNS de `enforos.net`, `www`, `api` y `app` apuntan al VPS
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

No hace falta reiniciar el contenedor — es un bind mount.
