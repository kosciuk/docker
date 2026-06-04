# Projects

Cada proyecto vive en su propia carpeta y comparte dos cosas:

- La red `projects_public` para tráfico web
- La red `shared_services` para servicios comunes como MySQL

Además, la infraestructura reutilizable queda separada por tipo:

- `services/` para stacks compartidos como MySQL
- `images/` para imágenes base reutilizables como Apache + PHP
- `gateway/` para el proxy común

## Estructura sugerida

```text
projects/
├── granhermano/
│   ├── compose/
│   │   └── web.yml
│   ├── env/
│   │   └── web.env.example
│   └── README.md
└── zurdosanonimos/
    ├── compose/
    │   └── web.yml
    ├── env/
    │   └── web.env.example
    └── README.md
```

Así cada proyecto mantiene su propio stack y el gateway solo resuelve dominios.
