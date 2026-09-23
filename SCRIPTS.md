# Scripts de bin/

Se corren en el VPS, en `/var/www/docker`.

- **`<proyecto>.sh`** — arma o actualiza, en una sola corrida idempotente
  (clona si falta, crea dirs/redes, git pull, compose up, composer/migrate
  si aplica). Chequea antes de tocar nada; corta si algo falla. `--build`
  reconstruye imágenes, `--dry-run` sólo muestra qué haría.
- **`check-<proyecto>.sh`** — sólo lectura, chequeos específicos del
  proyecto. Sólo existe para `linkedcode-auth` por ahora.
- **`projects/<x>.conf`** — la config de cada proyecto (lo lee
  `<proyecto>.sh`).

Proyectos con este esquema: cooperativismoabierto, ember, enforos,
granhermano, impuestounico, liberamerkato, linkedcode-auth, linkedcode-www,
perdidosyencontrados, zurdosanonimos. Todos migrados — no queda ninguno con
el patrón viejo (`setup-*`/`deploy-*`/`reload-*`/`restart-*`/`status-*`).

Lo que no es de un proyecto puntual sino del VPS en general lleva el
prefijo `vps-`: `vps-diagnose.sh`, `vps-errors.sh`, `vps-check-gateway.sh`
(los tres, sólo lectura, corren libre) y `vps-cleanup.sh` (libera disco;
sin `--apply`, simula).
