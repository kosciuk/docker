# Docker Infrastructure

Infraestructura Docker compartida para varios proyectos en un VPS Ubuntu 24.04.

Este repositorio **es** la infraestructura del VPS. Se clona en `/var/www/docker` en el servidor
y desde ahí se levanta todo. Los `.env.example` viven acá; los `.env` reales se crean en el servidor
y nunca se commitean.

```text
/var/www/docker
├── gateway/        # Proxy Apache compartido (SSL, reverse proxy)
├── images/         # Imágenes base reutilizables
├── projects/       # Stack Docker de cada proyecto
├── services/       # Servicios compartidos (MySQL, etc.)
├── systemd/        # Units para arranque automático
└── README.md
```

---

## 1. Instalar Docker

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg
sudo apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verificar
sudo docker run hello-world

# Usar Docker sin sudo
sudo usermod -aG docker $USER
newgrp docker
```

---

## 2. Clonar este repositorio

Generar una clave SSH en el VPS para acceder al repo privado:

```bash
ssh-keygen -t ed25519 -C "vps@docker"
cat ~/.ssh/id_ed25519.pub
```

Agregar la clave pública en GitHub → Settings → Deploy keys. Verificar:

```bash
ssh -T git@github.com
```

Clonar:

```bash
sudo mkdir -p /var/www
sudo chown $USER:$USER /var/www

cd /var/www
git clone git@github.com:kosciuk/docker.git docker
```

---

## 3. Crear redes compartidas

```bash
docker network create shared_services
docker network create projects_public
```

Si ya existen, Docker lo indica y no pasa nada.

---

## 4. Levantar MySQL

```bash
cd /var/www/docker
cp services/mysql/.env.example services/mysql/.env
nano services/mysql/.env   # poner contraseñas reales entre comillas si tienen caracteres especiales

docker compose --env-file services/mysql/.env -f services/mysql/compose.yml up -d
```

---

## 5. Levantar el gateway

```bash
docker compose -f gateway/compose.yml up -d
```

El gateway Apache gestiona SSL con Let's Encrypt automáticamente para dominios públicos.
Para dominios `.local` usa HTTP en puerto 80.

---

## 6. Levantar proyectos

Cada proyecto tiene su propio README con los pasos completos:

- [projects/granhermano/README.md](projects/granhermano/README.md)

---

## Actualizar en producción

```bash
cd /var/www/docker
git pull
```

Luego volver a levantar los stacks que hayan cambiado. Con systemd:

```bash
sudo systemctl restart docker-mysql.service
sudo systemctl restart docker-gateway.service
```

Ver: [systemd/README.md](systemd/README.md)

---

## Agregar un nuevo proyecto

1. Crear `projects/NOMBRE/` con su compose y `.env.example`
2. Conectarlo a `projects_public` (y a `shared_services` si usa MySQL)
3. Crear `gateway/sites/NOMBRE.conf` con los VirtualHost

---

## Recuperación desde cero

Si el VPS se reinicia o un contenedor falla y no arranca automáticamente:

```bash
# 1. Ver qué está corriendo
docker ps

# 2. Levantar servicios en orden
sudo systemctl start docker-mysql.service
sudo systemctl start docker-gateway.service
sudo systemctl start docker-granhermano.service
sudo systemctl start docker-zurdosanonimos.service

# 3. Si el gateway no descubre un contenedor que acaba de arrancar, recargar Apache
docker exec shared-gateway apachectl graceful

# 4. Verificar logs si algo no responde
docker logs shared-gateway --tail 30
docker logs CONTENEDOR --tail 30
```

> Si un proyecto se muestra caído pero el servicio arranca correctamente (`systemctl status` dice active),
> el problema suele ser que el gateway no reconectó el upstream. Alcanza con el `apachectl graceful`.

---

## Certificados SSL (mod_md / Let's Encrypt)

mod_md obtiene los certificados automáticamente, pero el proceso tiene varias etapas. Si el browser muestra certificado self-signed o error SSL, seguir este checklist en orden.

### 1. Verificar que el DNS apunta al VPS

```bash
dig +short auth.linkedcode.com
# debe devolver la IP del VPS
```

Si el DNS no resuelve todavía, mod_md no puede completar el challenge HTTP-01 y no va a emitir el cert.

### 2. Ver el estado en los logs del gateway

```bash
docker logs shared-gateway 2>&1 | grep -i "md\|acme\|cert\|DOMINIO" | tail -30
```

Mensajes clave:

| Mensaje | Significado |
|---|---|
| `certificate for domains ... has been setup` | Cert obtenido, falta reiniciar |
| `renewing certificate` | En proceso, esperar |
| `problem with ... (challenge)` | El DNS no resuelve o el puerto 80 está bloqueado |
| `Letting-Encrypt rate limit` | Demasiados intentos, esperar horas |

### 3. Si el log dice "has been setup" → reiniciar el gateway

```bash
sudo systemctl restart docker-gateway.service
```

Un `apachectl graceful` no es suficiente en todos los casos — el reinicio completo es más confiable.

### 4. Si el cert sigue siendo self-signed después del reinicio

mod_md guarda los certificados en un volumen Docker. Verificar que el volumen persiste entre reinicios:

```bash
docker volume ls | grep gateway
docker exec shared-gateway ls /usr/local/apache2/md/domains/
```

Si el directorio del dominio está vacío, mod_md todavía no completó el challenge. Esperar unos minutos y volver a revisar los logs.

### 5. Si el challenge falla repetidamente

Causas comunes:
- El puerto 80 no está abierto en el firewall del VPS (`ufw status`)
- El dominio tiene un CAA record que bloquea Let's Encrypt
- El dominio no tiene registro A apuntando al VPS aún (TTL pendiente)

### 6. Forzar renovación manual (último recurso)

```bash
# Eliminar el estado de mod_md para el dominio y reiniciar
docker exec shared-gateway rm -rf /usr/local/apache2/md/domains/DOMINIO
sudo systemctl restart docker-gateway.service
```

---

## Comandos útiles

```bash
docker ps                          # ver contenedores corriendo
docker logs -f shared-gateway      # logs del gateway
docker logs -f shared-mysql        # logs de MySQL
docker exec -it CONTENEDOR bash    # entrar a un contenedor
```

---

## Secretos y credenciales

- No versionar `.env` reales (están en `.gitignore`).
- Sí versionar `.env.example`.
- Contraseñas con caracteres especiales deben ir entre comillas dobles en el `.env`.
