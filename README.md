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

Todas as cores moram em `scripts/paleta.gd`. Fundo, saco, medidor,
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

**O medalhão.** Uma máquina de fliperama tem UM visor, e é ele que a
pessoa olha o jogo inteiro. Aqui é a mesma peça em todos os momentos, e
só muda o que está escrito dentro: `3, 2, 1` na contagem, os pontos da
carga enquanto se segura a barra, traços piscando no impacto e a
pontuação subindo no fim. Quatro faixas concêntricas, sem uma invadir a
outra: raios girando por fora, o anel de faixa (que é o relógio — enche
na contagem do placar e esvazia nos oito segundos do soco), o bisel e o
vidro. O rótulo é serigrafado em curva na faixa, como no painel real.

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

Fora isso: o vinil do saco ganhou uma faixa de verniz estreita e quase
branca — é o risco de luz que separa vinil de feltro — e o medidor ganhou
o mesmo bisel marinho do visor, para as duas peças de instrumento da
tela parecerem o mesmo equipamento.

### Como a tela se organiza

A tela é dividida em **bandas horizontais fixas**, declaradas no topo de
`scripts/main.gd` (`BANDA_TOPO`, `PALCO_*`, `LEITURA_*`, `CARTOES_Y`,
`RODAPE_Y`). Cada coisa desenhada mora dentro da sua banda:

```
  0 –  150   cabeçalho: marca do jogo e modo de operação
168 – 1104   palco: o saco e o medidor de potência
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

**A janela do soco é de oito segundos**, mostrada por uma barra que
esvazia e fica vermelha no fim — sem número para ninguém precisar ler.

**Carregando, o visor mostra o VALOR EXATO.** Enquanto a barra de espaço
está pressionada, o número grande na tela e a coluna do medidor mostram
quantos pontos o golpe vale *se soltar agora* — não a fração do tempo
segurado. A conversão de tempo em pontos é uma curva, então uma barra
proporcional ao tempo mostraria 60 % quando o golpe valeria 640. É a
mesma chamada de `ScoreCurve.points_from_charge` que o placar usa depois, e
por isso o número prometido e o número pago não têm como divergir.

**O resultado tem três faixas**, e é isso que faz o cliente jogar de novo:

| Faixa | Padrão | O que a tela faz |
| --- | --- | --- |
| **Forte** | 700 a 999 | `NOCAUTE!`, `PESO-PESADO` ou `LENDÁRIO` — confete, fogos, tremor e clarão. |
| **Média** | 330 a 699 | `BOM GOLPE` ou `GOLPE FORTE` — âmbar, faíscas e anéis pulsando. |
| **Fraca** | 0 a 329 | `FRACO!` ou `GOLPE LEVE` — cinza, estilhaços caindo. |

Os dois limites são ajustáveis na Central Técnica: a mecânica de cada
máquina responde diferente, e uma faixa errada faz todo mundo ganhar (ou
todo mundo perder), que é o jeito mais rápido de esvaziar a fila. A
mesma faixa manda na cor da moldura de LEDs, nas zonas do medidor e na
cor do veredito — os três nunca discordam sobre o que é um golpe forte.

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
- Contagem regressiva animada `3, 2, 1` e janela de oito segundos para o golpe.
- Pontuação de 0 a 999 baseada em curva gradual `smoothstep + gamma`.
  O padrão difícil usa expoente `2,00`; o cálculo antigo com `0,8`, que
  favorecia demais golpes médios, não é mais utilizado.
- Sete vereditos, distribuídos pelas três faixas ajustáveis.
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
| **Faixas do placar** | Os dois limites que separam fraco, médio e forte. A régua colorida acima muda na hora — o técnico regula olhando o resultado. |
| **Velocidade que vira ponto** | Velocidades mínima/máxima e expoente da curva gradual. |
| **Sensor e firmware** | Porta serial, eixo do golpe, raio do braço e sensibilidade. |
| **Ações no firmware** | Enviar configuração, testar sensor, câmera e fotografia. |
| **Diagnóstico** | Telemetria, estatísticas, ranking, fotos e reconexão. |

Cada par `−` / `+` sai da tabela `PASSOS` no topo de `scripts/main.gd`: o
mesmo retângulo desenha o botão e confere o clique, e o valor é
desenhado **no espaço livre entre os dois** — não há como um número
cobrir uma área de toque.

## Calibração da pontuação

1. Na Central Técnica, deixe a mínima em `0,8 m/s`, a máxima em `12,0 m/s`
   e a curva difícil em `γ 2,00`.
2. Faça dez golpes leves e anote aproximadamente as velocidades
   (aparecem na linha de diagnóstico).
3. Faça dez golpes fortes com segurança e anote o maior valor repetível.
4. Use como mínima o valor de um golpe fraco verdadeiro.
5. Use como máxima o maior golpe que a mecânica suporta de forma repetível.

Depois disso, ajuste as faixas em **ATÉ AQUI É FRACO** e **DAQUI É
FORTE**. Uma referência que costuma funcionar em máquina nova é deixar a
criança tirando "médio" e o adulto empenhado tirando "forte" — se todo
mundo estiver tirando nocaute, suba o limite; se ninguém conseguir,
desça.

## Teste sem Arduino

Durante a janela do soco, **segure a barra de espaço para carregar e
solte para socar**: quanto mais tempo segura, mais forte o golpe. O
número grande na tela mostra, a cada instante, exatamente quantos pontos
sairão se você soltar naquele momento. A carga máxima exige cerca de
`2,8 s`; sensor e teclado passam pela mesma curva. Fora da janela, a barra de espaço
faz o papel do START. `C` adiciona crédito e `F9` abre a Central Técnica.

Essas instruções só aparecem no rodapé **quando o sensor não está
conectado** — ou seja, na bancada de montagem. Com o Arduino no lugar, o
cliente nunca vê instrução de teclado numa máquina de ficha.

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
