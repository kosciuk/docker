# bin/

Scripts operativos para correr **en el VPS**.

## Converger un proyecto

`<proyecto>.sh` deja un proyecto listo y actualizado: en la misma corrida crea
lo que falte (clona el repo si no está, directorios, redes, contenedores) y
actualiza el código a lo último (`git pull`, `composer install`,
migraciones). Reemplaza a los viejos `setup-<x>.sh` + `deploy-<x>.sh`.

```bash
./bin/enforos.sh           # converge y actualiza (sin rebuild)
./bin/enforos.sh --build   # además reconstruye las imágenes
./bin/enforos.sh --dry-run # sólo muestra qué cambiaría
```

Todos comparten un motor y se diferencian sólo por su archivo de configuración:

```
bin/
├── <proyecto>.sh            # wrapper: carga la config y el motor
├── projects/<proyecto>.conf # qué tiene de particular este proyecto
└── lib/engine.sh            # el flujo, igual para todos
```

### Cómo corren

Los scripts trabajan en **dos fases**:

1. **Sólo lectura** — env completo, Docker accesible, servicios compartidos
   arriba, base de datos accesible, repos (working tree limpio, rama, acceso
   al remoto -- si falta clonar, sólo se anota), COMPOSER_AUTH si el
   contenedor ya corre, y lo que el proyecto declare. Si algo falla, corta ahí
   **sin haber modificado nada**, y muestra todos los problemas juntos en vez
   del primero.
2. **Modifica** — clona/actualiza repos, directorios, redes,
   `docker compose up`, y con el contenedor arriba: `composer install` +
   migraciones si el proyecto los usa, reinicio sólo si hubo cambios de
   código.

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

Y el wrapper `bin/miproyecto.sh`:

```bash
#!/bin/bash
set -uo pipefail
DOCKER="${DOCKER:-/var/www/docker}"
source "${DOCKER}/bin/projects/miproyecto.conf"
source "${DOCKER}/bin/lib/engine.sh"
```

Las variables que acepta la config están documentadas en la cabecera de
`lib/engine.sh`. Las más usadas:

| Variable | Para qué |
|---|---|
| `DATA_DIRS` | directorios a crear bajo `ROOT` |
| `WRITABLE_DIRS` | los que `www-data` debe poder escribir (uploads) |
| `SERVICES` | servicios del compose a levantar (vacío = todos) |
| `REPOS` | `"ruta\|url"` de lo que tiene que estar clonado (se clona si falta) |
| `DB_SOURCE` | `env` (default), `config` (lee `config.php`) o `none` |
| `NEEDS_MYSQL` / `NEEDS_GATEWAY` | `0` si no depende de ese servicio |
| `USES_COMPOSER` | `1` si corre `composer install` + migraciones en el contenedor |
| `MIGRATE_CONTAINER` | dónde correrlos (default: el primero de `CONTAINERS`) |
| `SYSTEMD_UNITS` | units que deberían estar activas |
| `REQUIRED_FILES` | `"ruta\|explicación"` de archivos sin los que no arranca |
| `KEYPAIR_DIR` | directorio con `private.key`/`public.key` a verificar |

Para chequeos que no entran en ese molde, la config puede definir dos funciones:
`check_extra` (fase 1, sólo lectura) y `converge_extra` (fase 2, al final).
Ejemplo: `ember.conf` valida el largo de `SMTP_PASS_KEY`.

## Diagnóstico

`diagnose.sh` junta en una sola corrida el estado de todo el VPS: host (disco,
memoria), Docker (contenedores, reinicios, redes), y por proyecto el env, el
código desplegado, los directorios, la base de datos y el DNS.

```bash
./bin/diagnose.sh              # todos los proyectos
./bin/diagnose.sh enforos      # sólo uno
./bin/diagnose.sh --help       # qué proyectos hay
```

Los nombres salen de `bin/projects/*.conf` y no siempre coinciden con el
directorio: `auth.linkedcode.com` se diagnostica como **`linkedcode-auth`**, y
`www.linkedcode.com` como **`linkedcode-www`** — comparten compose pero son
aplicaciones independientes. Un nombre que no existe corta con la lista de los
válidos.

**Sólo lee.** No crea, no modifica, no levanta ni reinicia nada: se puede correr
en producción con el sitio andando.

**Los secretos no se imprimen nunca.** De cada uno reporta si está definido y
cuántos caracteres tiene, y marca los que quedaron con un placeholder. Así la
salida se puede pegar en un chat o un issue sin filtrar credenciales.

Es el complemento de los `<proyecto>.sh`: aquéllos verifican lo necesario para
levantar y actualizar un proyecto, éste responde "qué está pasando" cuando
algo ya está roto.

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
