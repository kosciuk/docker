# Cooperativismo Abierto

Sitio estático servido por Apache.

- Archivos estáticos (local): `/var/www/cooperativismoabierto/html`
- Archivos en el VPS: `/var/www/cooperativismoabierto/www`
- Dev: `http://cooperativismoabierto.local`
- Prod: `https://cooperativismoabierto.com.ar` (`www` redirige al canónico)

El VirtualHost ya está definido en `gateway/sites/cooperativismoabierto.conf` — no hay que configurar nada más.

---

## Deploy (subir archivos al VPS)

```bash
rsync -avz --delete \
  /var/www/cooperativismoabierto/html/ \
  usuario@IP_DEL_VPS:/var/www/cooperativismoabierto/www/
```

No hace falta reiniciar el contenedor — el volumen bind sirve los archivos directamente.

---

## Primera vez en el VPS

Crear el directorio destino:

```bash
sudo mkdir -p /var/www/cooperativismoabierto/www
sudo chown ubuntu:ubuntu /var/www/cooperativismoabierto/www
```

Luego hacer el deploy con rsync desde la máquina local.

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
docker compose -f /var/www/docker/projects/cooperativismoabierto/compose/web.yml up -d
```

---

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS cooperativismoabierto.local
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
