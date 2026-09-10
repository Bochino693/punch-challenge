# ======================================================================
#  PONTE SERIAL -- Arduino <-> jogo, SEM INSTALAR NADA.
# ======================================================================
#
#  POR QUE ISTO EXISTE.
#
#  O Godot nao sabe abrir uma porta COM sozinho. Ate agora quem fazia
#  isso era uma extensao nativa (gdserial.dll). Quando ela nao carrega --
#  e no gabinete do operador ela NAO CARREGOU -- o jogo fica escrito
#  "SIMULACAO -- SEM EXTENSAO SERIAL" e a maquina inteira morre junto:
#  START morto, CREDITO morto, sensor mudo, fitas apagadas.
#
#  Este arquivo e o plano B que nao depende de nada: o Windows ja vem com
#  o PowerShell, e o PowerShell ja vem com System.IO.Ports.SerialPort.
#  Nao ha Python para instalar, nao ha .dll para faltar, nao ha antivirus
#  para apagar um binario desconhecido. Em PC cru, funciona.
#
#  COMO CONVERSA COM O JOGO.
#
#  O jogo abre este script como processo filho e fala pelos canos padrao
#  (OS.execute_with_pipe). Uma linha de texto para cada lado.
#
#    jogo -> ponte   @LISTAR              reenumera as portas
#                    @ABRIR,COM5,115200   abre
#                    @FECHAR              fecha
#                    @SAIR                encerra
#                    qualquer outra linha vai CRUA para o Arduino
#                    (PING, TEST, CONFIG,... , LEDS,...)
#
#    ponte -> jogo   #PONTE,V1            apresentacao
#                    #PORTAS,COM3,COM5    lista, ja em ordem de suspeita
#                    #ABERTA,COM5
#                    #FECHADA,COM5
#                    #FALHA,COM5,motivo
#                    #ERRO,texto
#                    qualquer outra linha veio CRUA do Arduino
#
#  A REGRA DE OURO: ESTE LACO NUNCA PODE BLOQUEAR.
#
#  Se ele parar esperando um byte que nao vem, o cano entope e o jogo
#  trava junto. Por isso a leitura do Arduino usa ReadExisting() (volta na
#  hora com o que houver, nem que seja vazio) e a leitura dos comandos do
#  jogo usa BeginRead/IsCompleted (assincrona). Nada aqui espera.
#
#  Uso manual, para testar fora do jogo:
#      powershell -NoProfile -ExecutionPolicy Bypass -File ponte_serial.ps1
#  Depois digite  @LISTAR  e Enter.
# ======================================================================

param(
    [string]$Porta = "",
    [int]$Baud = 115200
)

$ErrorActionPreference = "Continue"

# A SAIDA PRECISA SER UTF-8 SEM BOM.
#
# O console do Windows fala CP-850/CP-1252. Deixando como esta, cada
# linha do Arduino chega no jogo com bytes trocados, e o BOM (tres bytes
# invisiveis no comeco) entra dentro da PRIMEIRA linha -- que e
# justamente o "READY". O jogo compara com "READY", nao bate, e conclui
# que a placa nao respondeu.
try {
    $semBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $semBom
    $saida = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $semBom)
    $saida.AutoFlush = $true
} catch {
    $saida = [Console]::Out
}

function Dizer([string]$texto) {
    try { $saida.WriteLine($texto) } catch { }
}

# A APRESENTACAO E A PRIMEIRA COISA QUE SAI, ANTES DE QUALQUER TRABALHO.
#
# Ela ficava depois do `Add-Type` e das definicoes -- e o `Add-Type` de
# `System.IO.Ports` carrega um assembly, o que num PC lento ou com
# antivirus vigiando o PowerShell leva segundos. O jogo conta o tempo da
# apresentacao para decidir se a politica do Windows recusou o script, e
# um `Add-Type` demorado estourava esse prazo: o jogo derrubava um
# ajudante que estava perfeitamente vivo e recomecava, para trocar de
# receita e derrubar o proximo. A ponte nunca chegava a dizer nada.
#
# Falar primeiro e trabalhar depois nao custa nada e tira o prazo do
# caminho.
Dizer "#PONTE,V1,windows"

# Em Windows PowerShell (5.1) a classe SerialPort ja vem carregada; em
# PowerShell 7 ela mora num pacote a parte. Tentar carregar e nao
# conseguir nao pode derrubar a ponte -- por isso o try vazio.
try { Add-Type -AssemblyName System.IO.Ports -ErrorAction SilentlyContinue } catch { }

$script:sp = $null
$script:portaAberta = ""
$script:sobras = ""
$script:listaConhecida = @()
$script:nomesCrus = @()
$script:proximaBusca = [DateTime]::MinValue

# ----------------------------------------------------------------------
#  QUAL DESSAS PORTAS E UM ARDUINO?
# ----------------------------------------------------------------------
#
#  Um gabinete quase nunca tem uma porta COM so: o Bluetooth inventa duas,
#  o leitor de cartao traz a dele, a impressora fiscal traz outra. Abrir a
#  primeira da lista e sorteio -- e a porta errada nao responde nunca.
#
#  Estes sao os fabricantes de conversor USB-serial que aparecem num
#  Arduino: 2341 e 2A03 sao os oficiais, 1A86 e o CH340 dos clones de
#  Nano, 0403 e o FTDI, 10C4 e o CP210x. Uma porta com um desses vai para
#  a frente da fila; as outras ficam atras, porque uma porta anonima ainda
#  pode ser a placa.
$MARCAS = @("VID_2341", "VID_2A03", "VID_1A86", "VID_0403", "VID_10C4", "VID_1B4F",
            "ARDUINO", "CH340", "CH341", "USB-SERIAL", "USB SERIAL", "FT232", "CP210")

# MAIUSCULA SO PARA QUEM E "COM ALGUMA COISA".
#
# No Windows a porta se chama COM5 e escrever "com5" ou "COM5" da na
# mesma -- deixar tudo maiusculo evita a mesma porta aparecer duas vezes
# com grafias diferentes. Fora do Windows o nome e um caminho de arquivo
# (/dev/ttyUSB0), e caminho tem maiuscula e minuscula que importam:
# passar tudo para maiuscula ali inventa uma porta que nao existe. Esta
# funcao e a diferenca entre as duas coisas.
function Normalizar([string]$nome) {
    $nome = $nome.Trim()
    if ($nome -match '^(?i)com\d+$') { return $nome.ToUpper() }
    return $nome
}

function NumeroDaPorta([string]$nome) {
    $digitos = ($nome -replace "\D", "")
    if ($digitos -eq "") { return 9999 }
    return [int]$digitos
}

# TRES FONTES, E NAO UMA -- E ESTE E O CONSERTO DO "FUNCIONA NO MEU PC".
#
# A lista de portas vinha SO do `[SerialPort]::GetPortNames()`. Ele le uma
# chave do registro, e quando essa chave nao tem a porta -- driver CH340
# instalado por cima de outro, porta que o Windows enumerou de um jeito
# antigo, perfil de usuario sem permissao de leitura ali -- ele devolve
# VAZIO. Vazio sem erro: nenhuma excecao, nenhuma pista. O jogo recebia
# "#PORTAS," sem nada, concluia que nao havia porta e ficava
# "PROCURANDO ARDUINO..." para sempre, com a placa espetada e falando.
#
# E POR ISSO O DIAGNOSTICO NAO BATE ENTRE DOIS PCs: nao e a placa que
# muda, e QUEM SABE DA PORTA que muda. Num PC as tres fontes concordam;
# noutro, duas estao cegas e a terceira sabe.
#
# Agora sao tres, e a lista e a UNIAO delas:
#   1. GetPortNames()               -- o caminho normal, quando funciona
#   2. HKLM\HARDWARE\DEVICEMAP\SERIALCOMM -- o registro cru, direto
#   3. Win32_SerialPort / Win32_PnPEntity   -- o gerenciador de dispositivos
# Uma fonte cega nao apaga o que as outras acharam. Para uma porta ser
# ignorada agora, as tres precisam nao a conhecer -- e mesmo aí sobra a
# varredura cega do lado do jogo.
# TRES FONTES, E NAO UMA -- E ESTE E O CONSERTO DO "FUNCIONA NO MEU PC".
#
# A lista de portas vinha SO do `[SerialPort]::GetPortNames()`. Ele le uma
# chave do registro, e quando essa chave nao tem a porta -- driver CH340
# instalado por cima de outro, porta enumerada de um jeito antigo, perfil
# de usuario sem permissao de leitura ali -- ele devolve VAZIO. Vazio sem
# erro: nenhuma excecao, nenhuma pista. O jogo recebia "#PORTAS," sem
# nada, concluia que nao havia porta e ficava "PROCURANDO ARDUINO..."
# para sempre, com a placa espetada e falando.
#
# E POR ISSO O DIAGNOSTICO NAO BATE ENTRE DOIS PCs: nao e a placa que
# muda, e QUEM SABE DA PORTA. Num PC as tres fontes concordam; noutro,
# duas estao cegas e a terceira sabe. A lista e a UNIAO das tres, e uma
# fonte cega nao apaga o que as outras acharam:
#   1. GetPortNames()                        -- o caminho normal
#   2. HKLM\HARDWARE\DEVICEMAP\SERIALCOMM   -- o registro cru
#   3. Win32_PnPEntity                       -- o gerenciador de dispositivos
# Para uma porta ser ignorada agora, as tres precisam nao a conhecer -- e
# mesmo ai sobra a varredura cega do lado do jogo.

# AS DUAS FONTES BARATAS: milissegundos, podem rodar sempre.
function NomesBaratos() {
    $achados = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($n in @([System.IO.Ports.SerialPort]::GetPortNames())) {
            if ($n) { $achados.Add((Normalizar $n)) }
        }
    } catch { }
    # O registro cru: a mesma informacao que o GetPortNames le, mas sem a
    # camada do .NET no meio -- e ha maquina em que uma funciona e a outra
    # nao.
    try {
        $chave = Get-ItemProperty -Path "HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM" -ErrorAction Stop
        foreach ($prop in $chave.PSObject.Properties) {
            if ($prop.Name -like "PS*") { continue }
            $valor = ([string]$prop.Value) -replace '^\\\\\.\\', ''
            if ($valor -match '^(?i)com\d+$') { $achados.Add($valor.ToUpper()) }
        }
    } catch { }
    return @($achados | Where-Object { $_ } | Sort-Object -Unique)
}

# A FONTE CARA: o gerenciador de dispositivos. Varre uns mil e quinhentos
# dispositivos e leva de um a tres segundos num PC bom, mais num PC de
# gabinete -- e o laco desta ponte e o mesmo que le a placa, entao cada
# consulta e um tempo em que a placa fala e ninguem ouve. Por isso ela e
# racionada: roda quando a lista barata MUDA (a resposta pode ter mudado)
# e, quando a lista barata esta vazia, de seis em seis segundos, porque ai
# ela e a unica que ainda pode saber da porta.
#
# Ela serve duas coisas de uma vez: descobre portas que as baratas nao
# viram, e diz QUEM e cada porta, que e o que monta a fila de prioridade.
$script:mapaPnp = @{}
$script:pnpEm = [DateTime]::MinValue

function ConsultarPnp() {
    $mapa = @{}
    try {
        $itens = $null
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $itens = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue
        } else {
            $itens = Get-WmiObject Win32_PnPEntity -ErrorAction SilentlyContinue
        }
        # `@(...)` porque `$itens` pode voltar vazio, e um foreach sobre
        # nada precisa dar zero voltas -- nao uma volta com $null.
        foreach ($it in @($itens)) {
            $rotulo = [string]$it.Name
            if ($rotulo -notmatch "\((COM\d+)\)") { continue }
            $qual = $matches[1].ToUpper()
            $mapa[$qual] = ($rotulo + " " + [string]$it.PNPDeviceID).ToUpper()
        }
    } catch { }
    $script:mapaPnp = $mapa
    $script:pnpEm = Get-Date
}

function ChiaAArduino([string]$texto) {
    if (-not $texto) { return $false }
    foreach ($m in $MARCAS) {
        if ($texto.Contains($m)) { return $true }
    }
    return $false
}

function Enumerar() {
    $baratos = @(NomesBaratos)
    $mudou = (($baratos -join ",") -ne ($script:nomesCrus -join ","))
    $script:nomesCrus = $baratos
    # Racionamento da consulta cara -- ver o comentario de `ConsultarPnp`.
    $vencido = ((Get-Date) - $script:pnpEm).TotalSeconds -ge 6
    if ($mudou -or ($baratos.Count -eq 0 -and $vencido) -or $script:pnpEm -eq [DateTime]::MinValue) {
        ConsultarPnp
    }

    $todos = New-Object System.Collections.Generic.List[string]
    foreach ($n in $baratos) { $todos.Add($n) }
    foreach ($n in $script:mapaPnp.Keys) { $todos.Add([string]$n) }
    $nomes = @($todos | Where-Object { $_ } | Sort-Object -Unique)
    if ($nomes.Count -eq 0) { return @() }

    $frente = @($nomes | Where-Object { ChiaAArduino ([string]$script:mapaPnp[$_]) } | Sort-Object { NumeroDaPorta $_ })
    $fundo  = @($nomes | Where-Object { -not (ChiaAArduino ([string]$script:mapaPnp[$_])) } | Sort-Object { NumeroDaPorta $_ })
    return @($frente + $fundo)
}

function AnunciarPortas([bool]$sempre) {
    $lista = Enumerar
    $script:proximaBusca = (Get-Date).AddSeconds(3)
    $mudou = ($lista -join ",") -ne ($script:listaConhecida -join ",")
    $script:listaConhecida = $lista
    if ($mudou -or $sempre) {
        Dizer ("#PORTAS," + ($lista -join ","))
    }
}

# A PRIMEIRA LISTA NAO PODE ESPERAR PELA PARTE CARA.
#
# `Enumerar` faz a classificacao por fabricante, e essa consulta ao
# gerenciador de dispositivos varre uns mil e quinhentos dispositivos: de
# um a tres segundos num PC bom, mais de dez num PC de gabinete. Durante
# esse tempo o jogo nao tinha lista NENHUMA e mostrava
# "PROCURANDO ARDUINO..." -- que e exatamente a queixa. Entao a lista
# barata sai na frente, na hora, e a classificada sai depois por cima. O
# jogo ja pode estar tentando a porta certa enquanto o Windows ainda
# responde quem ela e.
function AnunciarDepressa() {
    $cru = @()
    try { $cru = @([System.IO.Ports.SerialPort]::GetPortNames() | Where-Object { $_ } | ForEach-Object { Normalizar $_ } | Sort-Object -Unique) } catch { }
    if ($cru.Count -gt 0) {
        Dizer ("#PORTAS," + ($cru -join ","))
    }
}

function Fechar([bool]$avisar) {
    if ($script:sp -ne $null) {
        try { $script:sp.Close() } catch { }
        try { $script:sp.Dispose() } catch { }
    }
    $qual = $script:portaAberta
    $script:sp = $null
    $script:portaAberta = ""
    $script:sobras = ""
    if ($avisar -and $qual -ne "") { Dizer ("#FECHADA," + $qual) }
}

function Abrir([string]$nome, [int]$velocidade) {
    Fechar $false
    if ($nome -eq "") { Dizer "#FALHA,,porta vazia"; return }
    try {
        $p = New-Object System.IO.Ports.SerialPort($nome, $velocidade, "None", 8, "One")
        $p.ReadTimeout = 40
        $p.WriteTimeout = 800
        $p.NewLine = "`n"
        $p.Handshake = "None"
        $p.Open()
        # DTR E RTS LIGADOS DE PROPOSITO, E DEPOIS DE ABRIR.
        #
        # O Nano reinicia quando o DTR sobe -- e e reiniciando que ele
        # manda o "READY". Com DTR desligado (que e o padrao do .NET) a
        # placa fica quieta ate alguem apertar algo, o jogo espera um
        # READY que nunca vem e desiste da porta certa.
        #
        # Depois de abrir, e nao antes, porque nem toda porta tem essas
        # duas linhas. Adaptador sem controle de fluxo, porta virtual,
        # ponte de rede: em todas elas mexer no DTR devolve erro. Feito
        # ANTES do Open(), o erro derruba a abertura inteira e a porta
        # boa e descartada como se nao existisse; feito depois e dentro do
        # try, a porta abre e segue funcionando sem o reset.
        # E O RESET PRECISA DE UMA BORDA, nao de um estado.
        #
        # Punha DTR e RTS em `$true` e pronto. Funciona quando o driver
        # abriu a porta com eles em baixo -- que e o padrao do .NET e o
        # caso do PC de quem escreveu isto. Mas ha driver (CH340 generico,
        # e as portas que passam por concentrador USB) que ja entrega a
        # porta com DTR EM ALTA: pôr em alta o que ja esta em alta nao
        # move linha nenhuma, a placa nao reinicia, o `READY` nunca sai, e
        # o jogo descarta a porta CERTA como muda. Mesma placa, mesmo
        # cabo, mesmo firmware -- e um PC funciona e o outro nao.
        #
        # Baixar e subir garante o degrau que reinicia o Arduino em
        # qualquer driver. Os 60 ms sao o tempo de o capacitor de 100 nF
        # do circuito de reset da placa ver o pulso.
        try {
            $p.DtrEnable = $false
            $p.RtsEnable = $false
            Start-Sleep -Milliseconds 60
            $p.DtrEnable = $true
            $p.RtsEnable = $true
        } catch { }
        try { $p.DiscardInBuffer(); $p.DiscardOutBuffer() } catch { }
        $script:sp = $p
        $script:portaAberta = $nome
        Dizer ("#ABERTA," + $nome)
    } catch {
        $motivo = ($_.Exception.Message -replace "[\r\n,]", " ")
        Dizer ("#FALHA," + $nome + "," + $motivo)
    }
}

function ParaOArduino([string]$linha) {
    if ($script:sp -eq $null) { return }
    try {
        $script:sp.Write($linha + "`n")
    } catch {
        $motivo = ($_.Exception.Message -replace "[\r\n,]", " ")
        Dizer ("#ERRO,escrita " + $motivo)
        Fechar $true
    }
}

function Executar([string]$linha) {
    $linha = $linha.Trim()
    if ($linha -eq "") { return }
    if (-not $linha.StartsWith("@")) { ParaOArduino $linha; return }
    $campos = $linha.Substring(1).Split(",")
    switch ($campos[0].ToUpper()) {
        "LISTAR" { AnunciarPortas $true }
        "PORTAS" { AnunciarPortas $true }
        "ABRIR"  {
            $nome = ""
            if ($campos.Count -gt 1) { $nome = Normalizar $campos[1] }
            $vel = $Baud
            if ($campos.Count -gt 2) { try { $vel = [int]$campos[2] } catch { } }
            Abrir $nome $vel
        }
        "FECHAR" { Fechar $true }
        "SAIR"   { Fechar $false; exit 0 }
        default  { Dizer ("#ERRO,comando desconhecido " + $campos[0]) }
    }
}

# ----------------------------------------------------------------------
#  LACO PRINCIPAL
# ----------------------------------------------------------------------
$entrada = [Console]::OpenStandardInput()
$balde = New-Object byte[] 8192
$acumulado = ""
$pendente = $entrada.BeginRead($balde, 0, $balde.Length, $null, $null)

if ($Porta -ne "") {
    Abrir (Normalizar $Porta) $Baud
} else {
    AnunciarDepressa
    AnunciarPortas $true
}

while ($true) {

    # --- o que o jogo mandou (assincrono, nunca espera) ---
    if ($pendente.IsCompleted) {
        $lidos = 0
        try { $lidos = $entrada.EndRead($pendente) } catch { $lidos = 0 }
        if ($lidos -le 0) { break }   # o jogo fechou o cano: hora de sair
        $acumulado += [System.Text.Encoding]::UTF8.GetString($balde, 0, $lidos)
        while ($true) {
            $corte = $acumulado.IndexOf("`n")
            if ($corte -lt 0) { break }
            $uma = $acumulado.Substring(0, $corte).TrimEnd("`r")
            $acumulado = $acumulado.Substring($corte + 1)
            Executar $uma
        }
        $pendente = $entrada.BeginRead($balde, 0, $balde.Length, $null, $null)
    }

    # --- o que o Arduino mandou (ReadExisting: volta na hora) ---
    if ($script:sp -ne $null) {
        $pedaco = ""
        try {
            if ($script:sp.IsOpen) { $pedaco = $script:sp.ReadExisting() }
        } catch {
            # Porta arrancada no meio do jogo. Avisa e volta a procurar --
            # nao e motivo para a ponte inteira morrer.
            $motivo = ($_.Exception.Message -replace "[\r\n,]", " ")
            Dizer ("#ERRO,leitura " + $motivo)
            Fechar $true
            $pedaco = ""
        }
        if ($pedaco -ne "") {
            $script:sobras += $pedaco
            while ($true) {
                $corte = $script:sobras.IndexOf("`n")
                if ($corte -lt 0) { break }
                $uma = $script:sobras.Substring(0, $corte).TrimEnd("`r").Trim()
                $script:sobras = $script:sobras.Substring($corte + 1)
                if ($uma -ne "") { Dizer $uma }
            }
            # Linha sem fim a vista: lixo de reinicio da placa. Descarta,
            # senao a memoria cresce sem parar.
            if ($script:sobras.Length -gt 4096) { $script:sobras = "" }
        }
    } elseif ((Get-Date) -ge $script:proximaBusca) {
        # Sem porta aberta: fica de olho em placa espetada depois que a
        # maquina ja estava ligada.
        AnunciarPortas $false
    }

    Start-Sleep -Milliseconds 6
}

Fechar $false
exit 0
