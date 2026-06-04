# MySQL

Servicio MySQL compartido para varios proyectos.

## Uso

```bash
cp /var/www/docker/services/mysql/.env.example /var/www/docker/services/mysql/.env
docker compose --env-file /var/www/docker/services/mysql/.env -f /var/www/docker/services/mysql/compose.yml up -d
```

## Red

Este servicio publica la red Docker `shared_services` para que los stacks de cada proyecto puedan conectarse por hostname `shared-mysql`.
