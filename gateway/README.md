# Shared Gateway

Este stack publica HTTP/HTTPS para varios proyectos usando un único proxy reverso Apache.

## Estructura

```text
gateway/
├── compose.yml
├── httpd.conf
└── sites/
    ├── granhermano.conf
    └── liberamerkato.conf
```

## Idea

- Un solo contenedor `httpd:2.4` escucha en `80` y `443`.
- Cada proyecto agrega su propio archivo en `sites/`.
- Todos los servicios web se conectan a la red Docker compartida `projects_public`.
- `mod_md` gestiona los certificados Let's Encrypt automáticamente para dominios públicos.

## Convención HTTPS

- Para desarrollo con `.local`, usar HTTP en puerto 80.
- Para producción, declarar los dominios con `MDomain` en el `.conf` del proyecto — Apache obtiene y renueva el certificado solo.
- `www.DOMINIO` siempre redirige al dominio canónico sin `www`.

## Patrones recomendados

### 1. Proyecto con `api`, `app`, `img` y `www`

```apache
MDomain liberamerkato.com api.liberamerkato.com img.liberamerkato.com app.liberamerkato.com www.liberamerkato.com
```

### 2. Sitio directo sobre el dominio principal

```apache
MDomain granhermano.com.ar www.granhermano.com.ar
```

## Primer uso

```bash
docker network create projects_public
docker compose -f /var/www/docker/gateway/compose.yml up -d
```

## Agregar un nuevo proyecto

1. Crear su stack en `/var/www/docker/projects/NOMBRE/`
2. Conectar sus servicios HTTP a la red `projects_public`
3. Crear un archivo `gateway/sites/NOMBRE.conf` con los VirtualHost locales y de producción
