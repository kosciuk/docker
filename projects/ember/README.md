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

## Primera instalación en el VPS

### 1. Red compartida (si no existe)

```bash
docker network create shared_services
```

### 2. Env

```bash
cp /var/www/docker/projects/ember/env/web.env.example /var/www/docker/projects/ember/env/web.env
```

Completar `DB_USER` / `DB_PASS` (usuario de `shared-mysql`) y `SMTP_PASS_KEY` (clave usada
para cifrar los `smtp_pass` de cada proyecto en la tabla `projects`, ver `sql/schema.sql`).

### 3. Base de datos

```bash
docker exec -i shared-mysql mysql -u root -pPASS -e "CREATE DATABASE IF NOT EXISTS ember"
docker exec -i shared-mysql mysql -u root -pPASS ember < /var/www/linkedcode/ember.linkedcode.com/sql/schema.sql
```

### 4. Levantar el contenedor con systemd

```bash
sudo cp /var/www/docker/systemd/docker-ember.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-ember.service
```

### 5. Worker de la cola (cron cada 1 minuto)

```bash
sudo cp /var/www/docker/systemd/docker-ember-cron.service /etc/systemd/system/
sudo cp /var/www/docker/systemd/docker-ember-cron.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-ember-cron.timer
```

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
