# Justicia para Margarita

Sitio estático (HTML generado, subido por rsync). Sin base de datos.

- Contenido: `/var/www/justiciaparamargarita/www`
- Prod: `https://justiciaparamargarita.ar` (`www.` redirige al apex)

El VirtualHost está en `gateway/sites/justiciaparamargarita.conf`.

## Primera instalación en el VPS

```bash
mkdir -p /var/www/justiciaparamargarita/{www,logs}
sudo cp /var/www/docker/systemd/docker-justiciaparamargarita.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-justiciaparamargarita.service
# El gateway necesita el volumen de logs nuevo: recrear, no alcanza con graceful
docker exec shared-gateway httpd -t
sudo systemctl restart docker-gateway.service
```

mod_md pide el certificado al arrancar; cuando el log del gateway diga
"changes will be activated on next (graceful) server restart":

```bash
docker exec shared-gateway apachectl graceful
```

## Deploy

```bash
rsync -avz --delete _site/ ubuntu@VPS:/var/www/justiciaparamargarita/www/
```
