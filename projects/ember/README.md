# Ember

API interna de envío de emails multi-proyecto. **No se expone al gateway ni tiene dominio
público** — vive únicamente en la red `shared_services`, la misma que usa `shared-mysql`
(y, si aplica, `shared-mailserver` como backend SMTP). Solo son clientes de esta API otros
contenedores de este mismo `docker compose` (ej. `granhermano-web`, `partidodelasoledad-app`),
que la llaman por nombre de servicio Docker: `http://ember-app/api/emails`.

La administración de proyectos/API keys y el procesamiento de la cola ya no pasan por HTTP:
se hacen con `bin/ember.php` dentro del contenedor (ver `README.md` del propio proyecto en
`/var/www/linkedcode/ember.linkedcode.com`).

---

## Camino corto

```bash
/var/www/docker/bin/setup-ember.sh           # converge el stack
/var/www/docker/bin/setup-ember.sh --build   # además reconstruye la imagen
```

Corre en dos fases. Primero chequea, sin tocar nada: env completo (incluido el largo de `SMTP_PASS_KEY`), Docker accesible, `shared-mysql` arriba, base accesible con las credenciales del env, y el repo clonado. Si algo falla, corta ahí sin haber modificado nada. Recién después crea la red y levanta el contenedor, y al final avisa si el timer del cron no está instalado o activo.

No clona el repo, no crea la base ni instala las units de systemd: las verifica y te dice qué falta. Para eso, seguir la instalación completa.

---

## Primera instalación en el VPS

### 1. Clonar el proyecto Ember

```bash
git clone git@github.com:linkedcode/ember.git /var/www/linkedcode/ember.linkedcode.com
```

### 2. Red compartida (si no existe)

```bash
docker network create shared_services
```

### 3. Env

```bash
cp /var/www/docker/projects/ember/env/web.env.example /var/www/docker/projects/ember/env/web.env
```

Completar `DB_USER` / `DB_PASS` (usuario de `shared-mysql`) y `SMTP_PASS_KEY` (clave usada
para cifrar los `smtp_pass` de cada proyecto en la tabla `projects`, ver `sql/schema.sql`).

### 4. Base de datos

```bash
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS ember"
docker exec -i shared-mysql mysql -u root -pPASS ember < /var/www/linkedcode/ember.linkedcode.com/sql/schema.sql
```

### 5. Levantar el contenedor con systemd

```bash
sudo cp /var/www/docker/systemd/docker-ember.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-ember.service
```

### 6. Worker de la cola (cron cada 1 minuto)

```bash
sudo cp /var/www/docker/systemd/docker-ember-cron.service /etc/systemd/system/
sudo cp /var/www/docker/systemd/docker-ember-cron.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-ember-cron.timer
```

Si se modifica alguna de las units, recargar:

```bash
sudo cp /var/www/docker/systemd/docker-ember-cron.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart docker-ember-cron.timer
```

El cron es la **red de seguridad**: los proyectos con `send_immediately = 1`
(recuperar contraseña, verificación) envían en el mismo request y no dependen
de él. El timer levanta lo que haya quedado pendiente si ese envío falla.

---

## Conectar otro proyecto a Ember

El proyecto que quiera enviar mail debe unirse a la red `shared_services` en su propio
`compose/web.yml`:

```yaml
services:
  app:
    networks:
      - projects_public
      - shared_services

networks:
  shared_services:
    external: true
    name: shared_services
```

Y llamar a `http://ember-app/api/emails` con el header `X-Api-Key` del proyecto (se
crea/consulta con `bin/ember.php` dentro del contenedor de Ember, no por HTTP).

---

## Verificar que todo está funcionando

```bash
docker ps | grep ember-app
docker logs -f ember-app

# Administración / prueba manual del worker
docker exec -it ember-app php bin/ember.php
docker exec -it ember-app php bin/ember.php emails:process-pending

# Estado del cron
systemctl status docker-ember-cron.timer
systemctl list-timers docker-ember-cron.timer
```
