# Protocolo serial V2 — Punch Challenge

Conversa entre o firmware `arduino/punch_sensor/punch_sensor.ino` e o
jogo em Godot. **115200 bps, 8N1.** Uma mensagem por linha, terminada em
`\n`, campos separados por vírgula, sem espaços.

O firmware **mede**; o jogo **pontua**. O Arduino nunca manda pontos, só
velocidade, aceleração e duração — quem transforma isso em 0 a 999 é a
Central Técnica do jogo, e é por isso que dá para recalibrar uma máquina
sem regravar a placa.

Quem faz o *parse* do lado do jogo é `scripts/arduino_protocol.gd`.
**Linha malformada é descartada ali**, antes de chegar à tela: campo
faltando, número inválido ou valor fora da faixa física viram
`{"type": ""}` e o jogo simplesmente ignora. Um cabo com ruído atrapalha
a medição, mas não faz a máquina pontuar errado.

---

## Placa → jogo

| Mensagem | Formato | Quando |
| --- | --- | --- |
| `READY` | `READY,PUNCH_MPU6050,V2` | Uma vez, no fim do `setup()`. O jogo responde mandando `CONFIG`. |
| `CALIBRATING` | `CALIBRATING,<0-100>` | Durante a medida do repouso, para a tela mostrar o progresso. |
| `CALIBRATED` | `CALIBRATED,<offX>,<offY>,<offZ>` | Fim da calibração. Offsets em g, 3 casas. |
| `PONG` | `PONG` | Resposta ao `PING`. É o sinal de vida da conexão. |
| `BUTTON` | `BUTTON,START` ou `BUTTON,CREDIT` | Botão do gabinete apertado (D2 e D3). |
| `TELEMETRY` | `TELEMETRY,ax,ay,az,gx,gy,gz,vel,pico_g` | A cada 250 ms, **fora** de um golpe. Aceleração em g, giro em °/s. |
| `HIT` | `HIT,<vel_pico>,<accel_pico>,<duracao_ms>,<eixo>` | Um golpe terminou de ser medido. |
| `SATURATION` | `SATURATION,ACCEL` ou `SATURATION,GYRO` | O golpe passou do fundo de escala (±16 g / ±2000 °/s): a medida saiu por baixo do valor real. |
| `ERROR` | `ERROR,<CÓDIGO>` | `NO_MPU`, `MPU_LEITURA`, `PARAM`, `COMANDO_DESCONHECIDO`. |
| `OK` | `OK,<COMANDO>` | Confirmação de `RESET`, `CALIBRATE` e `CONFIG`. |

### Limites aceitos em `HIT`

O jogo rejeita a linha inteira se algum campo cair fora destas faixas —
são limites do que um saco de pancadas consegue fisicamente fazer:

| Campo | Faixa aceita |
| --- | --- |
| velocidade de pico | 0 a 60 m/s |
| aceleração de pico | 0 a 17 g |
| duração | maior que 0 e até 5000 ms |
| eixo | `X`, `Y` ou `Z` |

**Um `HIT` fora da janela do soco não vira ponto.** Se o saco balançar
sozinho, ou alguém encostar nele entre uma partida e outra, a medida
aparece só na linha de diagnóstico da Central Técnica.

---

## Jogo → placa

| Comando | Formato | Efeito |
| --- | --- | --- |
| `PING` | `PING` | Pede um `PONG`. O jogo manda a cada 5 s; sem resposta por 9 s, a tela passa a `SEM RESPOSTA`. |
| `RESET` | `RESET` | Abandona a medição em andamento. |
| `CALIBRATE` | `CALIBRATE` | Remede o repouso. **O saco precisa estar parado.** |
| `TEST` | `TEST` | Devolve um `HIT` sintético (`HIT,7.50,9.20,120,<eixo>`). |
| `CONFIG` | `CONFIG,<eixo>,<raio>,<vmin>,<amin>[,<vmax>]` | Configura a medição. O 5º campo é opcional. |
| `LEDS` | `LEDS,<0..1000>` | Altura da coluna das duas fitas, em por mil. |

### `LEDS` e as duas fitas do gabinete

O gabinete tem duas fitas endereçáveis (WS2812B), uma de cada lado,
subindo. Elas são o placar que se lê do outro lado do salão: ninguém lê
`9610` a dez metros, mas todo mundo vê a coluna de luz subir até o topo e
estourar em branco.

`LEDS,0` a `LEDS,1000` diz a altura da coluna. **Quem manda é o jogo,
enquanto o placar sobe na tela** — assim a fita acompanha o *número
subindo*, e não o golpe cru. As duas coisas no mesmo compasso é o que faz
a máquina parecer uma peça só, em vez de um monitor com uma fita
pendurada do lado. O jogo manda no máximo doze por segundo; a placa
interpola entre um comando e o seguinte, então a subida sai lisa sem
entupir a serial.

**A placa se vira sozinha quando o jogo cala.** Passados 3 s sem `LEDS`,
ela volta a mapear a própria medição entre `vmin` e `vmax` — e é por isso
que o 5º campo do `CONFIG` existe. Com o PC desligado a máquina continua
tendo fita: coluna que sobe no soco, desce devagar, e uma onda lenta de
espera quando não há ninguém. Fita apagada é máquina que parece
quebrada, e ninguém põe ficha em máquina quebrada.

Ligação, e ela importa: dado da fita esquerda em `D5`, direita em `D6`,
cada uma com 330 Ω em série. **Alimentação das fitas por fonte de 5 V
própria, nunca pelo Arduino** — trinta LEDs por fita no brilho máximo
pedem quase dois amperes, e tirar isso do regulador do Uno queima a
placa. O único fio que volta ao Arduino é o **GND**, que precisa ser
comum. Um capacitor de 1000 µF entre +5 V e GND, junto do primeiro LED,
segura o pico da ligada.

Biblioteca: **Adafruit NeoPixel**, pelo Gerenciador de Bibliotecas da IDE
do Arduino. Sem ela o sketch não compila.

### `CONFIG` em detalhe

`CONFIG,X,0.450,0.80,3.50`

| Campo | Unidade | Faixa | O que é |
| --- | --- | --- | --- |
| eixo | `X` `Y` `Z` | — | Eixo do MPU alinhado com a direção do soco. |
| raio | metros | 0,05 a 1,50 | Distância do ponto de giro do saco até onde o soco chega. Entra na estimativa pelo giroscópio (`ω × raio`). |
| vmin | m/s | 0,2 a 20,0 | Abaixo disso a placa nem reporta o golpe. |
| amin | g | 0,5 a 15,0 | Limiar que arma a medição. Sobe se a máquina vibra sozinha; desce se golpe fraco não é reconhecido. |

**Os dois lados validam.** `ArduinoProtocol.build_config` já limita os
valores antes de enviar, e o firmware revalida ao receber, respondendo
`ERROR,PARAM` no que não servir. Uma placa gravada com firmware mais
velho, ou um cabo que corrompeu a linha, não consegue ser configurada
com um raio negativo.

O jogo envia `CONFIG` sozinho em dois momentos: ao receber `READY` e ao
fechar a Central Técnica. O botão **ENVIAR CONFIG** existe para reenviar
à mão quando se troca a placa sem reiniciar o jogo.

---

## Como a placa mede

1. A aceleração dinâmica do eixo escolhido (bruta menos o repouso
   calibrado) passa de `amin` → começa a medição.
2. Enquanto o golpe dura, o firmware **integra** a aceleração a 250 Hz
   para achar a velocidade de pico, e guarda a aceleração máxima.
3. O giroscópio dá uma segunda estimativa: velocidade angular × raio.
4. Vale a maior das duas — a integração perde golpes muito curtos, e o
   giroscópio perde golpes que empurram o saco sem girá-lo.
5. O golpe termina quando a aceleração cai abaixo de 40 % do limiar por
   60 ms, ou aos 400 ms, o que vier antes. Depois há 650 ms de descanso,
   para um soco não ser contado duas vezes.

O sensor mede **velocidade**, não força em newtons nem em quilogramas-força.
A pontuação de 0 a 999 é uma escala de arcade calibrada, não uma medição
de física.

No jogo a velocidade é normalizada entre `vmin` e `vmax`, passa por
`smoothstep` e depois por uma potência configurável. O padrão difícil usa
expoente `2,00`; isso distribui melhor as notas e reserva 900–999 para os
golpes realmente próximos da velocidade máxima.

---

## Diagnóstico rápido

| Sintoma | Onde olhar |
| --- | --- |
| Tela em `PROCURANDO ARDUINO…` | Nenhuma porta serial visível. Cabo, driver CH340/FTDI, ou a extensão `gdserial` não carregou. |
| `AGUARDANDO READY` e não sai dali | Porta abriu, mas nada chega. Confira a velocidade (115200) e se o `.ino` gravado é o V2. |
| `SEM RESPOSTA` depois de funcionar | A placa travou ou o cabo soltou. O jogo continua tentando sozinho. |
| `ERROR,NO_MPU` | O MPU-6050 não respondeu no I2C. Confira SDA em A4, SCL em A5 e a alimentação. |
| `SATURATION` a cada golpe forte | O sensor está no fundo de escala. A medida sai menor que a real: afaste o sensor do ponto de impacto. |
| `TEST` aparece na tela mas o soco real não | O caminho placa → jogo está bom. O problema é o sensor, a fixação dele ou o limiar `amin`. |

## O Arduino não manda pontos

O firmware manda **medida**, o Godot faz a **nota**:

```
HIT,<velocidade_m_s>,<pico_g>,<duracao_ms>,<eixo>
```

Só a velocidade entra na pontuação. O pico de aceleração e a duração
servem para decidir se aquilo foi um soco — validam, não inflam.

Isso não é preciosismo de arquitetura. Com a nota calculada no firmware,
mudar a dificuldade da casa exigiria regravar o Arduino; a curva não
poderia ser desenhada na tela antes de salvar; e duas máquinas com
firmwares de épocas diferentes dariam notas diferentes para o mesmo soco.

### O que o jogo recusa, e por quê

| Recusa | Motivo |
| --- | --- |
| Fora do estado `ARMED` | Abertura, foto, contagem e resultado não pontuam. |
| Segundo `HIT` na mesma rodada | Um soco por rodada. |
| Menos de 900 ms desde o último aceito | O saco balança depois do impacto, e o MPU lê o balanço como uma sequência de eventos menores. |
| Duração abaixo de 12 ms | Um toque, um esbarrão ou um tranco no gabinete duram muito menos que um soco. |
| Pico abaixo da sensibilidade configurada | Idem. O valor sai do assistente de calibração. |

### `SATURATION` não vira 9999

Quando o acelerômetro chega ao fim da escala, ele **parou de medir**. A
máquina não sabe quanto aquele golpe valeu, e chutar o teto seria
inventar um número. A saturação fica registrada na Central Técnica, na
página GOLPE, com a hora — é lá que alguém aumenta a faixa do MPU-6050.

### `BUTTON,START` e `BUTTON,CREDIT`

Os dois botões do gabinete podem chegar pela serial **ou** pela placa
Zero Delay como controle USB. Os dois caminhos passam pelo mesmo
antirrepique de 250 ms e pelas mesmas ações `cabinet_start` e
`cabinet_credit`.

---

## Quando o Arduino "não faz nada"

Quatro problemas dão exatamente o mesmo sintoma — START e CRÉDITO mortos.
A aba **DADOS** da Central (`F9`) separa os quatro em um segundo. Aperte o
botão do gabinete e olhe a linha **`Arduino (D2/D3)`**:

| O que acontece | O que é |
| --- | --- |
| O número **sobe** | Fio, pino e placa certos. Se o crédito não entra, o problema é o modo de operação (LIVRE × 1 FICHA), não o botão. |
| O número **não sobe** e a linha diz `CONECTADO` | O fio ou o pino. START é **D2**, CRÉDITO é **D3**, o outro lado de cada botão vai ao **GND**. |
| Diz `SEM RESPOSTA EM COMx` | Porta errada, e o jogo já está tentando a próxima sozinho. |
| Diz `PROCURANDO ARDUINO…` | O Windows não vê a placa: driver CH340 faltando, ou cabo USB só de carga. |

A linha **`portas vistas`**, logo abaixo, mostra todas as COM que o
Windows anuncia. Se a do Nano não estiver ali, o problema é do driver e
não do jogo.

### Por que o jogo troca de porta sozinha

Um PC de gabinete quase nunca tem uma porta COM só: o Windows inventa
COM3 e COM4 para o Bluetooth, o leitor de cartão traz a dele. O jogo
abria **a primeira da lista** e ficava esperando um `READY` que nunca
chegava — a noite inteira, com os botões mortos.

Agora a lista é uma fila, com as portas de conversor conhecido (CH340,
FTDI, CP210x, Arduino oficial) na frente. Aberta uma porta, o jogo espera
**três segundos** pela apresentação da placa; sem ela, fecha e vai para a
próxima. A que responder fica.

Para fixar uma porta à mão, use **PORTA SERIAL** na aba GOLPE.

### O sketch compila sem a biblioteca das fitas

O `#include` da Adafruit NeoPixel é condicional (`__has_include`). Numa
IDE sem ela instalada o sketch **compila e grava assim mesmo**: o sensor
mede, os botões respondem, e só as fitas ficam apagadas — com um aviso na
compilação dizendo o que instalar.

Isto não é conveniência, é a lição de um defeito real: enquanto o
`#include` era incondicional, a IDE sem a biblioteca **não gerava upload
nenhum**, a placa ficava com o firmware velho, e o sintoma não era "as
fitas não acendem" — era "o Arduino não faz nada".

Antes de qualquer entrega, `sh tools/conferir_firmware.sh` compila o
sketch nas duas situações, fora da IDE, e confere que ele é ASCII puro.

### O vermelho que aparecia a cada gravação

A IDE despejava meia tela de `note: candidate 1 / candidate 2` sobre
`Wire.requestFrom`. **Não era erro** — o sketch compilava e gravava —, mas
também não era ruído inofensivo: era o compilador dizendo que **não sabia
qual das duas funções você quis**.

A biblioteca Wire declara `requestFrom(int, int)` e
`requestFrom(uint8_t, uint8_t)`. Chamando com `MPU_ADDR` (que é um
`#define`, portanto `int`) e um `(uint8_t)` no segundo argumento, nenhuma
das duas é melhor: a primeira precisa promover um argumento, a segunda
precisa converter o outro. Um dia o compilador escolhe a outra, o
endereço vira um `int` truncado, e o defeito aparece como "o sensor parou
de ler" numa máquina que estava boa.

Com os dois argumentos em `uint8_t`, só uma versão serve e a compilação
sai limpa.

E o `conferir_firmware.sh` passou a rodar com `-Werror`: **aviso ali é
erro**. Um aviso que aparece toda vez que se grava a placa é um aviso que
o operador aprende a ignorar — e no meio deles vai o que importava. O
cabeçalho falso do Wire declara as duas versões de propósito, justamente
para essa ambiguidade ser pega aqui e não na sua tela.

---

## A placa nunca trava, nem sem sensor

Isto foi o defeito mais caro que o firmware teve, e explica de uma vez
START morto, CRÉDITO morto e o jogo trocando de porta a noite inteira.

O `setup()` estava assim:

```cpp
if (!mpuVivo()) {
  Serial.println(F("ERROR,NO_MPU"));
  while (true) { pisca o LED; }     // <- para sempre
}
...
Serial.println(F("READY,..."));     // <- nunca chegava aqui
```

Sem o MPU-6050 respondendo, a placa entrava num laço infinito **antes de
chegar ao `loop()`**. `processarBotoes()` nunca rodava — e um problema no
sensor derrubava junto os botões, a serial e as fitas, três coisas que
não dependem dele para nada. O `READY` também nunca saía, então o jogo
nunca reconhecia a porta.

Agora:

- o **`READY` sai primeiro**, antes de tocar no sensor;
- sem sensor a placa **continua no ar** — botões, crédito, serial, fitas;
- ela **tenta o sensor de novo a cada 2 s** e manda `OK,MPU` quando ele
  aparece, então um fio de I2C encaixado de volta volta a funcionar sem
  desligar nada;
- o LED de D13 pisca enquanto faltar sensor.

E o sensor é procurado nos **dois endereços** (0x68 e 0x69 — o AD0 solto
de muitos clones flutua) aceitando **qualquer `WHO_AM_I`** que não seja
0x00 nem 0xFF. Metade dos módulos vendidos como MPU-6050 é MPU-6500,
MPU-9250 ou ICM-20608, devolve 0x70/0x71/0x73/0x98 e mede igual: exigir
0x68 era reprovar hardware bom.

### `READY` não quer mais dizer "sensor presente"

São duas coisas diferentes agora, e a aba **DADOS** mostra as duas
separadas. Quem desliga a simulação de bancada é o **`OK,MPU`** ou o
primeiro golpe medido — nunca o `READY`. Se fosse o `READY`, uma máquina
sem sensor perderia a barra de espaço e não sobraria jeito nenhum de
jogar nela.

---

## "Funciona no meu PC e não no outro"

Este sintoma quase nunca é o fio. São três causas, em ordem de
frequência, e a aba **DADOS** da Central separa as três:

**1. A extensão nativa da serial não veio junto.** A conversa com o
Arduino depende da `gdserial` — um `.dll` que viaja ao lado do
executável. No computador de quem desenvolve ele está sempre lá, então o
defeito nunca aparece ali: aparece no PC novo, e o sintoma é "não
funciona nada", com START e CRÉDITO mortos e o sensor mudo.

A Central agora diz isso em vermelho: `extensão serial: NÃO CARREGOU`.
Antes ela falhava calada, e quem estava do outro lado procurava fio solto
durante horas por causa de um arquivo.

Antes de exportar, `sh tools/conferir_exportacao.sh` confere que todos os
binários declarados existem.

**2. O driver da placa não está instalado.** Clones de Nano usam o
conversor **CH340**, que o Windows não traz de fábrica. Sem o driver a
porta COM nem aparece — e a Central mostra `portas vistas: nenhuma`.

**3. O Nano reinicia ao apertar o botão** (o Windows toca o som de
desconexão). Isto é elétrico, não é software: ou o botão está fechando
**5 V no GND** em vez de **D2 no GND**, ou o 5 V do Nano está ligado ao
5 V da fonte das fitas e as duas fontes brigam. Num PC de mesa a USB
aguenta e o defeito não aparece; num notebook, não aguenta.

---

## O jogo NÃO precisa de Python

Só a **ponte de câmera** precisa, e ela é a segunda opção. O jogo tenta
primeiro o caminho **nativo**, que não exige nada instalado; a ponte só
entra se esse caminho não provar que entrega imagem de verdade (há uma
checagem de contraste: feed preto é reprovado em dois segundos e meio).

Num PC recém-formatado, sem Python e sem nada:

| O que | Funciona? |
| --- | --- |
| START, CRÉDITO, sensor de soco, fitas de LED | **Sim**, sempre |
| Ranking, pontuação, som, todas as telas | **Sim**, sempre |
| Foto pela câmera nativa | Sim, se o Windows entregar imagem |
| Foto pela ponte | Só com Python + OpenCV |

Sem foto, o ranking mostra a silhueta desenhada e o jogo segue inteiro.

---

## Se o `git pull` entrar num laço "Unlink failed"

```
Unlink of file 'addons/gdserial/bin/windows-x86_64/~gdserial.dll' failed.
Should I try again? (y/n)
```

Responder `y` não resolve nunca — o arquivo está **travado**, e vai
continuar travado enquanto quem o travou estiver no ar.

**Saída:**

1. digite `n` e Enter (ou `Ctrl+C`) para abortar;
2. **feche o editor do Godot** e qualquer `PunchChallenge.exe` rodando;
3. `git pull` de novo.

**Por que acontece.** No Windows não dá para sobrescrever uma DLL que
está carregada. Quando o editor do Godot precisa recarregar uma extensão,
ele copia a atual para um nome com `~` na frente e usa a cópia — então
`~gdserial.dll` **nasce sozinho** ao abrir o projeto e fica preso ao
processo do editor. O `git` tenta apagá-lo, o Windows recusa, e o git
pergunta em laço.

O arquivo está no `.gitignore` desde a BUILD 43: ele continua nascendo na
máquina de quem desenvolve, mas não entra mais no repositório e não
atrapalha mais nenhum `pull`.
