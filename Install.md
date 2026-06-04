# Instalar Docker en Ubuntu 24.04

Esta guía asume un VPS recién instalado con Ubuntu 24.04 y acceso a un usuario con permisos de `sudo`.

## 1. Actualizar el sistema

```bash
sudo apt update
sudo apt upgrade -y
```

## 2. Instalar dependencias necesarias

```bash
sudo apt install -y ca-certificates curl gnupg
```

## 3. Eliminar paquetes viejos de Docker si existen

```bash
sudo apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc
```

## 4. Crear el directorio para la clave GPG

```bash
sudo install -m 0755 -d /etc/apt/keyrings
```

## 5. Descargar la clave oficial de Docker

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

## 6. Agregar el repositorio oficial

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

## 7. Instalar Docker Engine y herramientas

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## 8. Verificar que Docker quedó instalado

```bash
sudo systemctl status docker
sudo docker version
sudo docker run hello-world
```

## 9. Opcional: usar Docker sin `sudo`

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Si estás conectado por SSH, a veces conviene cerrar sesión y volver a entrar para que el grupo aplique correctamente.

## 10. Comandos útiles de comprobación

```bash
docker compose version
docker ps
docker info
```

## 11. Crear redes Docker externas

Estas redes son compartidas entre proyectos y deben existir antes de levantar cualquier servicio:

```bash
docker network create shared_services
docker network create projects_public
```

- `shared_services` — conecta los contenedores de app con servicios compartidos (MySQL, Redis, etc.)
- `projects_public` — conecta los contenedores con el reverse proxy (Apache)

## Notas

- `docker compose` es el comando actual. No hace falta instalar `docker-compose` aparte en Ubuntu 24.04 si ya instalaste el plugin oficial.
- Si el firewall está activo, Docker puede modificar reglas de red automáticamente. Conviene revisar esto si vas a publicar puertos.
- En un entorno productivo, después de instalar Docker suele ser buena idea reiniciar el VPS si también se aplicaron actualizaciones del kernel.
