#!/bin/sh
# CONFERE SE O FIRMWARE COMPILA -- SEM A IDE DO ARDUINO.
#
# POR QUE ISTO EXISTE. Um sketch que nao compila nao e "as fitas nao
# acendem": e "o Arduino nao faz nada". Sem compilar nao ha upload, a
# placa fica com o firmware velho ou com nenhum, e START e CREDITO morrem
# junto -- e o motivo verdadeiro fica escondido atras de um sintoma que
# nao tem nada a ver com a causa. Foi exatamente o que aconteceu quando o
# `#include` da biblioteca das fitas entrou sem protecao.
#
# Os cabecalhos de `firmware_stub/` sao FALSOS: eles declaram a API do
# Arduino sem implementar nada. Nao servem para gerar o binario da placa;
# servem para o compilador ler o sketch inteiro e reclamar de erro de
# sintaxe, funcao sem declarar e tipo errado -- que e onde estao os
# defeitos que impedem a gravacao.
#
# Uso:  sh tools/conferir_firmware.sh
set -e
raiz=$(dirname "$0")/..
stub="$raiz/tools/firmware_stub"
sketch="$raiz/arduino/punch_sensor/punch_sensor.ino"
tmp=$(mktemp -d)
cp "$sketch" "$tmp/sketch.cpp"

# -Werror de proposito: um aviso que aparece toda vez que se grava a
# placa e um aviso que o operador aprende a ignorar -- e no meio deles vai
# o que importava. Aqui aviso e erro.
echo "--- sem a biblioteca das fitas (placa recem-instalada) ---"
g++ -fsyntax-only -Werror -Wall -Wno-cpp -I"$stub" -include "$stub/Arduino.h" -std=gnu++11 "$tmp/sketch.cpp"
echo "    compila."

echo "--- com a biblioteca das fitas ---"
g++ -fsyntax-only -Werror -Wall -Wno-cpp -I"$stub" -I"$stub/comlib" -include "$stub/Arduino.h" -std=gnu++11 "$tmp/sketch.cpp"
echo "    compila."

echo "--- o sketch e ASCII puro? ---"
if LC_ALL=C grep -qP '[^\x00-\x7F]' "$sketch"; then
  echo "    NAO: ha caractere acentuado. A IDE do Arduino no Windows abre"
  echo "    o arquivo como CP-1252 e o acento vira simbolo estranho."
  exit 1
fi
echo "    e ASCII puro."
rm -rf "$tmp"
echo "FIRMWARE_OK"
