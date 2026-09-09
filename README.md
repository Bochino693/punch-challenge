# Punch Challenge

Máquina de soco da **Lazer & Sport Brinquedos**: jogo em Godot 4 e
firmware Arduino com sensor MPU-6050 no saco. O sensor mede a
velocidade do golpe; o jogo transforma em pontuação de arcade, mostra o
número subindo e dá o veredito.

## Tela em pé

O jogo é desenhado para **1080 × 1920 (vertical)**. A máquina é um
armário alto com o saco na frente: quem joga olha para cima, não para os
lados. Numa tela deitada, metade da largura seria moldura vazia e o
número da pontuação ficaria pequeno justamente para quem está a três
metros de distância. Em pé, a leitura desce em coluna — saco, número,
veredito — que é a ordem em que a pessoa procura.

Para montar:

1. Gire o monitor fisicamente (suporte VESA em retrato).
2. No Windows: **Configurações → Sistema → Vídeo → Orientação da tela →
   Retrato**. Confira qual dos dois retratos deixa a imagem na posição
   certa para o seu suporte.
3. O jogo abre em tela cheia; nada mais a ajustar.

Para testar no PC do escritório, sem girar o monitor, a janela abre em
540 × 960 (`window_width_override` no `project.godot`) — a proporção é a
mesma, só menor.

### Tema arena neon

O jogo combina o azul e vermelho da Lazer & Sport com uma arena
marinho/preta, painéis tecnológicos e luzes ciano, magenta, verde e âmbar.
O contraste mantém o placar legível a distância e aproxima a apresentação
das máquinas modernas de boxe com câmera e ranking visual.

Todas as cores moram em `scripts/paleta.gd`. Fundo, alvo, placar,
moldura e textos leem de lá, então o tema é uma coisa só — mudar a cara
do jogo é mexer num arquivo, e não caçar hexadecimal em seis.

Dois detalhes que só existem porque o tema é claro:

- **Lâmpada em vez de ponto de luz.** Um LED desenhado como brilho
  difuso some num fundo claro. Cada bulbo tem corpo pintado e aro
  escuro, então a apagada também se vê — e é a fieira inteira que faz o
  olho ler "letreiro".
- **Clarão em âmbar, com as bordas escurecendo.** Lavar a tela de branco
  não funciona sobre quase-branco. O golpe acende em âmbar e escurece as
  bordas ao mesmo tempo: o que o olho lê como flash é o contraste.

### Acabamento de fliperama

A referência é máquina de salão de verdade (PUNCH & KICK, KUNG FU): o que
faz aquilo parecer equipamento caro, e não desenho, são três coisas — e
as três estão aqui.

**A entrada abre com o selo da casa.** Um quadrado pequeno com o
logotipo da Lazer & Sport, placa vermelha, borda de ouro e um brilho
atravessando — e só depois vem o soco que faz nascer o emblema do jogo.
Antes a máquina abria com o logotipo comprido sobre um fundo azul-marinho
que não tinha parentesco nenhum com o resto, e a troca para o emblema
parecia defeito. Agora a tela de arranque do Godot usa o mesmo selo e o
mesmo chão escuro, então o arranque e a entrada são a mesma coisa
continuando.

**O que voa não é confete.** Um retângulo girando é festa de
aniversário; o que sai de uma pancada é brasa, e brasa tem rastro. A
comemoração é feita de brasas explodindo do ponto do impacto, raios
girando junto e anéis em sequência — mais um ESTRELÃO de história em
quadrinhos que abre no lugar do golpe, com rachaduras e riscos
convergindo. Ele dura quatro décimos de segundo e é o desenho que diz
"bateu" antes de qualquer número aparecer.

**A tela de jogo tem três papéis de texto, e só três.** Título (letreiro
com contorno, o mesmo da abertura), rótulo (26 px, o que nomeia um
número) e apoio (22 px, a letra miúda de quem quiser conferir). Antes
cada linha escolhia o próprio corpo na hora — 25, 26, 30, 32, 34, 46 — e
metade era texto cru, sem contorno, sobre um painel que muda de cor a
cada faixa.

**O visor é UM SÓ, o jogo inteiro.** Uma máquina de fliperama tem um
painel, e é para ele que a pessoa olha do começo ao fim. Aqui é a mesma
peça em todos os momentos, e só muda o que está escrito dentro: traços
piscando enquanto a máquina espera o soco, os pontos da carga enquanto se
segura a barra, e a pontuação subindo no fim. O anel de sessenta marcas
em volta muda de papel junto: corre em três marcas quando está esperando,
enche com a carga quando alguém simula pelo teclado, e enche com a
PONTUAÇÃO na contagem — nunca com o relógio.

**Não há saco de pancadas desenhado.** O saco é a peça física que a
pessoa tem na frente do corpo; um segundo saco na tela dividia a atenção
entre dois alvos, e o de pixel não é o que se acerta. No lugar dele, a
tela de espera acende um FAROL: anéis saindo do visor, sempre para fora,
chamando o punho para onde o número vai nascer.

**O visor de sete segmentos** (`scripts/visor_led.gd`). Não é fonte: é
segmento a segmento. O que faz o olho reconhecer um painel de LED não é
o formato do algarismo, é o **segmento apagado** — num visor de verdade
os sete traços estão sempre lá, e os que não fazem parte do número ficam
visíveis, escuros. Nenhuma fonte dá isso. Cada traço aceso ainda leva um
miolo quase branco, porque um LED aceso estoura no centro e guarda a cor
só na borda.

**A letra de fliperama** (`_letreiro`). Três passadas sobre a mesma
palavra: um contorno grosso quase preto, que segura a letra sobre
qualquer fundo; a palavra alguns pixels acima num tom claro, cujo
resquício virando por cima da borda faz o brilho do topo (o Godot
desenha texto de uma cor só, então o degradê é simulado assim); e o
preenchimento. Com halo, entra antes um contorno largo e transparente na
cor de destaque.

### Como a tela se organiza

A tela é dividida em **bandas horizontais fixas**, declaradas no topo de
`scripts/main.gd` (`BANDA_TOPO`, `PALCO_*`, `LEITURA_*`, `CARTOES_Y`,
`RODAPE_Y`). Cada coisa desenhada mora dentro da sua banda:

```
  0 –  150   cabeçalho: marca do jogo e modo de operação
168 – 1104   alvo: o visor, o farol e o campo de força
1124 – 1580  leitura: número, veredito e convite
1608 – 1740  cartões: recorde, partidas, créditos
1876         rodapé: assinatura da casa
```

Enquanto tudo respeitar a sua banda, nada se sobrepõe. Textos que podem
crescer (o veredito, valores de configuração) passam por
`_texto_cabendo`, que **mede a palavra e encolhe o corpo até caber** —
`PESO-PESADO` e `FRACO!` ocupam o mesmo lugar sem um estourar a tela nem
o outro ficar pequeno.

## Como a máquina se comporta

```
ABERTURA → (START) → ENTRADA → 3, 2, 1 → SENSOR ARMADO → IMPACTO → RESULTADO
```

**Abertura: quatro telas, alternando sozinhas.** Uma máquina parada não
fica repetindo o mesmo cartaz — ela conta o jogo em capítulos, e é o
rodízio que segura quem passa no corredor por tempo suficiente para
decidir jogar. A cada sete segundos troca entre:

1. **A marca** — a logo da casa montada como letreiro, o nome do jogo e
   o recorde a bater, no mesmo medalhão que o jogo usa.
2. **Melhores da casa** — as cinco marcas, com ouro, prata e bronze.
3. **Como jogar** — os três passos, do tamanho de quem lê de longe.
4. **Você no ranking** — prévia da câmera e explicação das fotos locais.

O convite e os números da máquina ficam FIXOS nas três, porque não podem
depender de a pessoa ter chegado na página certa. Sem crédito no modo
ficha, o convite troca de texto em vez de sumir — quem chegou perto
precisa saber o que fazer.

**START entra no jogo.** Em modo ficha, o crédito é debitado aqui; em
modo livre, START entra direto.

**A máquina ESPERA o soco, e não cobra a espera.** Não há relógio na
tela nem barra esvaziando: o jogo fica armado, com o farol chamando, até
o golpe chegar. Existe um limite de noventa segundos, para a máquina não
passar a tarde armada se a pessoa foi embora — e, ao fim dele, **o
crédito é devolvido**. Nos últimos quinze segundos a tela avisa que vai
voltar e diz, na mesma linha, que a ficha volta junto. Antes a janela era
de oito segundos e a rodada morria com o crédito já debitado: quem
hesitou pagou e não jogou.

**O GOLPE VEM DO SENSOR, E DE MAIS NADA.** O MPU-6050 mede e manda
`HIT,<velocidade>,<pico_g>,<duração_ms>,<eixo>`; o Godot valida e calcula
a nota. O Arduino nunca manda pontos. A barra de espaço é um **simulador
de bancada** com chave própria na Central: em salão ela não pontua e a
tela nem a menciona — anunciar um atalho que, se existisse, seria fraude
é pior do que não ter o atalho.

**O resultado tem OITO NÍVEIS**, de 0000 a 9999, e cada um tem
apresentação própria — cor, animação, partículas, tremor e som:

| Pontos | Nível | O que a tela faz |
| --- | --- | --- |
| 0–1799 | `IMPACTO LEVE` | pulso pequeno, poucas faíscas, som seco, sem tremor |
| 1800–3999 | `BOM GOLPE` | dois anéis vermelhos, riscos e som de couro com grave leve |
| 4000–6499 | `GOLPE FORTE` | explosão radial amarela, brasas, tremor médio, grave encorpado |
| 6500–7999 | `EXPLOSIVO` | flash branco, rachaduras no ponto do golpe, onda dupla e subgrave |
| 8000–8999 | `NOCAUTE` | hit-stop de 95 ms, zoom de impacto, três ondas e sirene curta |
| 9000–9699 | `PESO-PESADO` | túnel de luz, brasas densas, câmera sacudindo e fanfarra |
| 9700–9998 | `LENDÁRIO` | o palco inteiro reage, raios dourados e música de vitória |
| 9999 | `SOCO PERFEITO` | congelamento de 360 ms, explosão branca e dourada, coro |

As faixas são **fixas** e moram numa tabela só (`scripts/fx/score_tier.gd`).
Elas descrevem o espetáculo, não a dificuldade: quem decide quanta gente
chega a cada nível é a **curva**, pela velocidade mínima, máxima e pelo
expoente. Um teste recusa duas receitas de efeito iguais — oito níveis
escritos como oito blocos de `if` viram dois níveis com a mesma animação
e só o texto mudando, e é isso que a pessoa que joga duas vezes seguidas
percebe.

**A contagem é o suspense.** O número sobe de zero até a pontuação em
cerca de dois segundos, com tique a cada passo e a coluna de potência
acompanhando. O veredito só entra quando a contagem termina — é o
momento pelo qual o cliente pagou.

## O que já está pronto

- Interface vertical em 1080 × 1920, adaptável para outras resoluções.
- Abertura com a marca da casa, efeito de luz, partículas, convite
  piscando e os três passos de como jogar.
- Saco de pancadas desenhado em código, com volume de cilindro, corrente
  de elos até o teto do gabinete, amassado no impacto e balanço limitado
  a 20° — o saco reage ao soco sem sair do enquadramento.
- Medidor de potência com escala numerada, as três zonas coloridas da
  máquina e o traço do recorde da casa.
- Tema de arena neon inteiro num arquivo só (`scripts/paleta.gd`).
- Medalhão com visor de sete segmentos, anel-relógio e rótulo curvo,
  compartilhado por todos os momentos da partida.
- Letras de fliperama com contorno grosso, brilho de topo e halo.
- Ícones desenhados em código (`scripts/icones.gd`): troféu, luva, ficha,
  raio, alvo, botão e estrela. Sem arquivo de imagem — não somem se
  faltar um PNG, não serrilham em outra resolução e mudam de cor junto
  com a faixa do golpe.
- A marca da casa montada como letreiro de parque: placa creme, moldura
  marinho e lâmpadas correndo em volta.
- Contagem regressiva animada `3, 2, 1` e tela de espera que aguarda o soco sem consumir a ficha.
- Pontuação de 0000 a 9999 baseada em curva gradual `smoothstep + gamma`.
  O padrão difícil usa expoente `2,00`; o cálculo antigo com `0,8`, que
  favorecia demais golpes médios, não é mais utilizado.
- Oito níveis de golpe, cada um com cor, animação, partículas, tremor e som próprios.
- Ranking das cinco melhores marcas, persistente, com foto local do
  jogador quando a câmera está disponível e com a posição
  conquistada anunciada no fim da rodada. Cinco e não uma: com recorde
  único, quem não bate o recorde não ganha nada, e o recorde de uma
  máquina movimentada fica inalcançável em uma semana — entrar em quinto
  ainda é entrar, e é essa vitória pequena que vende a segunda ficha.
  Quem já tinha um recorde salvo não o perde: ele vira a primeira linha.
- Número total de partidas e saldo de créditos persistentes.
- Estatísticas diárias locais: partidas, média, melhor marca, faixas de
  força e entradas no Top 5.
- Modo Livre ou 1 Ficha selecionável na Central Técnica.
- `START`: entra no jogo e joga de novo depois do resultado.
- `SELECT`: adiciona um crédito.
- `F9`: abre e fecha a Central Técnica.
- `ESC`: fecha a configuração ou cancela uma rodada sem travar a interface.
- Seleção de porta serial, teste do sensor e envio de configuração ao firmware.
- Ícone, abertura e identificação próprios — sem símbolo padrão do Godot.

## Hardware

- Arduino Nano ou Uno (ATmega328P).
- **MPU-6050** (acelerômetro + giroscópio) fixado no saco, no I2C.
- Placa USB Zero Delay para os botões arcade, ou os botões direto na placa.

### Ligação

| MPU-6050 | Arduino |
| --- | --- |
| VCC | 5 V (ou 3,3 V, conforme o módulo) |
| GND | GND |
| SDA | A4 |
| SCL | A5 |
| AD0 | GND (endereço 0x68) |

| Botão do gabinete | Arduino |
| --- | --- |
| START | D2 → GND |
| CREDIT / SELECT | D3 → GND |

Os botões usam o `INPUT_PULLUP` interno: ligam direto no GND, sem
resistor externo. Quem preferir uma placa USB Zero Delay em vez dos
pinos do Arduino tem o caminho alternativo pronto: as ações
`input_start` e `input_credito` do `project.godot` já respondem a botões
de controle (por padrão, os índices 6 e 4). Cada placa numera os botões
de um jeito, então confira o índice da sua em **Projeto → Configurações
do Projeto → Mapa de Entrada**. O cabo do sensor deve ficar afastado de motor,
solenoide e cabos de potência. Em máquina com ruído elétrico, use fonte
estabilizada, aterramento correto e cabo de sinal blindado.

## Instalação

1. Grave `arduino/punch_sensor/punch_sensor.ino` no Arduino a 115200 bps.
2. Abra `project.godot` no Godot 4.4 ou mais recente (a extensão serial
   `gdserial` exige 4.4).
3. Execute o projeto e pressione `F9`.
4. Escolha a porta serial e pressione **RECONECTAR**.
5. Balance o saco: a linha de diagnóstico deve mostrar telemetria.

Sem a extensão serial, ou sem Arduino, o jogo continua funcionando em
**modo simulação** — nada trava por falta de hardware.

### Câmera no Windows

O `CameraServer` do Godot não fornece webcam no Windows. Por isso o projeto
inclui `tools/camera_bridge.py`, uma ponte local por OpenCV. Instale uma vez:

```powershell
py -m pip install -r tools/requirements-camera.txt
```

O jogo inicia e encerra a ponte automaticamente. As imagens ficam somente
em `user://ranking_photos`; não há envio para internet nem reconhecimento
facial. Sem Python, OpenCV, permissão ou webcam, aparece um avatar e todo o
restante do jogo continua funcionando.

## Central Técnica (F9)

| Seção | Para quê |
| --- | --- |
| **Modo de operação** | Livre ou 1 ficha por partida. |
| **Botões do gabinete** | Mapeamento da placa Zero Delay: aperte o botão de verdade e o jogo grava controle, índice e nome. Um contador por botão prova que pegou. |
| **Simulação de bancada** | A chave que libera a barra de espaço. Desligada de fábrica. |
| **Velocidade e dificuldade** | Mínima, máxima, expoente e zona morta — com a curva desenhada. |
| **Os oito níveis** | Régua de leitura. Mostra a desproporção real: os quatro níveis de cima ocupam um quinto da escala. |
| **Assistente de calibração** | Mede a máquina em quatro passos em vez de regular por tentativa e erro. |
| **Sensor e firmware** | Porta serial, eixo do golpe, raio do braço, sensibilidade e envio de configuração. |
| **Câmera e som** | Prévia ao vivo, troca de câmera, foto de teste, volumes de trilha e efeitos, soco de teste. |
| **Dados** | Ranking, estatísticas, telemetria, contadores dos botões e o que apagar. |

A Central tem **quatro páginas**, e um controle só responde na página
aberta: os retângulos continuam existindo quando não estão desenhados, e
botão invisível que responde é a pior espécie de defeito.

Cada par `−` / `+` sai da tabela `PASSOS` no topo de `scripts/main.gd`: o
mesmo retângulo desenha o botão e confere o clique, e o valor é
desenhado **no espaço livre entre os dois** — não há como um número
cobrir uma área de toque.

## Calibração da pontuação

Use o **assistente**, na Central Técnica → GOLPE → *Assistente de
calibração*. Quatro passos:

1. **Repouso** — não encoste no saco por quatro segundos. Mede o ruído do
   sensor parado, que é o piso da sensibilidade.
2. **Cinco golpes fracos** — bata de leve, como quem testa.
3. **Cinco golpes fortes** — bata com tudo, como o melhor cliente da noite.
4. **Sugestão** — velocidade mínima, máxima e sensibilidade, cada uma com
   o motivo escrito ao lado, e a curva **desenhada** antes de salvar.

A conta usa **percentis**, não mínimo e máximo: em cinco socos, um
escorrega no saco e outro pega de raspão, e com o extremo a calibração
inteira dependeria do pior e do melhor golpe do dia. O piso desce 15 %
abaixo do percentil 20 dos fracos, para quem bate de leve ver *algum*
ponto; o teto sobe 8 % acima do percentil 80 dos fortes, para 9999
continuar raro — se o teto fosse o golpe mais forte já medido, o primeiro
cliente forte zeraria o desafio na primeira noite.

Salvando, os valores vão para a máquina **e** para o firmware do sensor.

Parâmetros de fábrica: mínima `1,2 m/s`, máxima `16,0 m/s`, zona morta
`8 %`, expoente `γ 2,80`.

## Teste sem Arduino

Ligue a chave **SIMULAÇÃO DE BANCADA** na Central (página OPERAÇÃO), ou
rode o jogo com `PUNCH_SIMULACAO=1` no ambiente. Com ela ligada:

- **segure a barra de espaço para carregar e solte para socar** — o visor
  mostra, a cada instante, exatamente quantos pontos sairão;
- `1` / `Enter` fazem o papel do START e `5` / `C` adicionam crédito.

Desligada — que é como ela sai de fábrica — nada disso responde, e a tela
não menciona teclado nenhum. Num salão, a barra de espaço ligada é
qualquer pessoa tirando 9999 sem encostar no equipamento, e um teclado
esquecido no armário vira crédito de graça.

A Central mostra a chave em **vermelho** quando está ligada, com o aviso
`DESLIGUE ANTES DE ABRIR O SALÃO`.

Com o Arduino ligado, o botão **TESTAR SENSOR** (ou a tecla `T` na
Central) pede um golpe sintético à placa: se ele aparece na tela e o
soco real não, o problema é o sensor, e não o software.

## Conferir a tela sem abrir o editor

```
godot --path . --script tools/capturar_telas.gd
```

Percorre todos os momentos do jogo — abertura, contagem, sensor armado,
carga, impacto, contagem do placar, os três vereditos e a Central
Técnica — e salva um PNG de cada um em `.telas/` (ou na pasta apontada
por `PUNCH_SHOTS`). É como se confere que nada saiu da sua banda depois
de mexer no traçado.

## Exportação Windows

O preset já está incluído. No Godot, instale os templates de exportação e
use **Projeto → Exportar → Windows Desktop**. O executável será criado em
`build/PunchChallenge.exe` com o pacote incorporado.

## Refazer o ícone do aplicativo

```
python3 tools/gerar_icone.py
```

Redesenha `assets/icon.png` (512 × 512) a partir da mesma silhueta de
luva que `scripts/icones.gd` usa no jogo — a luva da barra de tarefas e
a luva do cartão de PARTIDAS são reconhecidamente a mesma coisa. Só
depende do Python padrão; não há dependência de imagem para instalar.

## Documentação

- `docs/PROTOCOLO_SERIAL.md` — todas as mensagens entre placa e jogo,
  os limites aceitos e um guia de diagnóstico.

## Segurança mecânica

Instale batentes, proteções e amortecimento adequados para impedir que o
mecanismo alcance o operador. O sensor e o Arduino não substituem
proteções físicas, parada de emergência nem projeto mecânico seguro.
