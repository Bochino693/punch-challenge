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
| `CONFIG` | `CONFIG,<eixo>,<raio>,<vmin>,<amin>` | Configura a medição. |

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
