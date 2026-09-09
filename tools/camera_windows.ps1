# PERGUNTA AO WINDOWS O QUE O OPENCV NAO CONSEGUE RESPONDER.
#
# Quando a sondagem do OpenCV volta "nenhuma camera respondeu", ha tres
# mundos diferentes escondidos atras da mesma frase:
#
#   1. o Windows tambem nao ve a camera      -> cabo, porta USB ou driver;
#   2. o Windows ve, mas a privacidade esta  -> um interruptor, e o jogo
#      fechada para aplicativos de area de      nem chega a tentar;
#      trabalho
#   3. o Windows ve e liberou, mas outro     -> so um programa por vez
#      programa esta com a camera aberta        pode abrir uma webcam.
#
# O OpenCV falha igual nos tres. Este script separa os tres, e por isso
# ele existe: sem ele o operador fica trocando cabo por causa de um
# interruptor de privacidade.
#
# Uso:
#   powershell -NoProfile -ExecutionPolicy Bypass -File camera_windows.ps1 -Acao listar
#   powershell -NoProfile -ExecutionPolicy Bypass -File camera_windows.ps1 -Acao liberar
#
# SAIDA SEM ACENTO, DE PROPOSITO. Ela e lida pelo jogo atraves de
# OS.execute, e a pagina de codigo do console do Windows nao e UTF-8:
# um "camera" com acento chega no jogo como "c mera".

param(
    [ValidateSet("listar", "liberar")]
    [string]$Acao = "listar"
)

$ErrorActionPreference = "Continue"

# O caminho do interruptor "permitir que aplicativos de area de trabalho
# acessem sua camera". NonPackaged e justamente o ramo dos programas que
# nao vieram da Loja -- que e o caso do jogo.
$RamoUsuario = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
$RamoMaquina = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"

function Ler-Consentimento($caminho) {
    try {
        $item = Get-ItemProperty -Path $caminho -Name Value -ErrorAction Stop
        return $item.Value
    } catch {
        return "?"
    }
}

function Listar-Dispositivos {
    $achou = 0
    try {
        $lista = Get-PnpDevice -Class Camera, Image -PresentOnly -ErrorAction Stop
        foreach ($d in $lista) {
            $achou++
            Write-Output ("DISPOSITIVO=" + $d.FriendlyName + " | " + $d.Status)
        }
    } catch {
        Write-Output "DISPOSITIVO=<Get-PnpDevice indisponivel neste Windows>"
    }
    Write-Output ("WINDOWS_CAMERAS=" + $achou)
}

# Programas que costumam segurar a webcam. Nao da para saber com certeza
# quem esta com o dispositivo aberto sem um driver de filtro; da para
# dizer quais dos suspeitos de sempre estao rodando agora, que e o que o
# operador precisa saber para fechar e tentar de novo.
$Suspeitos = @(
    "WindowsCamera", "Teams", "ms-teams", "Zoom", "obs64", "obs32",
    "Skype", "Discord", "chrome", "msedge", "firefox", "CameraApp"
)

function Listar-Suspeitos {
    $abertos = @()
    foreach ($nome in $Suspeitos) {
        try {
            if (Get-Process -Name $nome -ErrorAction SilentlyContinue) {
                $abertos += $nome
            }
        } catch { }
    }
    if ($abertos.Count -gt 0) {
        Write-Output ("OCUPANTES=" + ($abertos -join ", "))
    } else {
        Write-Output "OCUPANTES=nenhum"
    }
}

if ($Acao -eq "liberar") {
    # SO O RAMO DO USUARIO. HKLM exigiria administrador, e um jogo que
    # pede elevacao para abrir a webcam e um jogo que o operador vai
    # desistir de usar. O ramo do usuario e exatamente o mesmo valor que
    # o aplicativo Configuracoes do Windows grava quando alguem move o
    # interruptor a mao -- nada aqui e escondido nem irreversivel.
    foreach ($caminho in @($RamoUsuario, ($RamoUsuario + "\NonPackaged"))) {
        try {
            if (-not (Test-Path $caminho)) {
                New-Item -Path $caminho -Force | Out-Null
            }
            $antes = Ler-Consentimento $caminho
            Set-ItemProperty -Path $caminho -Name Value -Value "Allow" -ErrorAction Stop
            $depois = Ler-Consentimento $caminho
            Write-Output ("LIBEROU=" + $caminho.Split('\')[-1] + " " + $antes + " -> " + $depois)
        } catch {
            Write-Output ("FALHOU=" + $caminho.Split('\')[-1] + " " + $_.Exception.Message)
        }
    }
}

Listar-Dispositivos
Write-Output ("PRIVACIDADE_USUARIO=" + (Ler-Consentimento $RamoUsuario))
Write-Output ("PRIVACIDADE_PROGRAMAS=" + (Ler-Consentimento ($RamoUsuario + "\NonPackaged")))
Write-Output ("PRIVACIDADE_MAQUINA=" + (Ler-Consentimento $RamoMaquina))
Listar-Suspeitos
