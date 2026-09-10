# ======================================================================
#  PUNCH CHALLENGE -- DIAGNOSTICO DA MAQUINA (Windows)
# ======================================================================
#
#  POR QUE ISTO EXISTE.
#
#  "Funciona no meu PC e nao no outro" nao se resolve por telefone. As
#  causas possiveis sao meia duzia, todas invisiveis, e todas com o mesmo
#  sintoma na tela do jogo. Este arquivo responde as seis de uma vez, na
#  maquina onde o problema acontece, sem instalar nada e sem depender do
#  jogo estar aberto.
#
#  A PERGUNTA QUE ELE RESPONDE DE VERDADE e a ultima: ele ABRE cada porta
#  COM da maquina, uma por uma, e ESCUTA. Se o Arduino estiver espetado e
#  falando, ele aparece aqui com o nome da porta e a linha que mandou --
#  e ai o problema esta no jogo. Se nao aparecer em porta nenhuma, o
#  problema esta antes do jogo (driver, cabo ou placa), e nenhuma
#  mudanca de codigo vai consertar.
#
#  Uso: clique duas vezes no DIAGNOSTICO.bat que esta ao lado.
#  A saida vai para a tela E para DIAGNOSTICO-PUNCH.txt na mesma pasta.
# ======================================================================

$ErrorActionPreference = "Continue"
$linhas = New-Object System.Collections.Generic.List[string]

function Dizer([string]$t) {
    Write-Host $t
    $linhas.Add($t)
}
function Titulo([string]$t) {
    Dizer ""
    Dizer ("=== " + $t + " " + ("=" * [Math]::Max(0, 60 - $t.Length)))
}

Dizer "PUNCH CHALLENGE -- DIAGNOSTICO DA MAQUINA"
Dizer ("gerado em " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))

# ----------------------------------------------------------------- 1
Titulo "1. A MAQUINA"
try {
    $so = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Dizer ("Windows      : " + $so.Caption + " (build " + $so.BuildNumber + ")")
} catch { Dizer "Windows      : nao consegui perguntar" }
Dizer ("PowerShell   : " + $PSVersionTable.PSVersion.ToString())
Dizer ("Processo     : " + $(if ([Environment]::Is64BitProcess) { "64 bits" } else { "32 bits" }))
try { Dizer ("Politica     : " + (Get-ExecutionPolicy)) } catch { }

# ----------------------------------------------------------------- 2
#  O runtime do Visual C++. A extensao nativa do jogo (gdserial.dll)
#  depende dele, e ele NAO vem no Windows limpo -- e a causa numero um
#  do "funciona no meu PC". Nao e obrigatorio: sem ele o jogo usa a
#  ponte. Mas e bom saber em qual dos dois a maquina esta.
Titulo "2. RUNTIME DO VISUAL C++ (VCRUNTIME140.dll)"
$vc = @()
foreach ($p in @("$env:SystemRoot\System32\VCRUNTIME140.dll",
                 "$env:SystemRoot\SysWOW64\VCRUNTIME140.dll")) {
    if (Test-Path $p) { $vc += $p }
}
if ($vc.Count -gt 0) {
    Dizer "PRESENTE. A extensao nativa pode carregar:"
    foreach ($p in $vc) { Dizer ("   " + $p) }
} else {
    Dizer "AUSENTE -- a extensao nativa do jogo NAO vai carregar nesta maquina."
    Dizer "Isso NAO impede o jogo de funcionar (ele usa a ponte do PowerShell),"
    Dizer "mas se quiser o caminho rapido, instale:"
    Dizer "   Microsoft Visual C++ 2015-2022 Redistributable (x64)"
}

# ----------------------------------------------------------------- 3
Titulo "3. ARQUIVOS DO JOGO NESTA PASTA"
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
$achouExe = $false
foreach ($f in @(Get-ChildItem -Path $pasta -Filter *.exe -ErrorAction SilentlyContinue)) {
    Dizer ("executavel   : " + $f.Name)
    $achouExe = $true
}
if (-not $achouExe) { Dizer "executavel   : nenhum .exe nesta pasta (rodando fora da pasta do jogo?)" }
$dll = Join-Path $pasta "gdserial.dll"
if (Test-Path $dll) {
    Dizer "gdserial.dll : PRESENTE ao lado do executavel"
} else {
    Dizer "gdserial.dll : NAO esta nesta pasta."
    Dizer "               Se o .exe do jogo esta aqui, a extensao ficou para tras"
    Dizer "               na copia -- leve a PASTA INTEIRA, nao so o .exe."
    Dizer "               (O jogo funciona assim mesmo, pela ponte.)"
}

# ----------------------------------------------------------------- 4
#  As tres fontes que sabem de porta COM. Elas discordam entre si de
#  maquina para maquina -- e por isso o jogo consulta as tres.
Titulo "4. PORTAS COM, PELAS TRES FONTES"
$todas = New-Object System.Collections.Generic.List[string]

try { Add-Type -AssemblyName System.IO.Ports -ErrorAction SilentlyContinue } catch { }
$f1 = @()
try { $f1 = @([System.IO.Ports.SerialPort]::GetPortNames()) } catch { }
Dizer ("fonte 1 (.NET GetPortNames) : " + $(if ($f1.Count) { $f1 -join ", " } else { "nenhuma" }))
foreach ($n in $f1) { $todas.Add($n.ToUpper()) }

$f2 = @()
try {
    $ch = Get-ItemProperty -Path "HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM" -ErrorAction Stop
    foreach ($pr in $ch.PSObject.Properties) {
        if ($pr.Name -like "PS*") { continue }
        $v = ([string]$pr.Value) -replace '^\\\\\.\\', ''
        if ($v -match '^(?i)com\d+$') { $f2 += $v.ToUpper() }
    }
} catch { }
Dizer ("fonte 2 (registro SERIALCOMM): " + $(if ($f2.Count) { $f2 -join ", " } else { "nenhuma" }))
foreach ($n in $f2) { $todas.Add($n) }

$f3 = @()
try {
    foreach ($it in @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue)) {
        $nome = [string]$it.Name
        if ($nome -match "\((COM\d+)\)") {
            $f3 += ($matches[1].ToUpper() + "  <- " + $nome)
            $todas.Add($matches[1].ToUpper())
        }
    }
} catch { }
Dizer "fonte 3 (gerenciador de dispositivos):"
if ($f3.Count) { foreach ($n in $f3) { Dizer ("   " + $n) } } else { Dizer "   nenhuma" }

$portas = @($todas | Sort-Object -Unique)
Dizer ("UNIAO DAS TRES: " + $(if ($portas.Count) { $portas -join ", " } else { "NENHUMA PORTA COM NESTA MAQUINA" }))

# ----------------------------------------------------------------- 5
#  Dispositivo com problema = driver faltando. E aqui que um CH340 sem
#  driver aparece, como "Dispositivo desconhecido" com codigo 28.
Titulo "5. DISPOSITIVOS COM PROBLEMA (driver faltando)"
$problemas = 0
$perguntou = $false
try {
    $itens = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
    $perguntou = $true
    foreach ($it in $itens) {
        if ($it.ConfigManagerErrorCode -ne $null -and $it.ConfigManagerErrorCode -ne 0) {
            $problemas++
            Dizer ("   codigo " + $it.ConfigManagerErrorCode + " : " + $it.Name + "  [" + $it.PNPDeviceID + "]")
        }
    }
} catch { }
if (-not $perguntou) {
    Dizer "   nao consegui perguntar (isto so funciona no Windows)"
} elseif ($problemas -eq 0) {
    Dizer "   nenhum -- todos os dispositivos tem driver."
} else {
    Dizer ""
    Dizer "   Codigo 28 quer dizer DRIVER NAO INSTALADO. Se um dos de cima for"
    Dizer "   o conversor da placa (VID_1A86 = CH340, VID_0403 = FTDI,"
    Dizer "   VID_10C4 = CP210x, VID_2341 = Arduino), instale o driver dele."

}

# ----------------------------------------------------------------- 6
#  A PERGUNTA QUE IMPORTA: alguma porta tem um Arduino falando?
Titulo "6. ESCUTANDO CADA PORTA (a prova final)"
if ($portas.Count -eq 0) {
    Dizer "Nao ha porta COM para escutar."
    Dizer "Isso quer dizer que o WINDOWS nao esta vendo a placa -- nao o jogo."
    Dizer "Causas, em ordem: (a) driver CH340 faltando, (b) cabo USB so de"
    Dizer "carga, sem fios de dados, (c) placa sem alimentacao ou queimada."
} else {
    Dizer "Abrindo cada porta a 115200 e ouvindo 3 segundos."
    Dizer "O Arduino reinicia ao abrir a porta e se apresenta sozinho."
    Dizer ""
    $achouPlaca = $false
    foreach ($nome in $portas) {
        $sp = $null
        try {
            $sp = New-Object System.IO.Ports.SerialPort($nome, 115200, "None", 8, "One")
            $sp.ReadTimeout = 50
            $sp.Handshake = "None"
            $sp.Open()
            # O reset do Arduino precisa de uma BORDA no DTR, nao de um
            # estado: ha driver que ja entrega a porta com DTR em alta.
            try {
                $sp.DtrEnable = $false; $sp.RtsEnable = $false
                Start-Sleep -Milliseconds 60
                $sp.DtrEnable = $true; $sp.RtsEnable = $true
            } catch { }
            try { $sp.DiscardInBuffer() } catch { }
            $texto = ""
            $fim = (Get-Date).AddSeconds(3)
            while ((Get-Date) -lt $fim -and $texto.Length -lt 400) {
                try { $texto += $sp.ReadExisting() } catch { }
                Start-Sleep -Milliseconds 25
            }
            $limpo = ($texto -replace "[\r\n]+", " | ").Trim()
            if ($limpo -eq "") {
                Dizer ("   " + $nome + " : abriu, mas ficou MUDA")
            } else {
                $marca = ""
                if ($limpo -match "READY|TELEMETRY|PINS|PONG|HIT,") { $marca = "   <<< E A PLACA DO PUNCH CHALLENGE"; $achouPlaca = $true }
                Dizer ("   " + $nome + " : FALOU -> " + $limpo.Substring(0, [Math]::Min(160, $limpo.Length)) + $marca)
            }
        } catch {
            Dizer ("   " + $nome + " : nao abriu -- " + ($_.Exception.Message -replace "[\r\n]", " "))
        } finally {
            if ($sp -ne $null) { try { $sp.Close() } catch { }; try { $sp.Dispose() } catch { } }
        }
    }
    Dizer ""
    if ($achouPlaca) {
        Dizer "VEREDITO: A PLACA ESTA FALANDO nesta maquina, na porta marcada acima."
        Dizer "O Windows, o cabo, o driver e a placa estao todos certos."
        Dizer "Abra o jogo, aperte F9 -> DADOS e mande a foto do DIARIO DA BUSCA."
    } else {
        Dizer "VEREDITO: NENHUMA PORTA TEM O ARDUINO FALANDO."
        Dizer "O problema esta ANTES do jogo. Confira, nesta ordem:"
        Dizer "  1. O cabo USB tem fios de dados? Cabo so de carga nao serve."
        Dizer "     Troque por outro cabo e rode este diagnostico de novo."
        Dizer "  2. O driver da placa esta instalado? Veja a secao 5 acima."
        Dizer "  3. A placa esta gravada com o firmware punch_sensor?"
        Dizer "     Abra a IDE do Arduino e veja se o Monitor Serial a 115200"
        Dizer "     mostra READY / TELEMETRY. Se nao mostrar nem la, o jogo"
        Dizer "     nunca teve chance."
    }
}

Titulo "FIM"
$destino = Join-Path $pasta "DIAGNOSTICO-PUNCH.txt"
try {
    $semBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($destino, $linhas, $semBom)
    Write-Host ""
    Write-Host ("Tudo isto foi gravado em: " + $destino)
    Write-Host "Mande ESSE arquivo, ou uma foto desta tela."
} catch {
    Write-Host ""
    Write-Host "Nao consegui gravar o arquivo; fotografe a tela."
}
