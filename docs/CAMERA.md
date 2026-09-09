# Câmera do Punch Challenge

A máquina fotografa quem entra no Top 20. A foto é tirada no momento da
pose, fica no disco do próprio gabinete (`user://ranking_photos`) e é
apagada sozinha quando a marca sai da lista. **Nada vai para a rede.**

---

## Por que existe uma ponte em Python

O `CameraServer` do Godot **não entrega imagem no Windows**, que é onde o
gabinete roda. Não é bug do jogo: a plataforma simplesmente não tem o
driver implementado, e `CameraServer.feeds()` volta vazio.

Então o jogo tem dois caminhos, nesta ordem:

1. **Nativo** — se o Godot enxergar a webcam (Linux, macOS, Android), usa
   direto, sem nada instalado.
2. **Ponte** — se não enxergar, o jogo **sobe sozinho** um processo
   Python que abre a webcam com OpenCV e publica o quadro atual num
   arquivo. O jogo lê esse arquivo quinze vezes por segundo.

Você não precisa iniciar a ponte à mão. O jogo faz isso quando abre.

---

## Instalação no gabinete (Windows)

Só há dois pré-requisitos, e os dois são do Python:

1. **Instale o Python 3** de python.org — marque **"Add Python to PATH"**
   na primeira tela do instalador. É o passo que mais gente pula, e sem
   ele o jogo não acha o interpretador.
2. **Instale o OpenCV**, num Prompt de Comando:

   ```
   py -m pip install opencv-python
   ```

Pronto. Abra o jogo, aperte `F9` e a seção da câmera deve mostrar
**CÂMERA CONECTADA (PONTE)**.

---

## A sua webcam: Intuitive Sigma W420

É uma webcam USB comum (classe UVC), do tipo que o Windows reconhece
sozinho, sem driver do fabricante. Para o jogo ela não tem nada de
especial — o que importa é em **qual índice** o sistema a coloca.

Se ela não aparecer de primeira, rode a sonda:

```
py tools\camera_bridge.py --probe
```

A saída diz exatamente o que está acontecendo:

```
câmera 0: OK via DSHOW — 640x480
use --camera 0 (ou ajuste na Central Técnica do jogo)
```

- **Se aparecer um índice**, e não for 0, use **TROCAR CÂMERA** na Central
  Técnica (`F9`) até a imagem certa aparecer no espelho.
- **Se não aparecer nenhum**, o problema está antes do jogo: cabo,
  porta USB, ou outro programa segurando a webcam (Teams, Meet, Camera
  do Windows — feche todos e teste de novo).

Notebooks com câmera embutida quase sempre têm a interna no índice 0 e a
USB no 1.

---

## Separando "ponte quebrada" de "câmera quebrada"

Quando não dá imagem, a dúvida é sempre a mesma: é o jogo ou é a webcam?
Existe um modo de teste que responde isso sem webcam nenhuma — a mesma
ideia do comando `TEST` do firmware do sensor:

```
py tools\camera_bridge.py --output %APPDATA%\Godot\app_userdata\Punch Challenge\camera_bridge\live.jpg --pattern
```

Ele publica um padrão colorido com um contador. Se o padrão **aparece**
no jogo, todo o caminho está bom e o problema é a webcam. Se **não
aparece**, o problema é a ponte (Python, OpenCV ou permissão de escrita).

---

## Quando algo dá errado

A Central Técnica mostra a linha de estado da ponte. Os textos vêm do
próprio processo, então dizem o motivo em vez de um erro genérico:

| Aparece na tela | O que é |
| --- | --- |
| `CÂMERA CONECTADA (PONTE)` | Funcionando. |
| `PYTHON NÃO ENCONTRADO` | Python não instalado, ou instalado sem "Add to PATH". |
| `PONTE SEM RESPOSTA — INSTALE OPENCV` | Python achado, mas o `pip install opencv-python` faltou. |
| `PROCURANDO CAMERA 0` | A ponte está de pé, mas o índice não responde — rode `--probe`. |
| `CAMERA PAROU DE RESPONDER` | Cabo solto ou webcam ocupada. A ponte reconecta sozinha. |
| `CÂMERA DESATIVADA` | Desligada de propósito na Central Técnica. |

A ponte **reconecta sozinha**: um tranco no cabo USB tira a imagem por
um segundo e ela volta, sem precisar reiniciar o jogo.

---

## Desligar a câmera

Na Central Técnica (`F9`), o botão da câmera desliga o recurso inteiro.
Com ela desligada o jogo funciona igual: o ranking mostra a silhueta no
lugar da foto e a tela de pose diz "SEM CÂMERA • VAMOS JOGAR".

Vale lembrar que fotografar clientes num estabelecimento tem
implicações — um aviso visível na máquina informando que há câmera é o
mínimo, e a LGPD trata imagem de pessoa identificável como dado pessoal.
O desligamento existe para isso.

## Instalação no Windows, em um passo

Rode `tools/instalar_camera_windows.ps1` — botão direito, "Executar com o
PowerShell". Ele procura o Python (`py -3`, depois `python`), instala o
OpenCV para o usuário e varre os índices de câmera, dizendo quais
respondem.

Não precisa de administrador. E o jogo roda sem nada disso: sem a ponte
ele só deixa de tirar foto para o ranking.

O script existe porque "câmera não funciona" era a mesma mensagem para
quatro problemas diferentes — Python ausente, OpenCV ausente, cabo/driver
e webcam ocupada por outro programa. Ele separa os quatro e diz qual é.

## Como o jogo sabe que a imagem é NOVA

A ponte publica, ao lado do JPEG, um `estado.txt` no formato
`TEXTO|contador|epoch_ms`. O contador sobe a cada quadro escrito.

A data de modificação do arquivo não serve para isso: ela tem resolução
de **um segundo** em vários sistemas de arquivos, e com ela o jogo não
consegue distinguir "quinze quadros novos" de "a ponte travou há
novecentos milissegundos".

Com o contador, o jogo:

- lê primeiro o `estado.txt`, que tem dezenas de bytes, e só abre o JPEG
  quando o contador andou — sem quadro novo não há por que ler dezenas de
  milhares de bytes quinze vezes por segundo;
- detecta **imagem congelada com processo vivo** (a webcam trava sem
  devolver erro ao OpenCV, e a ponte fica republicando o mesmo quadro).
  Três segundos com o contador parado e a ponte é religada;
- detecta **processo morto** e religa também. Antes a máquina só anunciava
  "desconectada" e ficava assim até alguém reiniciar o jogo — num salão,
  a noite inteira sem foto.

A Central Técnica, na página CÂMERA, mostra quantas vezes a ponte foi
religada na sessão. Muitas religadas é cabo ou porta USB, não software.

## A câmera SIGMA-W420

É uma webcam USB genérica: aparece no Gerenciador de Dispositivos do
Windows como `SIGMA-W420` em "Câmeras" e não precisa de driver próprio.

Caminho de leitura, em ordem:

1. `CameraServer` do Godot. No Godot 4.6 ele **começa dormindo** e só
   enumera câmeras depois de `set_monitoring_feeds(true)` — sem essa
   chamada a lista volta vazia e o jogo conclui, errado, que não há
   câmera nenhuma.
2. Se o feed nativo não entregar quadro em 2,5 s, cai para a ponte.
3. A ponte tenta `CAP_DSHOW` e depois `CAP_MSMF`. DirectShow abre webcams
   baratas que o Media Foundation recusa; em algumas outras é o
   contrário.

**Validação física pendente.** Nada aqui foi testado com a SIGMA-W420
ligada: o ambiente de desenvolvimento não tem webcam, e o que se provou
foi o caminho do arquivo (modo `--pattern`), a leitura do contador e o
religamento. A confirmação com a câmera de verdade tem de ser feita no
computador do gabinete.
