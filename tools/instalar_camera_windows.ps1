<#
    INSTALADOR DA CÂMERA — PUNCH CHALLENGE (Windows 10/11)

    O que este script faz, nesta ordem:

      1. procura um Python utilizável (`py -3`, depois `python`);
      2. instala o OpenCV, se ainda não estiver instalado;
      3. varre os índices de câmera e diz quais respondem.

    POR QUE EXISTE. A ponte de câmera do jogo é um processo Python com
    OpenCV. Sem ele, a máquina roda — só não tira foto do ranking. O erro
    aparecia como "câmera não funciona", que é a mesma mensagem de cabo
    solto, driver ausente e webcam ocupada por outro programa: três
    problemas diferentes com o mesmo sintoma. Este script separa os
    quatro casos e diz qual é.

    COMO USAR. Clique com o botão direito e escolha
    "Executar com o PowerShell", ou, num prompt:

        powershell -ExecutionPolicy Bypass -File tools\instalar_camera_windows.ps1

    Não precisa de administrador: a instalação é feita para o usuário
    (`--user`), que é o mesmo usuário que roda o gabinete.
#>

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$ponte = Join-Path $raiz "camera_bridge.py"

function Escrever($texto, $cor = "Gray") { Write-Host $texto -ForegroundColor $cor }

Escrever ""
Escrever "=== PUNCH CHALLENGE - INSTALADOR DA CAMERA ===" "Yellow"
Escrever ""

# ---------------------------------------------------------------- Python
# `py` é o lançador oficial do Windows e sabe achar a instalação certa
# mesmo com várias versões no computador. `python` é a reserva, e sofre
# do atalho da Microsoft Store, que existe e não é Python nenhum -- por
# isso a versão é conferida rodando o interpretador, e não pelo caminho.
$interpretador = $null
foreach ($tentativa in @(@("py", @("-3")), @("python", @()))) {
    $exe = $tentativa[0]
    $args = $tentativa[1]
    try {
        $versao = & $exe @args --version 2>&1
        if ($LASTEXITCODE -eq 0 -and "$versao" -match "Python 3") {
            $interpretador = @{ exe = $exe; args = $args; versao = "$versao".Trim() }
            break
        }
    } catch { }
}

if (-not $interpretador) {
    Escrever "PYTHON NAO ENCONTRADO." "Red"
    Escrever ""
    Escrever "Instale em https://www.python.org/downloads/windows/"
    Escrever "e marque 'Add python.exe to PATH' na primeira tela do instalador."
    Escrever ""
    Escrever "O jogo funciona sem isto -- so nao tira foto para o ranking."
    exit 1
}
Escrever ("Python encontrado: " + $interpretador.versao) "Green"

# ---------------------------------------------------------------- OpenCV
$temOpenCV = $false
try {
    & $interpretador.exe @($interpretador.args + @("-c", "import cv2")) 2>&1 | Out-Null
    $temOpenCV = ($LASTEXITCODE -eq 0)
} catch { }

if ($temOpenCV) {
    Escrever "OpenCV ja instalado." "Green"
} else {
    Escrever "Instalando OpenCV (pode levar alguns minutos)..." "Yellow"
    & $interpretador.exe @($interpretador.args + @("-m", "pip", "install", "--user", "--upgrade", "pip")) | Out-Null
    & $interpretador.exe @($interpretador.args + @("-m", "pip", "install", "--user", "opencv-python"))
    if ($LASTEXITCODE -ne 0) {
        Escrever "FALHA AO INSTALAR O OPENCV." "Red"
        Escrever "Verifique a conexao com a internet e rode de novo."
        exit 2
    }
    Escrever "OpenCV instalado." "Green"
}

# ---------------------------------------------------------------- câmeras
if (-not (Test-Path $ponte)) {
    Escrever "camera_bridge.py nao encontrado ao lado deste script." "Red"
    exit 3
}
Escrever ""
Escrever "Procurando cameras..." "Yellow"
& $interpretador.exe @($interpretador.args + @($ponte, "--probe"))

Escrever ""
Escrever "PROXIMO PASSO" "Yellow"
Escrever "Abra o jogo, aperte F9, va na pagina CAMERA e confira a previa."
Escrever "Se nenhum indice respondeu acima, o problema esta antes do jogo:"
Escrever "cabo, driver, ou outro programa segurando a webcam (Teams, Meet,"
Escrever "OBS, o app Camera do Windows)."
Escrever ""
