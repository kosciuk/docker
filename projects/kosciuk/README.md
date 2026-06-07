# Kosciuk

Sitio estático montado sobre el dominio principal. Sin base de datos.

- Contenido: `/var/www/kosciuk/www`
- Dev: `http://kosciuk.local`
- Prod: `https://kosciuk.com.ar`

El VirtualHost está definido en `gateway/sites/kosciuk.conf`.

---

## Primera instalación en el VPS

### 1. Redes y gateway (si no existen)

```bash
docker network create projects_public
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

### 2. Directorio de contenido y env

```bash
mkdir -p /var/www/kosciuk/www
cp /var/www/docker/projects/kosciuk/env/web.env.example /var/www/docker/projects/kosciuk/env/web.env
```

### 3. Levantar el contenedor con systemd

```bash
sudo cp /var/www/docker/systemd/docker-kosciuk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-kosciuk.service
```

### 4. Recargar el gateway

```bash
docker exec shared-gateway apachectl graceful
```

---

## Deploy del sitio estático

Desde tu máquina local, una vez generado el HTML:

```bash
rsync -avz --delete _site/ user@vps:/var/www/kosciuk/www/
```

---

## Verificar que todo está funcionando

```bash
# El contenedor está corriendo
docker ps | grep kosciuk-web

# Logs del contenedor
docker logs kosciuk-web

# El gateway responde (reemplazar IP_DEL_VPS)
curl -I http://kosciuk.local

# En producción, verificar SSL y redirección
curl -I http://kosciuk.com.ar          # debe redirigir a https
curl -I https://kosciuk.com.ar         # debe devolver 200

# Si https devuelve certificado self-signed, mod_md puede estar procesando el cert.
# Verificar estado:
docker logs shared-gateway 2>&1 | grep -i kosciuk | tail -20
# Cuando aparece "has been setup and changes will be activated on next (graceful) server restart",
# ejecutar:
docker exec shared-gateway apachectl graceful

# Estado del servicio systemd
sudo systemctl status docker-kosciuk.service
```

---

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS kosciuk.local
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
