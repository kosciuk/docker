# Mailserver

Servidor de correo compartido basado en [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver).

- SMTP: puerto 587 (submission, autenticado) / 465 (SMTPS)
- IMAP: puerto 993 (IMAPS)
- Recepción MX: puerto 25
- SSL: Let's Encrypt (certbot, montado desde `/etc/letsencrypt`)
- Antispam: Rspamd

## Primer uso — puesta en marcha

### 1. Obtener certificado SSL

Como el puerto 80 está ocupado por el gateway, se usa el método DNS challenge via plugin de OVH. Esto también habilita la renovación automática.

**Instalar certbot y el plugin OVH:**
```bash
apt install certbot python3-certbot-dns-ovh
```

**Crear token en la API de OVH:**

Entrá a https://api.ovh.com/createToken/ con estos permisos y validez **Unlimited**:
- `GET /domain/zone/*`
- `PUT /domain/zone/*`
- `POST /domain/zone/*`
- `DELETE /domain/zone/*`

**Guardar las credenciales en el VPS:**
```bash
mkdir -p /etc/letsencrypt/ovh
nano /etc/letsencrypt/ovh/credentials.ini
```

Contenido:
```ini
dns_ovh_endpoint = ovh-ca
dns_ovh_application_key = TU_APP_KEY
dns_ovh_application_secret = TU_APP_SECRET
dns_ovh_consumer_key = TU_CONSUMER_KEY
```

```bash
chmod 600 /etc/letsencrypt/ovh/credentials.ini
```

**Emitir el certificado:**
```bash
certbot certonly --dns-ovh --dns-ovh-credentials /etc/letsencrypt/ovh/credentials.ini -d mail.protesto.com.ar
```

El certificado queda en `/etc/letsencrypt/live/mail.protesto.com.ar/`. El contenedor lo monta como read-only desde `/etc/letsencrypt`.

**Verificar renovación automática:**
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
