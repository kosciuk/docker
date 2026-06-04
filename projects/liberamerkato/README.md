# LiberaMerkato

Stack del proyecto `liberamerkato`.

## Código fuente usado

- API: `/var/www/liberamerkato/api`
- Frontend: `/var/www/liberamerkato/app`
- Uploads: `/var/www/liberamerkato/img`

## Dominios

- `https://liberamerkato.local`
- `https://www.liberamerkato.local`
- `https://api.liberamerkato.local`
- `https://app.liberamerkato.local`
- `https://img.liberamerkato.local`

## Levantar la API

```bash
cp /var/www/docker/projects/liberamerkato/env/api.env.example /var/www/docker/projects/liberamerkato/env/api.env

docker compose \
  --env-file /var/www/docker/projects/liberamerkato/env/api.env \
  -f /var/www/docker/projects/liberamerkato/compose/api.yml \
  up -d --build
```

## Requisitos

- Red `shared_services` creada para MySQL
- Red `projects_public` creada para el gateway
- Gateway levantado desde `/var/www/docker/gateway/compose.yml`

## Hosts locales

```text
IP_DEL_SERVIDOR liberamerkato.local
IP_DEL_SERVIDOR www.liberamerkato.local
IP_DEL_SERVIDOR api.liberamerkato.local
IP_DEL_SERVIDOR app.liberamerkato.local
IP_DEL_SERVIDOR img.liberamerkato.local
```
