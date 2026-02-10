#!/bin/bash
# script para subir el core a la MiSTer rápidamente

IP_MISTER=$1
FILE=$2

if [ -z "$IP_MISTER" ] || [ -z "$FILE" ]; then
    echo "Uso: ./deploy.sh <ip_mister> <archivo.rbf>"
    exit 1
fi

scp "$FILE" "root@$IP_MISTER:/media/fat/_Arcade/PGM_test.rbf"
echo "Core enviado a la MiSTer. Cárgalo desde el menú de Arcade."
