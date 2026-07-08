# Partido de la Soledad

Sitio estático servido por Apache.

- Archivos en el VPS: `/var/www/partidodelasoledad/www`
- Dev: `http://www.partidodelasoledad.local`
- Prod: `https://www.partidodelasoledad.com.ar` (el dominio sin `www` redirige siempre al `www`)

El VirtualHost ya está definido en `gateway/sites/partidodelasoledad.conf` — no hay que configurar nada más.

---

## Deploy (subir archivos al VPS)

```bash
rsync -avz --delete \
  /ruta/local/al/sitio/ \
  usuario@IP_DEL_VPS:/var/www/partidodelasoledad/www/
```

No hace falta reiniciar el contenedor — el volumen bind sirve los archivos directamente.

---

## Primera vez en el VPS

Crear el directorio destino:

```bash
sudo mkdir -p /var/www/partidodelasoledad/www
sudo chown ubuntu:ubuntu /var/www/partidodelasoledad/www
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
docker compose -f /var/www/docker/projects/partidodelasoledad/compose/web.yml up -d
```

---

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS www.partidodelasoledad.local
```

---

## Systemd (arranque automático)

Copiar la unit y habilitarla:

```bash
sudo cp /var/www/docker/systemd/docker-partidodelasoledad.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-partidodelasoledad.service
sudo systemctl start docker-partidodelasoledad.service
```

---

## Producción

Apache (`mod_md`) obtiene el certificado Let's Encrypt automáticamente si:

- el registro DNS apunta al VPS (tanto `partidodelasoledad.com.ar` como `www.partidodelasoledad.com.ar`)
- los puertos `80` y `443` están abiertos
- el gateway está corriendo

mod_md descarga el certificado en el primer arranque, pero Apache necesita un reinicio para activarlo:

```bash
sudo systemctl restart docker-gateway.service
```
