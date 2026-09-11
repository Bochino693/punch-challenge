# Quando a máquina não acha o Arduino

Este arquivo existe para separar **etapas que costumam ser confundidas
numa só**. "Conectado" não prova que o sensor funciona, e "a placa Zero
Delay funciona" não prova que a serial do Arduino está certa — são
circuitos diferentes, e a Zero Delay nem passa por serial.

Percorra na ordem. Pare na primeira etapa que falhar: as seguintes só
fazem sentido depois dela.

---

## 1. O Windows enumera a COM?

Gerenciador de Dispositivos → **Portas (COM e LPT)**. Tem de aparecer um
item com um número de COM.

- **Não aparece nada** → é driver ou cabo, e não o jogo. Cabo de carga
  sem fios de dados é a causa mais comum; depois, o driver CH340 (clones
  de Nano) ou FTDI.
- **Aparece com triângulo amarelo** → driver. Instale o do chip USB da
  sua placa.

Anote o número: `COM3`, `COM5`, o que for. Ele muda de PC para PC — é por
isso que a porta fixa da Central é **preferência, não cadeado**.

## 2. O Arduino responde sozinho, sem o jogo?

**Com o jogo fechado**, abra o Monitor Serial da IDE do Arduino na porta
da etapa 1, em **115200**.

Tem de aparecer, em segundos:

```
READY,PUNCH_MPU6050,V9
CALIBRATING,0
...
CALIBRATED,-0.01,0.02,1.00
```

- **Nada** → baud errado, firmware não gravado, ou a porta é outra.
- **Caracteres embaralhados** → baud errado. Confira que está em 115200.
- **`READY` mas nenhum `CALIBRATED`** → veja a etapa 4.

> O `READY` sai **antes** de a placa procurar o sensor, de propósito.
> Ele prova que a **placa** está lá. Não prova sensor nenhum.

## 3. O jogo acha um caminho até a placa?

Abra o jogo e a Central Técnica (**F9**). A linha "caminho até a placa"
diz qual dos dois está em uso:

- `ponte PowerShell` ou `extensão nativa` → há caminho. Vá para a 4.
- `NENHUM` → **é esta a etapa que falha.** Duas causas, nesta ordem:

  **a) Falta o Visual C++ Redistributable.** A extensão nativa
  (`addons/gdserial/bin/windows-x86_64/gdserial.dll`) importa
  `VCRUNTIME140.dll`, que **não faz parte do Windows** — vem do
  *Visual C++ 2015-2022 Redistributable (x64)*, da Microsoft. O PC de
  quem desenvolve quase sempre já tem, porque o Godot e outras
  ferramentas o instalam. Um PC limpo pode não ter, e aí o Windows nem
  carrega o `.dll`.

  Confira no PowerShell:

  ```powershell
  Test-Path C:\Windows\System32\VCRUNTIME140.dll
  ```

  `False` → instale o redistribuível **x64** da Microsoft e reabra o
  jogo.

  **b) O PowerShell está barrado.** A ponte usa o PowerShell, que existe
  em todo Windows 10/11. Uma política de rede ou de grupo pode barrá-la.
  Confira:

  ```powershell
  powershell -NoProfile -Command "[System.IO.Ports.SerialPort]::GetPortNames()"
  ```

  Tem de listar as COM da etapa 1.

> Não desative o Defender e não crie exclusões para resolver isto. Se o
> antivírus estiver barrando, o caminho certo é tratar com quem
> administra a máquina, não contornar.

## 4. O sensor (MPU-6050) está pronto?

Na Central, a telemetria mostra a aceleração **dinâmica** — já sem a
gravidade. Com a máquina parada, os três números têm de ficar **perto de
zero**, oscilando pouco.

- `ERROR,NO_MPU` ou "SEM SENSOR" → fio de I2C. Confira **A4 = SDA** e
  **A5 = SCL**, mais 3,3 V/5 V e GND. A placa segue funcionando sem o
  sensor de propósito: botões, START e crédito continuam vivos.
- Números **longe de zero com a máquina parada** → a base nasceu torta.
  Aperte **CALIBRAR** na Central com a máquina **imóvel**. Se o firmware
  responder `ERROR,CALIB_MOVIMENTO`, é porque ele detectou movimento e
  **se recusou** a gravar um zero ruim — espere tudo parar e repita.

## 5. O sensor parado gera soco?

Deixe a máquina parada por **cinco minutos** com o jogo armado.

Nenhum `HIT` pode aparecer. Se aparecer, volte à etapa 4: é a base, e não
o limiar.

## 6. O soco chega ao jogo?

Na Central, **TESTAR** manda a placa emitir um golpe sintético
(`HIT,2.60,8.00,45,X`). Se ele aparece na tela e o soco real não, o
problema é **mecânico ou de sensor**, não de comunicação.

---

## Exportar e levar para outro PC

1. No Godot: **Projeto → Exportar → Windows Desktop → Exportar Projeto**.
2. Leve a pasta inteira do `.exe` (o `.pck` vai embutido, mas leve a
   pasta toda mesmo assim).
3. **No PC de destino, instale o Visual C++ 2015-2022 Redistributable
   (x64)** antes do primeiro teste. É a etapa 3a, e é a diferença entre
   "funciona no meu PC" e "funciona em qualquer PC".
4. Grave o firmware `arduino/punch_sensor/punch_sensor.ino` na placa pela
   IDE do Arduino (placa Uno ou Nano, 115200). A biblioteca
   **Adafruit NeoPixel** é opcional: sem ela o sketch compila e o jogo
   funciona, só as fitas de LED ficam desligadas.

O firmware **precisa ser regravado** ao atualizar para a V9: a escala de
medida mudou, e uma placa com firmware antigo devolve velocidades numa
faixa que a pontuação atual não espera.
