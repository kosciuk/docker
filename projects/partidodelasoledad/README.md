# Partido de la Soledad

Sitio con 4 subdominios:

| Subdominio | Servicio | Contenido | Deploy |
|---|---|---|---|
| `api.partidodelasoledad.com.ar` | `api` (php84-fpm) | API Slim (código + Composer vendor) | `git pull` / CI en el VPS |
| `app.partidodelasoledad.com.ar` | `app` (apache-static) | `dist/` de la SPA Vue | `rsync` |
| `img.partidodelasoledad.com.ar` | `img` (apache-static) | uploads (imágenes) | escrito por la API |
| `www.partidodelasoledad.com.ar` | `www` (apache-static) | versión estática SEO | `rsync` |

Archivos en el VPS:

- API: `/var/www/partidodelasoledad/api`
- App (dist): `/var/www/partidodelasoledad/app`
- Uploads: `/var/www/partidodelasoledad/img`
- Sitio estático SEO: `/var/www/partidodelasoledad/www`
- Logs: `/var/www/partidodelasoledad/logs`

El contenedor `api` también monta `/var/www/partidodelasoledad/img` (mismo path) para poder escribir los uploads que sirve el contenedor `img`. Los límites de `post_max_size` / `upload_max_filesize` están en `config/uploads.ini`.

Los VirtualHosts ya están definidos en `gateway/sites/partidodelasoledad.conf` — no hay que configurar nada más ahí.

---

## Levantar el proyecto

### Camino corto

```bash
/var/www/docker/bin/setup-partidodelasoledad.sh           # converge el stack
/var/www/docker/bin/setup-partidodelasoledad.sh --build   # además reconstruye las imágenes
```

Corre en dos fases. Primero chequea, sin tocar nada: env completo, Docker accesible, `shared-mysql` y `shared-gateway` arriba, base accesible con las credenciales del env, y la API clonada. Si algo falla, corta ahí sin haber modificado nada y muestra **todos** los problemas juntos. Recién después crea directorios, redes y levanta los contenedores.

No crea la base de datos ni el DNS. Para eso, seguir el camino largo.

### Camino largo

#### 1. Primera vez en el VPS

```bash
sudo mkdir -p /var/www/partidodelasoledad/{app,img,www,logs}
sudo chown ubuntu:ubuntu /var/www/partidodelasoledad/{app,img,www,logs}

# api se clona con git, no se crea vacío. app se llena con el rsync del deploy.
git clone git@github.com:partidodelasoledad/api.git /var/www/partidodelasoledad/api
sudo chown -R ubuntu:ubuntu /var/www/partidodelasoledad/api
```

```bash
cp /var/www/docker/projects/partidodelasoledad/env/web.env.example \
   /var/www/docker/projects/partidodelasoledad/env/web.env
```

Editar `env/web.env` con los valores reales (`JWT_SECRET`, `DB_USER`/`DB_PASS`, `COMPOSER_AUTH`).

#### 2. Redes (si no existen)

```bash
docker network create shared_services
docker network create projects_public
```

#### 3. Base de datos (primera vez)

```bash
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS pdls"

docker exec -i shared-mysql mysql -u root -pPASS -e "
  CREATE USER IF NOT EXISTS 'pdls_user'@'%' IDENTIFIED BY 'CAMBIAR_PASSWORD';
  GRANT ALL PRIVILEGES ON pdls.* TO 'pdls_user'@'%';
  FLUSH PRIVILEGES;
"
```

Usar esas credenciales en `env/web.env`.

#### 4. Gateway (si no está corriendo)

```bash
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

#### 5. El proyecto

```bash
docker compose --env-file /var/www/docker/projects/partidodelasoledad/env/web.env \
  -f /var/www/docker/projects/partidodelasoledad/compose/web.yml up -d --build
```

---

## Hosts locales (en tu máquina)

```text
IP_DEL_VPS partidodelasoledad.com.ar www.partidodelasoledad.com.ar api.partidodelasoledad.com.ar app.partidodelasoledad.com.ar img.partidodelasoledad.com.ar
```

---

## Systemd (arranque automático)

```bash
sudo cp /var/www/docker/systemd/docker-partidodelasoledad.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-partidodelasoledad.service
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente para los 5 nombres declarados en `MDomain` si:

- los registros DNS de `partidodelasoledad.com.ar`, `www`, `api`, `app` e `img` apuntan al VPS
- los puertos `80` y `443` están abiertos
- el gateway está corriendo

mod_md descarga el certificado en el primer arranque, pero Apache necesita un reinicio para activarlo:

```bash
sudo systemctl restart docker-gateway.service
```

---

## Deploy (con el stack ya levantado)

### API

```bash
cd /var/www/partidodelasoledad/api
git pull
docker exec partidodelasoledad-api composer install --no-dev
docker exec partidodelasoledad-api bin/migrate
```

### App (dist de Vue)

```bash
npm run build
rsync -avz --delete dist/ usuario@IP_DEL_VPS:/var/www/partidodelasoledad/app/
```

La SPA necesita fallback a `index.html` para el history mode del router. Como `AllowOverride All` ya está habilitado en la imagen `apache-static`, alcanza con un `.htaccess` dentro del `dist/`:

```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteRule ^ index.html [L]
```

### www (versión estática SEO)

```bash
rsync -avz --delete /ruta/local/al/sitio/ usuario@IP_DEL_VPS:/var/www/partidodelasoledad/www/
```

No hace falta reiniciar los contenedores — son bind mounts.
