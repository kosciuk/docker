# Mailserver

Servidor de correo compartido basado en [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver).

- SMTP: puerto 587 (submission, autenticado) / 465 (SMTPS)
- IMAP: puerto 993 (IMAPS)
- Recepción MX: puerto 25
- SSL: Let's Encrypt (certbot, montado desde `/etc/letsencrypt`)
- Antispam: Rspamd (firma DKIM incluida)

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
```

El comando muestra en el output el valor exacto del registro TXT. Crearlo en OVH como `mail._domainkey.protesto.com.ar`.

### 6. Instalar systemd

```bash
sudo cp /var/www/docker/systemd/docker-mailserver.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable docker-mailserver
```

---

## Gestión de usuarios

**Listar cuentas existentes:**
```bash
docker exec shared-mailserver setup email list
```

**Agregar usuario:**
```bash
docker exec shared-mailserver setup email add usuario@protesto.com.ar CONTRASEÑA
```

**Cambiar contraseña:**
```bash
docker exec shared-mailserver setup email update usuario@protesto.com.ar NUEVA_CONTRASEÑA
```

**Eliminar usuario:**
```bash
docker exec shared-mailserver setup email del usuario@protesto.com.ar
```

## Alias y subdireccionamiento

**Agregar alias** (redirige a otra cuenta):
```bash
docker exec shared-mailserver setup alias add info@protesto.com.ar usuario@protesto.com.ar
```

**Listar alias:**
```bash
docker exec shared-mailserver setup alias list
```

**Subdireccionamiento con `+`** (funciona sin configuración extra):

docker-mailserver soporta de forma nativa el formato `usuario+etiqueta@dominio.com`. Todos los correos enviados a `info+trabajo@protesto.com.ar` o `info+newsletter@protesto.com.ar` llegan a la bandeja de `info@protesto.com.ar`. Útil para filtrar correos por origen en el cliente de correo.

## DKIM

**Generar claves para un dominio:**
```bash
docker exec shared-mailserver setup config dkim domain protesto.com.ar
```

**Agregar dominio adicional:**

1. Crear usuario: `docker exec shared-mailserver setup email add info@otrodominio.com PASS`
2. Generar DKIM: `docker exec shared-mailserver setup config dkim domain otrodominio.com`
3. Agregar MX, SPF, DKIM y DMARC en el DNS del nuevo dominio

## Catch-all para reply tracking (subdominio `replies.protesto.com.ar`)

Permite recibir correos en `[hash]@replies.protesto.com.ar` para rastrear respuestas de usuarios sin parsear el asunto. El `Reply-To` de cada mail saliente lleva el hash del reclamo.

### 1. DNS (en OVH)

Agregar registro MX para el subdominio:
```
replies.protesto.com.ar  MX  10  mail.protesto.com.ar
```

### 2. Agregar el dominio al mailserver

```bash
docker exec shared-mailserver setup email add replies@replies.protesto.com.ar CONTRASEÑA_SEGURA
docker exec shared-mailserver setup config dkim domain replies.protesto.com.ar
```

El comando DKIM mostrará el valor del registro TXT. Crearlo en OVH como `mail._domainkey.replies.protesto.com.ar`.

### 3. Configurar el catch-all

```bash
docker exec -it shared-mailserver bash
echo "@replies.protesto.com.ar  r@protesto.com.ar" >> /tmp/docker-mailserver/postfix-virtual.cf
postfix reload
```

A partir de ahí, cualquier correo a `*@replies.protesto.com.ar` llega a `yo@protesto.com.ar`.

### Uso en la app

Al enviar notificaciones al ciudadano, incluir el header:
```
Reply-To: <hash_del_reclamo>@replies.protesto.com.ar
```

Al recibir la respuesta, el hash se extrae directamente de la dirección `To:` del mail entrante — sin parsear el asunto.

---

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
