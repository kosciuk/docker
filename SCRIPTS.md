# Scripts de bin/

Guía rápida de qué es cada familia de scripts y cuándo usar cada una.
Se corren en el VPS, en `/var/www/docker`.

## deploy-\<proyecto>.sh — el que se usa para actualizar

Es el flujo recomendado para subir cambios sin depender de rsync: hace
`git pull` del repo, `composer install`, corre migraciones pendientes y
reinicia el contenedor. Antes de tocar nada corre una fase de chequeos de
sólo lectura (contenedor corriendo, working tree limpio, rama correcta,
acceso al remoto, token de Composer válido) y si algo falla corta ahí, sin
modificar el sistema. El chequeo no es un paso aparte que haya que acordarse
de correr: ya está integrado como primer paso de este mismo comando.

Admite `--dry-run` para ver qué cambiaría sin aplicar nada.

Hoy existe para: `liberamerkato`, `enforos`, `ember`, `linkedcode-auth`.
Los demás proyectos (granhermano, zurdosanonimos, cooperativismoabierto,
impuestounico) todavía no lo tienen y siguen con los scripts viejos de
abajo.

## setup-\<proyecto>.sh — para armar el stack de cero o agregar algo nuevo

Converge el stack completo: valida el `.env`, crea directorios y redes que
falten, y levanta los contenedores (`docker compose up -d`). Se usa la
primera vez que se arma un proyecto, o después de agregar algo al compose
(una red, un volumen, un servicio nuevo) que todavía no existe en el VPS.
También corre sus propios chequeos antes de tocar nada. Acepta `--build`
para reconstruir las imágenes; sin esa opción no reconstruye nada.

## restart-\<proyecto>.sh — solo reiniciar

Reinicia el servicio systemd del proyecto, sin tocar código ni reconstruir
nada. Para cuando algo quedó colgado y alcanza con un reinicio.

## reload-\<proyecto>.sh — versión vieja de "actualizar"

Existen para granhermano, zurdosanonimos y linkedcode. Son anteriores a
`deploy-<proyecto>.sh` y no son consistentes entre sí: los de
granhermano/zurdosanonimos hacen `git pull` + restart completo del systemd,
el de linkedcode hace un `apache2ctl graceful` sin pull. No tienen la fase
de chequeos previos que sí tiene `deploy-*.sh`. Se mantienen porque esos
proyectos todavía no migraron al motor nuevo.

## status-\<proyecto>.sh — solo mirar

No modifica nada, muestra el estado del servicio o de los contenedores.

## Otros

`diagnose.sh`, `errors.sh` y `check-gateway.sh` en la raíz de `bin/` son de
sólo lectura y se pueden correr libremente en cualquier momento — son la
forma de mirar el estado general del VPS sin entrar proyecto por proyecto.
`cleanup.sh` libera disco; sin `--apply` sólo simula.
