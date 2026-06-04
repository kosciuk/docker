# Gran Hermano

Stack del proyecto `granhermano`.

## Código fuente usado

- Web PHP: `/var/www/granhermano/www`

## Dominios

- Dev: `http://granhermano.local`
- Prod: `https://granhermano.com.ar`
- `https://www.granhermano.com.ar` redirige a `https://granhermano.com.ar`

## Cómo funciona el routing

No hay que configurar VirtualHosts manualmente. El gateway Apache ya tiene el archivo
`/var/www/docker/gateway/sites/granhermano.conf` con los VirtualHost definidos:

- En desarrollo, `granhermano.local` hace proxy al contenedor `granhermano-web`.
- En producción, `granhermano.com.ar` hace lo mismo y Apache gestiona el SSL solo.

Lo único que hay que hacer es levantar el gateway y el contenedor del proyecto.

## Requisitos previos

```bash
# Redes compartidas (solo la primera vez)
docker network create shared_services
docker network create projects_public

# Gateway (si no está corriendo)
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

## Levantar el proyecto

```bash
cp /var/www/docker/projects/granhermano/env/web.env.example \
   /var/www/docker/projects/granhermano/env/web.env

# Editar web.env con las credenciales reales
nano /var/www/docker/projects/granhermano/env/web.env

docker compose \
  --env-file /var/www/docker/projects/granhermano/env/web.env \
  -f /var/www/docker/projects/granhermano/compose/web.yml \
  up -d --build
```

## Hosts locales (en tu máquina)

Agregar en `/etc/hosts`:

```text
IP_DEL_VPS granhermano.local
```

## Producción

Para `granhermano.com.ar`, Apache (`mod_md`) emite el certificado Let's Encrypt automáticamente si:

- el dominio apunta al VPS (registro A en el DNS)
- los puertos `80` y `443` están abiertos en el firewall
- el gateway está corriendo
