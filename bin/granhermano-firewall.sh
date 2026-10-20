#!/bin/bash
#
# Reglas de firewall (UFW) para bloquear granjas de scrapers y crawlers agresivos
# detectados en granhermano.com.ar (Oracle Cloud Singapur, DataForSEO, proxies).
#
#   ./bin/granhermano-firewall.sh              # simulación (muestra qué agregaría)
#   ./bin/granhermano-firewall.sh --apply      # ejecuta 'sudo ufw' para aplicar reglas
#   ./bin/granhermano-firewall.sh --status     # muestra estado actual de UFW
#   ./bin/granhermano-firewall.sh --delete     # elimina las reglas agregadas
#
# Contexto:
# En octubre 2026 se detectó un exceso masivo (>300k hits) de crawlers headless
# (AionBot, falsos Chrome/XXX.0.0.0) disparando Google Analytics desde Singapur
# y pools de proxies automatizados.
#
set -uo pipefail

APPLY=0
STATUS=0
DELETE=0

case "${1:-}" in
    --apply)
        APPLY=1
        ;;
    --status)
        STATUS=1
        ;;
    --delete)
        DELETE=1
        ;;
    "")
        ;;
    *)
        echo "Uso: $0 [--apply | --status | --delete]"
        exit 1
        ;;
esac

# Lista de subnets y motivo
# Formato: SUBNET|COMENTARIO
RULES=(
    "141.148.0.0/16|GH: Oracle Cloud SG (AionBot/Headless Chrome)"
    "132.226.0.0/16|GH: Oracle Cloud SG (AionBot/Headless Chrome)"
    "129.153.0.0/16|GH: Oracle Cloud SG (AionBot/Headless Chrome)"
    "161.153.0.0/16|GH: Oracle Cloud SG (AionBot/Headless Chrome)"
    "195.178.110.0/24|GH: DataForSEO scraper pool"
    "45.148.10.0/24|GH: Proxy scraper pool"
    "93.123.109.0/24|GH: Proxy scraper pool"
)

ok()   { echo "  [ ok ]   $1"; }
bad()  { echo "  [FALLA]  $1"; }
hmm()  { echo "  [ ojo ]  $1"; }
info() { echo "           $1"; }

if [ "$STATUS" = "1" ]; then
    echo "==> Estado actual de UFW:"
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw status numbered
    else
        bad "ufw no está instalado o no disponible en este entorno"
    fi
    exit 0
fi

echo "############ Firewall Gran Hermano (Bloqueo de Scrapers en UFW)"
echo

if [ "$DELETE" = "1" ]; then
    hmm "Modo eliminación de reglas"
    echo
    for entry in "${RULES[@]}"; do
        subnet="${entry%%|*}"
        desc="${entry##*|}"
        info "Eliminando: $subnet ($desc)"
        if command -v ufw >/dev/null 2>&1; then
            sudo ufw delete deny from "$subnet" to any || true
        else
            info "Comando: sudo ufw delete deny from $subnet to any"
        fi
    done
    exit 0
fi

if [ "$APPLY" = "1" ]; then
    hmm "Modo --apply: aplicando reglas en UFW..."
else
    info "Modo simulación. Nada se modifica. Usar --apply para ejecutar con sudo."
fi
echo

has_ufw=0
if command -v ufw >/dev/null 2>&1; then
    has_ufw=1
    CURRENT_UFW="$(sudo ufw status 2>/dev/null || true)"
fi

for entry in "${RULES[@]}"; do
    subnet="${entry%%|*}"
    desc="${entry##*|}"

    if [ "$has_ufw" = "1" ] && echo "$CURRENT_UFW" | grep -Fq "$subnet"; then
        ok "$subnet ya está bloqueada en UFW ($desc)"
        continue
    fi

    CMD="sudo ufw insert 1 deny from $subnet to any comment '$desc'"
    if [ "$APPLY" = "1" ]; then
        if [ "$has_ufw" = "1" ]; then
            info "Ejecutando: $CMD"
            eval "$CMD"
        else
            bad "No se encontró el comando 'ufw' en este sistema"
        fi
    else
        info "Simulación: $CMD"
    fi
done

echo
if [ "$APPLY" = "1" ]; then
    ok "Reglas aplicadas."
    echo "Para verificar el orden y comentarios: sudo ufw status numbered"
else
    info "Para aplicar en el VPS ejecutá:"
    info "  ./bin/granhermano-firewall.sh --apply"
fi

