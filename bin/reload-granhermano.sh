#!/bin/bash
set -e

echo "==> git pull granhermano/www"
git -C /var/www/granhermano/www pull

echo "==> restart docker-granhermano"
sudo systemctl restart docker-granhermano.service

echo "==> done"
