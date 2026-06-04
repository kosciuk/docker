# Systemd Units

Estas unidades permiten administrar los stacks Docker con `systemd`.

## Archivos incluidos

- `docker-mysql.service`
- `docker-gateway.service`
- `docker-granhermano.service`
- `docker-zurdosanonimos.service`

## Instalación en el VPS

Copiar los archivos a `/etc/systemd/system`:

```bash
sudo cp /var/www/docker/systemd/*.service /etc/systemd/system/
```

Recargar `systemd`:

```bash
sudo systemctl daemon-reload
```

Habilitar arranque automático:

```bash
sudo systemctl enable docker-mysql.service
sudo systemctl enable docker-granhermano.service
sudo systemctl enable docker-zurdosanonimos.service
sudo systemctl enable docker-gateway.service
```

Iniciar los servicios:

```bash
sudo systemctl start docker-mysql.service
sudo systemctl start docker-granhermano.service
sudo systemctl start docker-zurdosanonimos.service
sudo systemctl start docker-gateway.service
```

## Orden sugerido

- `docker-mysql.service`
- `docker-granhermano.service`
- `docker-zurdosanonimos.service`
- `docker-gateway.service`

El gateway queda al final para que los backends ya estén arriba cuando Caddy empiece a recibir tráfico.

## Actualizaciones

Después de hacer `git pull`:

```bash
sudo systemctl restart docker-granhermano.service
sudo systemctl restart docker-zurdosanonimos.service
sudo systemctl restart docker-gateway.service
```

Si cambió MySQL:

```bash
sudo systemctl restart docker-mysql.service
```

## Estado y logs

Ver estado:

```bash
sudo systemctl status docker-gateway.service
```

Ver logs:

```bash
journalctl -u docker-gateway.service -f
```
