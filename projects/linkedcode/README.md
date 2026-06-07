# Linkedcode

Proyecto paraguas para los subdominios de `linkedcode.com`.

| Subdominio | Contenedor | Tipo |
|---|---|---|
| `auth.linkedcode.com` | `linkedcode-auth` | PHP (OAuth server) |
| `www.linkedcode.com` | `linkedcode-www` | Estático (Vue compilado) |

- Código fuente auth: `/var/www/linkedcode/auth.linkedcode.com` → git@github.com:linkedcode/auth.linkedcode.com.git
- Código fuente www: `/var/www/linkedcode/www.linkedcode.com`
- Prod: `https://auth.linkedcode.com`, `https://www.linkedcode.com`
- `linkedcode.com` redirige a `www.linkedcode.com`

El VirtualHost y los certificados están en `gateway/sites/linkedcode.conf`.

---

## Primera vez en el VPS

```bash
# Auth
git clone git@github.com:linkedcode/auth.linkedcode.com.git /var/www/linkedcode/auth.linkedcode.com
cp /var/www/linkedcode/auth.linkedcode.com/.env.example /var/www/linkedcode/auth.linkedcode.com/.env
nano /var/www/linkedcode/auth.linkedcode.com/.env
composer install --no-dev -o --working-dir=/var/www/linkedcode/auth.linkedcode.com

# www (por ahora estático)
mkdir -p /var/www/linkedcode/www.linkedcode.com
# copiar el build de Vue o un index.html provisional
```

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
