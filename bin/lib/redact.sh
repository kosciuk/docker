#!/bin/bash
#
# redact(): tacha lo sensible de una salida antes de imprimirla.
#
# Lo usan errors.sh y diagnose.sh. Se comparte para que no se desincronicen:
# un patrón nuevo (un formato de token que empieza a aparecer en los logs)
# tiene que sumarse en un solo lugar.
#
# No se ejecuta directo; se hace source desde el script que lo necesita.
#
# Tacha lo sensible ANTES de imprimir nada.
#
# Los logs de la app son deliberadamente completos: ProblemDetailsMiddleware
# limpia la RESPUESTA (scrub() reemplaza el detail de los 5xx), pero manda al
# logger el getMessage() crudo y la excepción entera con su trace. Eso es lo
# correcto para operar, y es exactamente lo que no se quiere pegar en un chat,
# un ticket o un mail.
#
# Va en su propia función y no dentro de normalize() a propósito: normalize()
# sólo corre en modo agrupado, y esto tiene que correr siempre — también con
# --all y en las líneas que se muestran de un contenedor caído.
#
# Es un filtro de mejor esfuerzo sobre texto libre, no una garantía: tacha las
# formas conocidas. Para publicar un log hacia afuera, leerlo antes.
redact() {
    sed -E \
        -e 's/(eyJ[A-Za-z0-9_-]{4,})\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[JWT]/g' \
        -e 's/\b(Bearer|Basic)[[:space:]]+[A-Za-z0-9._~+\/=-]{8,}/\1 [TOKEN]/gI' \
        -e 's/\b(gh[pousr]|github_pat)_[A-Za-z0-9_]{10,}/[GH_TOKEN]/g' \
        -e 's/\b(AKIA|ASIA)[A-Z0-9]{12,}/[AWS_KEY]/g' \
        -e 's/\b(sk|rk|pk)_(live|test)_[A-Za-z0-9]{10,}/[API_KEY]/g' \
        -e 's/(-----BEGIN[A-Z ]*PRIVATE KEY-----).*/\1 [REDACTED]/g' \
        -e 's/((pass(word|wd)?|secret|token|api[_-]?key|authorization|auth|pwd)["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?)[^"'"'"',;[:space:]]+/\1[REDACTED]/gI' \
        -e 's/(mysql|pgsql|postgres|postgresql|redis|amqp|mongodb):\/\/[^:@[:space:]]+:[^@[:space:]]+@/\1:\/\/[USER]:[REDACTED]@/g' \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[EMAIL]/g' \
        -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/[IP]/g' \
        -e 's/\b([0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}\b/[IPv6]/g' \
        -e 's/("(client_ip|ip|remote_addr|user_agent|referer)":)[[:space:]]*"[^"]*"/\1"[REDACTED]"/gI' \
        -e 's/, referer: [^[:space:]]+/, referer: [REDACTED]/g'
}
