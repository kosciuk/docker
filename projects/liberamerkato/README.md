# LiberaMerkato

Proyecto con API, frontend SPA e imágenes en subdominios separados.

- API: `/var/www/liberamerkato/api`
- Frontend: `/var/www/liberamerkato/app/dist`
- Imágenes: `/var/www/liberamerkato/img`
- Dev: `http://api.liberamerkato.local`, `http://liberamerkato.local`, `http://img.liberamerkato.local`
- Prod: `https://api.liberamerkato.com`, `https://liberamerkato.com`, `https://img.liberamerkato.com`

El VirtualHost ya está definido en `gateway/sites/liberamerkato.conf` — no hay que configurar nada más.

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

### 4. La API

```bash
cd /var/www/docker
cp projects/liberamerkato/env/api.env.example projects/liberamerkato/env/api.env
nano projects/liberamerkato/env/api.env

docker compose \
  --env-file projects/liberamerkato/env/api.env \
  -f projects/liberamerkato/compose/api.yml \
  up -d --build
```

---

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS liberamerkato.local
IP_DEL_VPS www.liberamerkato.local
IP_DEL_VPS api.liberamerkato.local
IP_DEL_VPS app.liberamerkato.local
IP_DEL_VPS img.liberamerkato.local
```

---

## Producción

Apache (`mod_md`) obtiene los certificados Let's Encrypt automáticamente si:

- los registros DNS apuntan al VPS
- los puertos `80` y `443` están abiertos
- el gateway está corriendo
