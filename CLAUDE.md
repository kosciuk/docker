# Docker Infrastructure — CLAUDE.md

## Propósito
Infraestructura Docker compartida para varios proyectos en un VPS Ubuntu 24.04.
Este repositorio **vive en `/var/www/docker`** en el servidor: los `compose.yml`,
los systemd y los `bin/*.sh` usan esa ruta, y así tiene que quedar escrita en
todo lo que se versione — aunque en local se esté editando vía `/data/www/docker`.

## Contexto de ejecución

Este repo se lee desde dos lugares y **el comportamiento cambia según cuál sea**.
Averiguarlo antes de correr nada de Docker:

```bash
docker info >/dev/null 2>&1 && echo "VPS" || echo "local"
```

### En el VPS (hay demonio de Docker)

Sí se pueden correr los comandos de este documento. Con dos límites:

- **Sólo lectura sin avisar.** `docker ps`, `docker logs`, `bin/diagnose.sh`,
  `bin/errors.sh`, `bin/check-gateway.sh` (sin `--fix`) se pueden correr libremente.
- **Todo lo que modifique se consulta primero**: `up`, `down`, `restart`, `systemctl`,
  los `bin/setup-*.sh`, `bin/cleanup.sh --apply`. Son siete proyectos en producción
  sobre servicios compartidos: reiniciar `shared-gateway` o `shared-mysql` los afecta
  a todos, y `docker compose down -v` sobre MySQL **borra los datos de todos**.

### En local (no hay demonio, o el repo es un espejo)

- No ejecutar comandos de servidor: no van a funcionar y confunden.
- Los comandos de este documento son **para que el usuario los corra en el VPS**.
- Limitarse a leer y editar archivos de configuración.

### Secretos

Estén donde estén, **no leer ni imprimir** los `.env` reales
(`projects/*/env/web.env`, `services/mysql/.env`), los `config/config.php` de las
apps ni los `private.key`. Si hace falta saber si una variable está definida,
verificar que exista la clave, no mostrar el valor.

Los `logs/` de cada proyecto sí se pueden leer, pero salen crudos: usar
`bin/errors.sh`, que los tacha (ver abajo). Un `grep` directo al `app.log` no.

## Estructura
```
/var/www/docker
├── gateway/        # Proxy Apache compartido (SSL via mod_md, reverse proxy)
├── images/         # Imágenes base (php84-apache)
├── projects/       # Stack Docker por proyecto (granhermano, zurdosanonimos, kosciuk)
├── services/       # Servicios compartidos (shared-mysql)
├── systemd/        # Units systemd para arranque automático
└── promps/         # Prompts de contexto por proyecto
```

## Servicios compartidos

### MySQL (`shared-mysql`)
- Imagen: `mysql:8.4`
- Container: `shared-mysql`
- Red: `shared_services`
- Compose: `services/mysql/compose.yml`
- Env: `services/mysql/.env` (no versionado)
- Levantar: `docker compose --env-file services/mysql/.env -f services/mysql/compose.yml up -d`
- Reiniciar: `sudo systemctl restart docker-mysql.service`
- **MySQL 8.4:** no soporta `--default-authentication-plugin` ni `--mysql-native-password=OFF` — removidas.

### Gateway (`shared-gateway`)
- Apache con mod_md (Let's Encrypt automático para dominios públicos)
- Compose: `gateway/compose.yml`
- Sites: `gateway/sites/*.conf`
- **Logs por proyecto:** cada vhost define `ErrorLog`/`CustomLog` en
  `/var/www/<proyecto>/logs/`. El compose monta ese directorio de cada
  proyecto; si se agrega un proyecto nuevo hay que sumar el volumen ahí y
  crear el directorio, o Apache no arranca (`AH02291`).
- Validar la config antes de reiniciar:
  `docker exec shared-gateway httpd -t`

## Redes Docker
- `shared_services` — servicios internos (MySQL)
- `projects_public` — proyectos expuestos al gateway

## Proyectos
| Proyecto | Compose | Systemd |
|---|---|---|
| granhermano | `projects/granhermano/compose/web.yml` | `docker-granhermano.service` |
| zurdosanonimos | `projects/zurdosanonimos/compose/web.yml` | `docker-zurdosanonimos.service` |
| kosciuk | `projects/kosciuk/compose/web.yml` | `docker-kosciuk.service` |
| cooperativismoabierto | `projects/cooperativismoabierto/compose/web.yml` | `docker-cooperativismoabierto.service` |
| partidodelasoledad | `projects/partidodelasoledad/compose/web.yml` | `docker-partidodelasoledad.service` |
| liberamerkato | `projects/liberamerkato/compose/web.yml` | `docker-liberamerkato.service` |
| enforos | `projects/enforos/compose/web.yml` | `docker-enforos.service` |

## Comandos frecuentes
```bash
./bin/diagnose.sh                            # radiografía del VPS (sólo lee)
./bin/errors.sh                              # errores recientes por sitio (sólo lee)
./bin/errors.sh enforos 2h                   # un proyecto, otra ventana
./bin/check-gateway.sh                       # gateway desalineado (sólo lee)
./bin/cleanup.sh                             # liberar disco (simulación)
./bin/cleanup.sh --apply                     # liberar disco (ejecuta)

docker ps                                    # ver contenedores
docker logs -f shared-mysql                  # logs MySQL
docker logs -f shared-gateway                # logs gateway
docker exec -it shared-mysql mysql -u root -p  # entrar a MySQL

# Borrar volumen MySQL y reinicializar (DESTRUYE DATOS)
docker compose --env-file services/mysql/.env -f services/mysql/compose.yml down -v
docker compose --env-file services/mysql/.env -f services/mysql/compose.yml up -d

# Importar dump en MySQL
docker exec -i shared-mysql mysql -u root -pPASS database < dump.sql
# o desde local:
mysqldump -u user -p db | ssh user@vps "docker exec -i shared-mysql mysql -u root -pPASS db"
```

## Secretos
- `.env` reales nunca se versionan (`.gitignore`)
- `.env.example` sí se versionan
- Contraseñas con caracteres especiales van entre comillas dobles en `.env`

## Logs y redactado

Los logs de la app son **deliberadamente completos**: `ProblemDetailsMiddleware`
limpia la *respuesta* HTTP (los 5xx salen con un detail genérico), pero manda al
logger el `getMessage()` crudo y la excepción entera con su trace. En `app.log`
hay SQL con valores, paths, mails e IPs.

Por eso `bin/errors.sh` y `bin/diagnose.sh` pasan su salida por `redact()`
(`bin/lib/redact.sh`), que tacha IPs, mails, JWTs, tokens (`Bearer`, GitHub, AWS,
Stripe), claves privadas, pares `password=`/`secret=`/`api_key=` y credenciales
embebidas en URLs de conexión. Esa salida se puede pegar en un chat o un ticket.

Es mejor esfuerzo sobre texto libre, no una garantía: tacha las formas conocidas.
Un `grep` directo al `app.log` **no pasa por el filtro** — leerlo antes de compartirlo.

Si aparece un formato de secreto nuevo en los logs, el patrón se agrega en
`bin/lib/redact.sh`, que es de donde lo toman los dos scripts.
