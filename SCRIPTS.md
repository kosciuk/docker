# Scripts de bin/

Guía rápida de qué es cada familia de scripts y cuándo usar cada una.
Se corren en el VPS, en `/var/www/docker`.

## \<proyecto>.sh — el que se usa siempre: arma o actualiza

Es un único comando idempotente que reemplaza a los viejos `setup-<x>.sh` y
`deploy-<x>.sh`: en la misma corrida crea lo que falte (clona el repo si no
está, crea directorios y redes, levanta los contenedores) Y actualiza el
código a lo último (`git pull`, `composer install`, migraciones, reinicio si
hubo cambios). No hay un paso separado de "primera vez": si el proyecto nunca
se levantó, esta misma corrida clona el repo y arma todo; si ya está al día,
el `git pull` simplemente no hace nada.

Antes de tocar nada corre una fase de chequeos de sólo lectura (env, Docker,
servicios compartidos, working tree limpio, rama correcta, acceso al remoto,
base de datos, y si el contenedor ya está corriendo, también el token
COMPOSER_AUTH) y si algo falla corta ahí, sin modificar el sistema. El
chequeo no es un paso aparte que haya que acordarse de correr: ya está
integrado como primer paso de este mismo comando.

Admite `--build` para reconstruir las imágenes (sin esa opción no reconstruye
nada) y `--dry-run` para ver qué cambiaría sin aplicar nada.

La lógica común está en `bin/lib/engine.sh`; lo propio de cada proyecto, en
`bin/projects/<x>.conf`.

Hoy existe para: `cooperativismoabierto`, `ember`, `enforos`, `impuestounico`,
`liberamerkato`, `linkedcode-auth`, `linkedcode-www`, `perdidosyencontrados`.

Los demás proyectos (`granhermano`, `zurdosanonimos`) todavía no migraron y
siguen con los scripts viejos de abajo (`reload-*.sh`, `restart-*.sh`,
`status-*.sh`).

## check-\<proyecto>.sh — chequeo profundo, sólo lectura

Sólo existe para los proyectos que ya lo tenían: hoy, `linkedcode-auth`
(`check-linkedcode-auth.sh`). Verifica cosas que el `<proyecto>.sh` no cubre
porque son específicas de esa app (mod_remoteip, cookies de sesión, permisos
de las claves OAuth). No modifica nada. Se puede correr en cualquier momento,
antes o después de converger.

No se inventaron checks nuevos para los proyectos que no los tenían.

## projects/\<x>.conf — la config de cada proyecto

Declara las variables que `bin/lib/engine.sh` necesita para ese proyecto en
particular (PROJECT, ROOT, COMPOSE, ENV_FILE, REPOS, DATA_DIRS, SERVICES,
CONTAINERS, USES_COMPOSER, etc.) y, si hace falta, los hooks `check_extra`
(chequeos propios, fase de sólo lectura) y `converge_extra` (pasos propios,
fase que modifica). Es el mismo `.conf` que usa tanto el wrapper `<x>.sh`
como, indirectamente, cualquier chequeo que lo necesite.

## restart-\<proyecto>.sh — solo reiniciar

Reinicia el servicio systemd del proyecto, sin tocar código ni reconstruir
nada. Para cuando algo quedó colgado y alcanza con un reinicio. Siguen
existiendo para `granhermano` y `zurdosanonimos`, que todavía no migraron al
motor nuevo.

## reload-\<proyecto>.sh — versión vieja de "actualizar"

Existen para `granhermano`, `zurdosanonimos` y `linkedcode`. Son anteriores al
motor nuevo y no son consistentes entre sí: los de granhermano/zurdosanonimos
hacen `git pull` + restart completo del systemd, el de linkedcode hace un
`apache2ctl graceful` sin pull. No tienen la fase de chequeos previos que sí
tiene `<proyecto>.sh`. Se mantienen porque esos proyectos todavía no
migraron al motor nuevo.

## status-\<proyecto>.sh — solo mirar

No modifica nada, muestra el estado del servicio o de los contenedores.
Existen para `granhermano` y `zurdosanonimos`.

## Otros

`diagnose.sh`, `errors.sh` y `check-gateway.sh` en la raíz de `bin/` son de
sólo lectura y se pueden correr libremente en cualquier momento — son la
forma de mirar el estado general del VPS sin entrar proyecto por proyecto.
`cleanup.sh` libera disco; sin `--apply` sólo simula.
