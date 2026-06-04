#!/bin/bash
set -e

echo "==> git pull zurdosanonimos/www"
git -C /var/www/zurdosanonimos/www pull

echo "==> restart docker-zurdosanonimos"
sudo systemctl restart docker-zurdosanonimos.service

echo "==> done"
