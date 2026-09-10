#!/bin/sh
# ======================================================================
#  PONTE SERIAL -- versao Linux/macOS. Mesmo protocolo do .ps1.
# ======================================================================
#
#  Irma do tools/ponte_serial.ps1: fala exatamente as mesmas linhas com o
#  jogo, para o codigo do Godot ser UM SO nos dois sistemas. La e
#  PowerShell porque o Windows ja vem com ele; aqui e `stty` + `cat`,
#  porque todo Unix ja vem com os dois.
#
#  A DIVISAO DE TRABALHO E DIFERENTE, E DE PROPOSITO.
#
#  No PowerShell um processo so cuida das duas direcoes, alternando sem
#  nunca bloquear. Aqui nao precisa dessa ginastica: o `cat` da porta roda
#  como processo separado e escreve DIRETO na saida que o jogo le, entao o
#  laco principal pode ficar tranquilamente parado esperando o proximo
#  comando do jogo. Uma direcao nunca segura a outra.
#
#  Uso manual:  sh tools/ponte_serial.sh [porta] [velocidade]
# ======================================================================

porta_pedida="$1"
baud="${2:-115200}"
[ -n "$baud" ] || baud=115200

leitor=""
aberta=""

fechar() {
	if [ -n "$leitor" ]; then
		kill "$leitor" 2>/dev/null
		wait "$leitor" 2>/dev/null
		leitor=""
	fi
	exec 3>&- 2>/dev/null || true
	if [ -n "$aberta" ] && [ "$1" = "avisar" ]; then
		printf '#FECHADA,%s\n' "$aberta"
	fi
	aberta=""
}

listar() {
	achadas=""
	for d in /dev/ttyACM* /dev/ttyUSB* /dev/tty.usbmodem* /dev/tty.usbserial* /dev/tty.wchusbserial*; do
		[ -e "$d" ] || continue
		if [ -z "$achadas" ]; then achadas="$d"; else achadas="$achadas,$d"; fi
	done
	printf '#PORTAS,%s\n' "$achadas"
}

abrir() {
	alvo="$1"
	vel="$2"
	fechar quieto
	if [ ! -e "$alvo" ]; then
		printf '#FALHA,%s,nao existe\n' "$alvo"
		return
	fi
	# `-hupcl` IMPEDE O RESET A CADA ABERTURA em quem nao quer, mas nos
	# QUEREMOS o reset: e reiniciando que a placa manda o READY. Por isso
	# `hupcl` fica ligado (padrao) e nao mexemos nele.
	if ! stty -F "$alvo" "$vel" cs8 -cstopb -parenb -echo -icanon -ixon min 0 time 1 2>/dev/null; then
		# macOS usa -f no lugar de -F.
		if ! stty -f "$alvo" "$vel" cs8 -cstopb -parenb -echo -icanon -ixon min 0 time 1 2>/dev/null; then
			printf '#FALHA,%s,stty recusou\n' "$alvo"
			return
		fi
	fi
	if ! exec 3>"$alvo" 2>/dev/null; then
		printf '#FALHA,%s,sem permissao de escrita\n' "$alvo"
		return
	fi
	# `cat` E NAO `tr`, E O MOTIVO E BUFFER.
	#
	# O Arduino termina as linhas com \r\n, e a vontade e passar por um
	# `tr -d '\r'` para entregar limpo. Nao da: `tr` escreve por stdio, e
	# stdio com a saida num cano acumula 4 KB antes de soltar. O resultado
	# e a placa falando e o jogo sem ouvir nada por minutos -- que na tela
	# vira "o Arduino nao responde" e manda o tecnico procurar defeito no
	# lugar errado. `cat` copia com read/write direto, sem acumular nada,
	# e o byte sai no instante em que entra.
	#
	# O \r sobra, entao, e e retirado do outro lado: quem le no Godot
	# passa cada linha por `strip_edges()`.
	( cat < "$alvo" ) &
	leitor=$!
	aberta="$alvo"
	printf '#ABERTA,%s\n' "$alvo"
}

trap 'fechar quieto; exit 0' INT TERM HUP

printf '#PONTE,V1,unix\n'

if [ -n "$porta_pedida" ]; then
	abrir "$porta_pedida" "$baud"
else
	listar
fi

while IFS= read -r linha; do
	linha=$(printf '%s' "$linha" | tr -d '\r')
	[ -n "$linha" ] || continue
	case "$linha" in
		@LISTAR*) listar ;;
		@ABRIR*)
			resto=${linha#@ABRIR,}
			alvo=${resto%%,*}
			vel=${resto#*,}
			[ "$vel" = "$resto" ] && vel="$baud"
			abrir "$alvo" "$vel"
			;;
		@FECHAR*) fechar avisar ;;
		@SAIR*) fechar quieto; exit 0 ;;
		@*) printf '#ERRO,comando desconhecido %s\n' "$linha" ;;
		*)
			if [ -n "$aberta" ]; then
				printf '%s\n' "$linha" >&3 2>/dev/null || {
					printf '#ERRO,escrita falhou\n'
					fechar avisar
				}
			fi
			;;
	esac
done

fechar quieto
exit 0
