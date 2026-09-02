# bin/

Scripts operativos para correr **en el VPS**.

## Setup por proyecto

`setup-<proyecto>.sh` deja un proyecto listo para levantar: verifica lo que
necesita, crea directorios y redes, y levanta los contenedores.

```bash
./bin/setup-enforos.sh           # converge el stack (sin rebuild)
./bin/setup-enforos.sh --build   # además reconstruye las imágenes
```

Todos comparten un motor y se diferencian sólo por su archivo de configuración:

```
bin/
├── setup-<proyecto>.sh     # wrapper de 18 líneas: carga la config y el motor
├── projects/<proyecto>.conf # qué tiene de particular este proyecto
└── lib/setup-engine.sh     # el flujo, igual para todos
```

### Cómo corren

Los scripts trabajan en **dos fases**:

1. **Sólo lectura** — env completo, Docker accesible, servicios compartidos
   arriba, base de datos accesible, repos clonados, y lo que el proyecto
   declare. Si algo falla, corta ahí **sin haber modificado nada**, y muestra
   todos los problemas juntos en vez del primero.
2. **Modifica** — directorios, redes, `docker compose up`.

Se pueden correr de nuevo sin romper nada ni duplicar recursos. Ojo: **convergen,
no son idempotentes en sentido estricto**. Si cambió el `compose.yml` los
contenedores afectados se recrean (corte breve), y `--build` no reproduce la
imagen anterior porque los Dockerfile usan tags móviles (`php:8.4-fpm`) y
`apt`/`pecl`/`composer` sin versión fija. Por eso el rebuild es opt-in.

### Lo que no hacen, a propósito

- Editar `compose.yml` ni `gateway/sites/*.conf` — son cambios versionados.
- Crear bases de datos — necesita la contraseña de root.
- Crear registros DNS.
- Escribir los `.env` ni los `config.php` con secretos reales.

Todo eso lo **detectan** y te dan el comando exacto para resolverlo.

## Agregar un proyecto

Crear `bin/projects/<proyecto>.conf`:

```bash
PROJECT="miproyecto"
DATA_DIRS=(app img www logs)
WRITABLE_DIRS=(img)
SERVICES=(api app img www)
REPOS=("/var/www/miproyecto/api|git@github.com:miproyecto/api.git")
PLACEHOLDERS='^(DB_PASS|COMPOSER_AUTH)=[[:space:]]*$|CAMBIAR'
```

Y el wrapper `bin/setup-miproyecto.sh`:

```bash
#!/bin/bash
set -uo pipefail
DOCKER="${DOCKER:-/var/www/docker}"
source "${DOCKER}/bin/projects/miproyecto.conf"
source "${DOCKER}/bin/lib/setup-engine.sh"
```

Las variables que acepta la config están documentadas en la cabecera de
`lib/setup-engine.sh`. Las más usadas:

| Variable | Para qué |
|---|---|
| `DATA_DIRS` | directorios a crear bajo `ROOT` |
| `WRITABLE_DIRS` | los que `www-data` debe poder escribir (uploads) |
| `SERVICES` | servicios del compose a levantar (vacío = todos) |
| `REPOS` | `"ruta\|url"` de lo que tiene que estar clonado |
| `DB_SOURCE` | `env` (default), `config` (lee `config.php`) o `none` |
| `NEEDS_MYSQL` / `NEEDS_GATEWAY` | `0` si no depende de ese servicio |
| `SYSTEMD_UNITS` | units que deberían estar activas |
| `REQUIRED_FILES` | `"ruta\|explicación"` de archivos sin los que no arranca |
| `KEYPAIR_DIR` | directorio con `private.key`/`public.key` a verificar |

Para chequeos que no entran en ese molde, la config puede definir dos funciones:
`check_extra` (fase 1, sólo lectura) y `setup_extra` (fase 2). Ejemplos:
`ember.conf` valida el largo de `SMTP_PASS_KEY`, y `partidodelasoledad.conf`
detecta un `config.php` que quedó apuntando a `localhost`.

## Diagnóstico

`diagnose.sh` junta en una sola corrida el estado de todo el VPS: host (disco,
memoria), Docker (contenedores, reinicios, redes), y por proyecto el env, el
código desplegado, los directorios, la base de datos y el DNS.

```bash
./bin/diagnose.sh              # todos los proyectos
./bin/diagnose.sh enforos      # sólo uno
```

**Sólo lee.** No crea, no modifica, no levanta ni reinicia nada: se puede correr
en producción con el sitio andando.

**Los secretos no se imprimen nunca.** De cada uno reporta si está definido y
cuántos caracteres tiene, y marca los que quedaron con un placeholder. Así la
salida se puede pegar en un chat o un issue sin filtrar credenciales.

Es el complemento de los `setup-*.sh`: aquéllos verifican lo necesario para
levantar un proyecto, éste responde "qué está pasando" cuando algo ya está roto.

## Limpieza de disco

`cleanup.sh` libera lo que Docker y systemd acumulan solos. En un VPS con varios
proyectos lo que más crece, y por lejos, es el **build cache de Docker**: cada
build deja capas intermedias que nadie borra.

```bash
./bin/cleanup.sh              # simulación: dice qué liberaría, sin tocar nada
./bin/cleanup.sh --apply      # ejecuta
```

Limpia build cache, journal de systemd (lo deja en 200 MB), capas dangling y
volúmenes sin links. Además avisa —sin borrarlas— de las imágenes que ya no usa
ningún contenedor, y de si falta configurar la rotación de logs de Docker.

**Nunca toca volúmenes en uso.** En particular `mysql_mysql_data` y los del
mailserver, donde viven las bases y los mails. Por eso el script no usa
`docker system prune --volumes`, que sí se los llevaría puestos. Tampoco toca
`/var/www` ni reinicia contenedores: se puede correr con los sitios andando.

Para que el disco no se vuelva a llenar solo, conviene además dejar puestas dos
cosas que el script detecta pero no aplica (las dos son globales del host):
`SystemMaxUse=200M` en `/etc/systemd/journald.conf`, y la rotación de logs de
contenedor en `/etc/docker/daemon.json`.

## Otros scripts

| Script | Qué hace |
|---|---|
| `check-linkedcode-auth.sh` | chequeo profundo de auth con el stack ya arriba |
| `fix-linkedcode-auth.sh` | arregla los problemas más comunes que detecta el anterior |
| `restart-<proyecto>.sh` | `systemctl restart docker-<proyecto>.service` |
| `reload-<proyecto>.sh` | recarga sin reiniciar |
| `status-<proyecto>.sh` | estado de la unit |
