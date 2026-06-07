#!/bin/bash
docker compose --env-file /var/www/docker/projects/linkedcode/env/web.env \
  -f /var/www/docker/projects/linkedcode/compose/web.yml \
  ps
