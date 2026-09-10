#!/bin/sh
# CONFERE QUE NENHUM ARQUIVO DE TEXTO FOI CORROMPIDO NA COPIA.
#
# POR QUE ISTO EXISTE. Numa maquina o operador viu "CENTRAL TA%oCNICA" e
# "ConfiguraAAo" no lugar de "CENTRAL TECNICA" e "Configuracao". Nao era
# fonte, nem Godot, nem traducao: os arquivos .gd tinham sido lidos como
# Latin-1 e gravados como UTF-8 em algum momento -- um script de
# PowerShell com Get-Content/Set-Content sem -Encoding UTF8 faz
# exatamente isso, e o estrago fica GRAVADO no fonte.
#
# O estrago tem assinatura: onde havia "c-cedilha" passa a haver dois
# caracteres, o primeiro deles sempre um A-til ou um a-circunflexo. Essas
# duplas nao aparecem em portugues escrito direito.
#
# Uso:  sh tools/conferir_utf8.sh
set -e
raiz=$(dirname "$0")/..
cd "$raiz"
falhou=0

echo "--- todo arquivo de texto e UTF-8 valido? ---"
for f in $(git ls-files '*.gd' '*.md' '*.cfg' '*.godot' '*.gdshader' '*.txt'); do
  if ! iconv -f UTF-8 -t UTF-8 "$f" > /dev/null 2>&1; then
    echo "    NAO E UTF-8: $f"
    falhou=1
  fi
done
[ "$falhou" = "0" ] && echo "    todos ok."

echo "--- alguem foi codificado duas vezes? ---"
# As duplas que so aparecem quando UTF-8 foi lido como Latin-1 e gravado
# de novo. Um "A-til" seguido de simbolo nao existe em texto correto.
suspeitos=$(git ls-files '*.gd' '*.md' '*.cfg' '*.godot' '*.txt' \
  | xargs grep -l -e 'Ã§' -e 'Ã£' -e 'Ã©' -e 'Ãª' -e 'Ã­' -e 'Ã³' -e 'Ãµ' -e 'Ã¡' -e 'Ã¢' -e 'â€' -e 'Â·' 2>/dev/null | head -10 || true)
if [ -n "$suspeitos" ]; then
  echo "    CORROMPIDOS:"
  echo "$suspeitos" | sed 's/^/      /'
  echo "    Refaca a copia: git checkout -- <arquivo>, ou um clone limpo."
  exit 1
fi
echo "    nenhum."

[ "$falhou" = "0" ] || exit 1
echo "UTF8_OK"
