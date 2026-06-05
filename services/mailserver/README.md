# Mailserver

Servidor de correo compartido basado en [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver).

- SMTP: puerto 587 (submission, autenticado) / 465 (SMTPS)
- IMAP: puerto 993 (IMAPS)
- Recepción MX: puerto 25
- SSL: Let's Encrypt (certbot, montado desde `/etc/letsencrypt`)
- Antispam: Rspamd

## Primer uso — puesta en marcha

### 1. Obtener certificado SSL

El puerto 25 debe estar libre (detener cualquier servicio que lo use). Certbot usará el modo standalone:

```bash
apt install certbot
certbot certonly --standalone -d mail.protesto.com.ar
```

El certificado queda en `/etc/letsencrypt/live/mail.protesto.com.ar/`. El contenedor lo monta como read-only desde `/etc/letsencrypt`.

**Renovación automática:** certbot instala un timer systemd que renueva automáticamente. Para verificar:

```bash
systemctl status certbot.timer
```

### 2. Crear el .env

```bash
cp /var/www/docker/services/mailserver/.env.example /var/www/docker/services/mailserver/.env
```

### 3. Levantar el contenedor

```bash
docker compose --env-file services/mailserver/.env -f services/mailserver/compose.yml up -d
```

### 4. Crear el primer usuario

```bash
docker exec shared-mailserver setup email add info@protesto.com.ar CONTRASEÑA
```

### 5. Generar DKIM y agregar al DNS

```bash
docker exec shared-mailserver setup config dkim domain protesto.com.ar
docker exec shared-mailserver cat /tmp/docker-mailserver/opendkim/keys/protesto.com.ar/mail.txt
```

El output es el valor del registro TXT que hay que crear en OVH como `mail._domainkey.protesto.com.ar`.

### 6. Instalar systemd

```bash
sudo cp /var/www/docker/systemd/docker-mailserver.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-mailserver
```

---

## Levantar

```bash
cp services/mailserver/.env.example services/mailserver/.env
docker compose --env-file services/mailserver/.env -f services/mailserver/compose.yml up -d
```

## Agregar usuario

```bash
docker exec shared-mailserver setup email add usuario@protesto.com.ar CONTRASEÑA
```

## Agregar alias

```bash
docker exec shared-mailserver setup alias add info@protesto.com.ar usuario@protesto.com.ar
```

## Generar DKIM (ejecutar una vez al inicio)

```bash
docker exec shared-mailserver setup config dkim domain protesto.com.ar
```

Luego leer la clave generada y agregarla como TXT en el DNS:

```bash
docker exec shared-mailserver cat /tmp/docker-mailserver/opendkim/keys/protesto.com.ar/mail.txt
```

## Agregar dominio adicional

1. Crear usuario en el nuevo dominio: `setup email add info@otrodominio.com PASS`
2. Generar DKIM: `setup config dkim domain otrodominio.com`
3. Agregar MX, SPF, DKIM y DMARC en el DNS del nuevo dominio

## Systemd

```bash
sudo cp systemd/docker-mailserver.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-mailserver
sudo systemctl start docker-mailserver
```

## Ver logs

```bash
docker logs -f shared-mailserver
```
