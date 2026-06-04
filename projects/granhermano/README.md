# Gran Hermano

Sitio PHP clásico montado sobre el dominio principal.

- Código fuente: `/var/www/granhermano/www`
- Dev: `http://granhermano.local`
- Prod: `https://granhermano.com.ar` (`www` redirige al canónico)

El VirtualHost ya está definido en `gateway/sites/granhermano.conf` — no hay que configurar nada más.

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

### 4. El sitio

```bash
cd /var/www/docker
cp projects/granhermano/env/web.env.example projects/granhermano/env/web.env
nano projects/granhermano/env/web.env

docker compose \
  --env-file projects/granhermano/env/web.env \
  -f projects/granhermano/compose/web.yml \
  up -d --build
```

---

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS granhermano.local
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente si:

- el registro DNS apunta al VPS
- los puertos `80` y `443` están abiertos
- el gateway está corriendo
