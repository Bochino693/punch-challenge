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

# O SKETCH EXISTE E ESTA INTEIRO?
#
# Esta checagem parece boba e nao e: um arquivo VAZIO compila sem uma
# reclamacao, e este verificador chegou a dar FIRMWARE_OK para um sketch
# que um script meu tinha truncado a zero byte. "Compila" nao quer dizer
# "existe": sem `setup()` e `loop()` nao ha firmware nenhum.
for peca in "void setup" "void loop" "processarBotoes" "BUTTON,START" "BUTTON,CREDIT"; do
  if ! grep -q "$peca" "$sketch"; then
    echo "FALTA no sketch: $peca"
    exit 1
  fi
done

# E O LACO INFINITO DE NOVO NAO.
#
# O `while` sem fim por falta de sensor derrubava botoes, serial e fitas
# junto -- o defeito mais caro que este arquivo ja teve. Se alguem
# reintroduzir um, e aqui que se descobre.
#
# A busca e feita no codigo SEM COMENTARIOS: a explicacao do defeito
# antigo cita o `while` de proposito, e um verificador que reclama do
# proprio comentario que documenta o conserto e um verificador que se
# aprende a ignorar.
g++ -fpreprocessed -dD -E -P -I"$stub" -include "$stub/Arduino.h" \
    -std=gnu++11 "$tmp/sketch.cpp" > "$tmp/sem_comentario.cpp" 2>/dev/null || true
if grep -nE 'while *\( *(true|1) *\)' "$tmp/sem_comentario.cpp"; then
  echo "HA UM LACO INFINITO no codigo. A placa tem de sempre chegar ao loop()."
  exit 1
fi

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
