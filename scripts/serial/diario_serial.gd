class_name DiarioSerial
extends RefCounted

## O DIÁRIO DA BUSCA PELO ARDUINO.
##
## POR QUE ISTO EXISTE. Quando a máquina não acha a placa no PC do
## cliente, a única coisa que chega de volta é a frase "não funciona" —
## e com ela não se conserta nada. Todo o resto do diagnóstico depende de
## alguém estar na frente do gabinete, saber abrir a Central, saber o que
## está lendo, e conseguir repetir por telefone. Não é o que acontece às
## nove da noite num salão.
##
## Este diário anota CADA PASSO da procura: qual caminho subiu, que
## portas o sistema anunciou, qual foi tentada, o que cada uma respondeu,
## quantas vezes a ponte religou. Ele vai para dois lugares, e os dois de
## propósito:
##
##  1. UM ARQUIVO, ao lado do executável quando dá, e no `user://`
##     quando não dá. É o que se manda por e-mail.
##  2. A TELA, na Central Técnica — as últimas linhas, sempre visíveis.
##     É o que se FOTOGRAFA com o celular quando não há e-mail, nem
##     pendrive, nem paciência. Um retrato da tela resolve o que meia
##     hora de telefone não resolve.
##
## O diário nunca pode ser o motivo de a máquina falhar: se o arquivo não
## abrir, ele segue trabalhando só na memória, sem reclamar.

const NOME_DO_ARQUIVO := "punch_arduino.log"
## Quantas linhas ficam à mão para a tela. Oito é o que cabe na Central
## sem empurrar o resto da página para fora.
const LINHAS_NA_TELA := 8
## Teto do arquivo. Passado ele, o diário recomeça — um log que cresce
## sem limite numa máquina que fica ligada meses acaba enchendo o disco,
## e disco cheio quebra coisa de verdade.
const TETO_DO_ARQUIVO := 512 * 1024

var _recentes: PackedStringArray = PackedStringArray()
var _arquivo: FileAccess = null
var _caminho := ""
var _falha_do_arquivo := ""
var _ultima_igual := ""
var _repetidas := 0

func _init() -> void:
	_abrir()
	anotar("=== PUNCH CHALLENGE %s — %s %s ===" % [
		Versao.curta(), OS.get_name(), Engine.get_version_info().get("string", "")
	])
	anotar("executável: %s" % OS.get_executable_path())
	anotar("extensão nativa carregada: %s" % (
		"SIM" if ClassDB.class_exists(&"GdSerialManager") else "NÃO"
	))
	_instalar_diagnostico()

## O DIAGNÓSTICO CHEGA SOZINHO NA PASTA DO JOGO.
##
## O `tools/diagnostico_windows.ps1` responde de uma vez as seis causas
## invisíveis de "não acha o Arduino" — e a mais importante delas: ele
## ABRE cada porta COM e ESCUTA, dizendo se a placa está falando ou não.
## Isso separa "o jogo tem um defeito" de "o Windows nem está vendo a
## placa", que são consertos completamente diferentes.
##
## Só que ele viaja DENTRO do executável, e de lá ninguém clica nele. Um
## arquivo que existe mas que a pessoa não consegue abrir não serve de
## nada às nove da noite num salão. Então o jogo o desembrulha na própria
## pasta, junto com um `.bat` de clicar duas vezes, e escreve no diário
## onde ficou.
##
## Uma vez só: se já está lá, não reescreve — para não mexer numa pasta
## que o antivírus já examinou e aprovou.
func _instalar_diagnostico() -> void:
	if OS.get_name() != "Windows":
		return
	var pasta := OS.get_executable_path().get_base_dir()
	if pasta.is_empty():
		return
	var bat := pasta.path_join("DIAGNOSTICO.bat")
	var ps1 := pasta.path_join("diagnostico_windows.ps1")
	if FileAccess.file_exists(bat) and FileAccess.file_exists(ps1):
		anotar("diagnóstico já instalado em %s" % bat)
		return
	if not _copiar("res://tools/diagnostico_windows.ps1", ps1):
		anotar("não consegui gravar o diagnóstico em %s" % pasta)
		return
	var saida := FileAccess.open(bat, FileAccess.WRITE)
	if saida == null:
		anotar("não consegui gravar o DIAGNOSTICO.bat em %s" % pasta)
		return
	saida.store_string(ATALHO_DO_DIAGNOSTICO)
	saida.close()
	anotar("diagnóstico instalado: %s (clique duas vezes)" % bat)

static func _copiar(origem: String, destino: String) -> bool:
	var entrada := FileAccess.open(origem, FileAccess.READ)
	if entrada == null:
		return false
	var dados := entrada.get_buffer(entrada.get_length())
	entrada.close()
	if dados.is_empty():
		return false
	var saida := FileAccess.open(destino, FileAccess.WRITE)
	if saida == null:
		return false
	saida.store_buffer(dados)
	saida.close()
	return true

## O ATALHO DE CLICAR DUAS VEZES.
##
## Ele é `.bat` e não `.ps1` de propósito: um `.bat` abre com dois
## cliques em qualquer Windows, e um `.ps1` abre no Bloco de Notas. E
## quando o PowerShell não roda de jeito nenhum — que é uma das coisas
## que se quer descobrir — ele ainda responde o básico usando só o
## `cmd`, que sempre existe. Um diagnóstico que não roda na máquina
## quebrada não diagnostica nada.
##
## `pause` no fim porque a janela fecharia sozinha e ninguém leria uma
## linha.
const ATALHO_DO_DIAGNOSTICO := r"""@echo off
title Punch Challenge - Diagnostico da maquina
cd /d "%~dp0"
echo.
echo  ================================================================
echo   PUNCH CHALLENGE - DIAGNOSTICO DA MAQUINA
echo   Nao instala nada e nao muda nada neste computador.
echo   Espere terminar e mande o arquivo DIAGNOSTICO-PUNCH.txt
echo   que vai aparecer nesta mesma pasta.
echo  ================================================================
echo.
set "PS=powershell.exe"
where powershell.exe >nul 2>&1 || set "PS=%SystemRoot%\System32\WindowsPowerShell1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostico_windows.ps1"
if errorlevel 1 goto semps
goto fim

:semps
echo.
echo  O PowerShell nao rodou nesta maquina -- e isso ja e uma resposta.
echo  Segue o basico, pelo cmd, que sempre funciona:
echo.
echo  --- portas COM que o Windows conhece ---
mode
echo.
echo  --- portas COM no registro ---
reg query HKLM\HARDWARE\DEVICEMAP\SERIALCOMM
echo.
if exist "%SystemRoot%\System32\VCRUNTIME140.dll" (echo  VCRUNTIME140.dll: PRESENTE) else (echo  VCRUNTIME140.dll: AUSENTE)
if exist "%~dp0gdserial.dll" (echo  gdserial.dll: PRESENTE nesta pasta) else (echo  gdserial.dll: AUSENTE nesta pasta)
echo.
echo  Fotografe esta tela e mande.

:fim
echo.
pause
"""

## ONDE O ARQUIVO CABE, na ordem de quem vai procurá-lo.
##
## Ao lado do executável primeiro, porque é a pasta que a pessoa já tem
## aberta — pedir a alguém para achar
## `AppData\Roaming\Godot\app_userdata\...` por telefone não termina bem.
## Mas essa pasta pode ser só de leitura (instalado em `Arquivos de
## Programas`, ou rodando de um pendrive travado), e aí o `user://`
## salva o dia.
func _abrir() -> void:
	var tentativas := PackedStringArray()
	var ao_lado := OS.get_executable_path().get_base_dir()
	if not ao_lado.is_empty():
		tentativas.append(ao_lado.path_join(NOME_DO_ARQUIVO))
	tentativas.append(ProjectSettings.globalize_path("user://%s" % NOME_DO_ARQUIVO))
	for caminho in tentativas:
		var f := FileAccess.open(caminho, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(caminho, FileAccess.WRITE)
		if f == null:
			continue
		if f.get_length() > TETO_DO_ARQUIVO:
			f.close()
			f = FileAccess.open(caminho, FileAccess.WRITE)
			if f == null:
				continue
		f.seek_end()
		_arquivo = f
		_caminho = caminho
		return
	_falha_do_arquivo = "nenhuma pasta gravável para o diário"

## Onde o arquivo ficou, para a Central mostrar. Vazio quer dizer que o
## diário só existe na tela.
func caminho() -> String:
	return _caminho

func motivo_sem_arquivo() -> String:
	return _falha_do_arquivo

## As últimas linhas, da mais antiga para a mais nova.
func recentes() -> PackedStringArray:
	return _recentes

## Anota um passo. Linhas repetidas viram "(× N)" em vez de encherem o
## diário: a busca repete a mesma frase muitas vezes por minuto, e um
## diário em que a mesma linha aparece trezentas vezes esconde a linha
## diferente, que é justamente a que interessa.
func anotar(texto: String) -> void:
	if texto == _ultima_igual:
		_repetidas += 1
		if _repetidas % 20 != 0:
			return
		texto = "%s (× %d)" % [texto, _repetidas + 1]
	else:
		_ultima_igual = texto
		_repetidas = 0
	var linha := "[%s] %s" % [Time.get_time_string_from_system(true), texto]
	_recentes.append(linha)
	while _recentes.size() > LINHAS_NA_TELA:
		_recentes.remove_at(0)
	if _arquivo == null:
		return
	_arquivo.store_line(linha)
	# Gravado na hora: um diário que só chega ao disco quando o jogo fecha
	# direito é um diário que não existe justamente quando a máquina trava.
	_arquivo.flush()

func encerrar() -> void:
	if _arquivo != null:
		anotar("=== fim ===")
		_arquivo.close()
		_arquivo = null
