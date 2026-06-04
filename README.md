# Docker Infrastructure

Infraestructura Docker compartida para varios proyectos en un VPS.

## Estructura

```text
/var/www/docker
├── gateway/            # Proxy HTTPS compartido
├── images/             # Imágenes base reutilizables
├── projects/           # Stacks por proyecto
├── services/           # Servicios compartidos
├── systemd/            # Units para arranque automático y updates
├── Install.md          # Instalación de Docker en Ubuntu 24.04
└── README.md
```

## Idea general

- `services/` contiene servicios comunes, por ejemplo MySQL.
- `images/` contiene imágenes base reutilizables, por ejemplo Apache + PHP.
- `projects/` contiene la definición Docker de cada proyecto.
- `gateway/` publica dominios como `api.liberamerkato.local` o `app.enforos.local`.

## Tipos de proyecto soportados

Esta estructura ya contempla al menos dos patrones:

- Proyecto con subdominios separados, por ejemplo:
  - `liberamerkato.local`
  - `www.liberamerkato.local`
  - `api.liberamerkato.local`
  - `app.liberamerkato.local`
  - `img.liberamerkato.local`
- Sitio PHP clásico con dominio principal, por ejemplo:
  - `granhermano.local`
  - `granhermano.com.ar`

En ambos casos el HTTPS entra por `Apache` (httpd:2.4 + mod_md):

- `.local` usa HTTP en puerto 80
- dominios públicos usan certificados automáticos de Let's Encrypt vía `mod_md`
- si el sitio vive en el dominio principal, `www` redirige al canónico
- si el proyecto usa `api/app/img`, `www` puede servir el contenido estático público

## Primer despliegue en un VPS

Este repositorio **es** la infraestructura del VPS. Se clona en `/var/www/docker` en el servidor
y desde ahí se levanta todo. Los `.env.example` viven acá; los `.env` reales se crean en el servidor
y nunca se commitean.

### 1. Instalar Docker

Seguir la guía en [Install.md](/var/www/docker/Install.md).

### 2. Configurar acceso SSH al repositorio

Generar una clave SSH en el VPS para poder clonar el repo:

```bash
ssh-keygen -t ed25519 -C "vps@docker"
cat ~/.ssh/id_ed25519.pub
```

Copiar la clave pública y agregarla en GitHub → Settings → Deploy keys (o equivalente en GitLab).

Verificar acceso:

```bash
ssh -T git@github.com
```

### 3. Clonar el repositorio

```bash
sudo mkdir -p /var/www
sudo chown $USER:$USER /var/www

cd /var/www
git clone git@github.com:kosciuk/docker.git docker
```

Para actualizar cuando hay cambios:

```bash
cd /var/www/docker
git pull
```

## Configuración inicial

### 1. Crear redes compartidas

```bash
docker network create shared_services
docker network create projects_public
```

Si ya existen, Docker lo indicará y no pasa nada.

### 2. Crear archivos `.env`

```bash
cd /var/www/docker
```

Ejemplo para MySQL:

```bash
cp services/mysql/.env.example services/mysql/.env
```

Ejemplo para LiberaMerkato:

```bash
cp projects/liberamerkato/env/api.env.example projects/liberamerkato/env/api.env
```

Ejemplo para Gran Hermano:

```bash
cp projects/granhermano/env/web.env.example projects/granhermano/env/web.env
```

Después editar los `.env` reales con credenciales y secretos del servidor.

## Levantar servicios

### 1. MySQL compartido

```bash
docker compose --env-file services/mysql/.env -f services/mysql/compose.yml up -d
```

### 2. Gateway HTTPS compartido

```bash
docker compose -f gateway/compose.yml up -d
```

### 3. API de LiberaMerkato

```bash
docker compose \
  --env-file projects/liberamerkato/env/api.env \
  -f projects/liberamerkato/compose/api.yml \
  up -d --build
```

### 4. Sitio web de Gran Hermano

```bash
docker compose \
  --env-file projects/granhermano/env/web.env \
  -f projects/granhermano/compose/web.yml \
  up -d --build
```

## Actualizar en producción

Cuando hay cambios en este repo:

```bash
cd /var/www/docker
git pull
```

Luego volver a aplicar los stacks que hayan cambiado.

Ejemplos:

```bash
docker compose --env-file services/mysql/.env -f services/mysql/compose.yml up -d
docker compose -f gateway/compose.yml up -d
docker compose --env-file projects/liberamerkato/env/api.env -f projects/liberamerkato/compose/api.yml up -d --build
docker compose --env-file projects/granhermano/env/web.env -f projects/granhermano/compose/web.yml up -d --build
```

Si instalaste las unidades de `systemd`, también puedes actualizar reiniciando el servicio correspondiente:

```bash
sudo systemctl restart docker-liberamerkato.service
sudo systemctl restart docker-granhermano.service
sudo systemctl restart docker-gateway.service
```

## Secretos y credenciales

- No versionar `.env` reales.
- Sí versionar `.env.example`.
- Guardar contraseñas fuertes para MySQL, JWT y cualquier API key.
- Los `.env` reales quedan persistidos en el VPS y no deberían ser afectados por `git pull`.

## Dominios locales

Para desarrollo con dominios `.local`, agregar en tu máquina local algo así:

```text
IP_DEL_VPS liberamerkato.local
IP_DEL_VPS www.liberamerkato.local
IP_DEL_VPS api.liberamerkato.local
IP_DEL_VPS app.liberamerkato.local
IP_DEL_VPS img.liberamerkato.local
IP_DEL_VPS granhermano.local
```

Para nuevos proyectos se agregan más hosts del mismo modo:

```text
IP_DEL_VPS www.enforos.local
IP_DEL_VPS api.enforos.local
IP_DEL_VPS app.enforos.local
IP_DEL_VPS img.enforos.local
```

## Agregar un nuevo proyecto

1. Crear `projects/NOMBRE/`
2. Definir su compose y sus `.env.example`
3. Conectarlo a `projects_public`
4. Conectarlo a `shared_services` si usa servicios compartidos
5. Crear un archivo `gateway/sites/NOMBRE.conf`

## Comandos útiles

Ver contenedores:

```bash
docker ps
```

Ver logs del gateway:

```bash
docker logs -f shared-gateway
```

Ver logs de la API:

```bash
docker logs -f liberamerkato-api
```

Entrar al contenedor de la API:

```bash
docker exec -it liberamerkato-api bash
```

## Systemd

Hay units listas en [systemd/README.md](/var/www/docker/systemd/README.md) para:

- arranque automático al reiniciar el VPS
- reinicios ordenados por stack
- despliegues más prolijos después de `git pull`
