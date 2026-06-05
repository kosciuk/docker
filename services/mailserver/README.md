# Mailserver

Servidor de correo compartido basado en [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver).

- SMTP: puerto 587 (submission, autenticado) / 465 (SMTPS)
- IMAP: puerto 993 (IMAPS)
- Recepción MX: puerto 25
- SSL: Let's Encrypt (certbot, montado desde `/etc/letsencrypt`)
- Antispam: Rspamd

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
