#!/bin/sh
# CONFERE O QUE PRECISA ESTAR NO EXECUTAVEL -- antes de exportar.
#
# POR QUE ISTO EXISTE. A conversa com o Arduino depende de uma extensao
# NATIVA (gdserial), um .dll que viaja junto do executavel. No computador
# de quem desenvolve ele esta sempre la, entao o defeito nunca aparece
# ali: ele aparece no PC novo, no notebook levado para a festa, e o
# sintoma e "nao funciona nada" -- START morto, CREDITO morto, sensor
# mudo. Horas procurando fio solto por causa de um arquivo.
#
# Uso:  sh tools/conferir_exportacao.sh
set -e
raiz=$(dirname "$0")/..
ext="$raiz/addons/gdserial/gdserial.gdextension"
falhou=0

echo "--- a extensao da serial esta declarada? ---"
[ -f "$ext" ] || { echo "FALTA $ext"; exit 1; }
echo "    sim."

echo "--- os binarios que ela aponta existem? ---"
# Cada linha `plataforma = "res://..."` da secao [libraries].
# O `_` PRECISA ESTAR NA CLASSE DE CARACTERES.
#
# Sem ele o padrao nao casa com `linux.debug.x86_64` nem com
# `windows.release.x86_64` -- e o binario que este verificador existe
# para conferir, o .dll do Windows de 64 bits, era justamente um dos que
# escapavam. Um verificador com um furo no meio e pior do que nenhum:
# ele da OK e a pessoa confia.
sed -n 's/^[a-z0-9._]* *= *"res:\/\/\(.*\)"$/\1/p' "$ext" | sort -u | while read -r alvo; do
  if [ -f "$raiz/$alvo" ]; then
    printf '    ok   %s\n' "$alvo"
  else
    printf '    FALTA %s\n' "$alvo"
    echo x >> /tmp/conferir_exportacao.falhou
  fi
done
if [ -f /tmp/conferir_exportacao.falhou ]; then
  rm -f /tmp/conferir_exportacao.falhou
  echo "Binario de extensao faltando: o executavel sai sem serial."
  exit 1
fi

echo "--- caminhos declarados que nao existem (doc, icones) ---"
if grep -q '^\[documentation\]' "$ext"; then
  echo "    HA uma secao [documentation]. Se a pasta nao existir, o Godot"
  echo "    reclama a cada abertura -- e erro que aparece sempre e erro"
  echo "    que se aprende a ignorar."
  exit 1
fi
echo "    nenhum."

echo "--- sobrou lixo VERSIONADO no pacote? ---"
# PERGUNTA AO GIT, E NAO AO DISCO.
#
# `~gdserial.dll` NASCE sozinho na maquina de quem desenvolve: no Windows
# nao da para sobrescrever uma DLL carregada, entao o editor do Godot
# copia a atual para um nome com `~` na frente. Olhar o disco reprovaria
# toda maquina com o projeto aberto -- e, pior, sugeriria apagar um
# arquivo que o Windows nao deixa apagar, que foi como um `git pull`
# entrou num laco infinito de "Unlink failed. Should I try again?".
#
# O que nao pode e ele estar VERSIONADO. E isso que se pergunta aqui.
lixo=$(cd "$raiz" && git ls-files 'addons/**/~*' '**/*.tmp' 2>/dev/null | head -5)
if [ -n "$lixo" ]; then
  echo "    LIXO VERSIONADO: $lixo"
  echo "    (no disco tudo bem: o Godot recria. So nao pode entrar no git.)"
  exit 1
fi
echo "    nao."

echo "EXPORTACAO_OK"
