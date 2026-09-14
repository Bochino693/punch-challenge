#!/bin/sh
# ARDUINO DE MENTIRA, PROTOCOLO DE VERDADE.
#
# Fala exatamente as mesmas linhas que tools/ponte_serial.ps1 e
# tools/ponte_serial.sh falam, sem precisar de porta COM nem de placa
# espetada. Com isto o teste exercita o percurso inteiro do lado do jogo
# -- subir o processo, ler numa thread, atravessar o cano, digerir o
# protocolo -- que de outro jeito so seria exercitado na bancada do
# operador, que e justamente onde nao da para descobrir um defeito.
#
# A porta "COMRUIM" recusa de proposito: e assim que o teste prova que o
# jogo desiste dela e passa para a proxima.
printf '#PONTE,V1,falso\n'
aberta=""
while IFS= read -r l; do
	l=$(printf '%s' "$l" | tr -d '\r')
	case "$l" in
		@LISTAR*) printf '#PORTAS,COMBOA,COMRUIM\n' ;;
		@ABRIR,*)
			alvo=${l#@ABRIR,}
			alvo=${alvo%%,*}
			if [ "$alvo" = "COMRUIM" ]; then
				printf '#FALHA,%s,acesso negado\n' "$alvo"
			else
				aberta="$alvo"
				printf '#ABERTA,%s\n' "$alvo"
				printf 'READY,PUNCH_MPU6050,V3\n'
			fi
			;;
		@FECHAR*)
			[ -n "$aberta" ] && printf '#FECHADA,%s\n' "$aberta"
			aberta=""
			;;
		@SAIR*) exit 0 ;;
		@*) printf '#ERRO,comando desconhecido\n' ;;
		PING) [ -n "$aberta" ] && printf 'PONG\n' ;;
		TEST) [ -n "$aberta" ] && printf 'BUTTON,START\n' ;;
		*) [ -n "$aberta" ] && printf 'ECO,%s\n' "$l" ;;
	esac
done
exit 0
