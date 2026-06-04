#!/bin/bash
set -e

echo "==> git pull liberamerkato/api"
git -C /var/www/liberamerkato/api pull

echo "==> restart docker-liberamerkato-api"
sudo systemctl restart docker-liberamerkato-api.service

echo "==> done"
