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
