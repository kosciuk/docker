# Zurdos Anónimos

Sitio PHP clásico montado sobre el dominio principal. Sin base de datos.

- Código fuente: `/var/www/zurdosanonimos/www`
- Dev: `http://zurdosanonimos.local`
- Prod: `https://zurdosanonimos.com.ar`

El VirtualHost ya está definido en `gateway/sites/zurdosanonimos.conf` — no hay que configurar nada más.

---

## Levantar el proyecto

### 1. Redes (si no existen)

```bash
docker network create projects_public
```

### 2. Gateway (si no está corriendo)

```bash
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

### 3. El sitio

```bash
cd /var/www/docker
cp projects/zurdosanonimos/env/web.env.example projects/zurdosanonimos/env/web.env

docker compose \
  --env-file projects/zurdosanonimos/env/web.env \
  -f projects/zurdosanonimos/compose/web.yml \
  up -d --build
```

---

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS zurdosanonimos.local
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente si:

- el registro DNS apunta al VPS
- los puertos `80` y `443` están abiertos
- el gateway está corriendo

mod_md descarga el certificado en el primer arranque, pero Apache necesita un reinicio para activarlo:

```bash
sudo systemctl restart docker-gateway.service
```
