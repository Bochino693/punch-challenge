# Punch Challenge

Jogo arcade de soco desenvolvido em Godot 4, preparado para máquina física com Arduino e sensor óptico de encoder.

## Tela em pé

O jogo é desenhado para **1080 × 1920 (vertical)**. A máquina é um armário
alto com o saco na frente: quem joga olha para cima, não para os lados.
Numa tela deitada, metade da largura seria moldura vazia e o número da
pontuação ficaria pequeno justamente para quem está a três metros de
distância. Em pé, a leitura desce em coluna — marca, número, veredito —
que é a ordem em que a pessoa procura.

Para montar:

1. Gire o monitor fisicamente (suporte VESA em retrato).
2. No Windows: **Configurações → Sistema → Vídeo → Orientação da tela →
   Retrato**. Confira qual dos dois retratos deixa a imagem na posição
   certa para o seu suporte.
3. O jogo abre em tela cheia; nada mais a ajustar.

Para testar no PC do escritório, sem girar o monitor, a janela abre em
540 × 960 (`window_width_override` no `project.godot`) — a proporção é a
mesma, só menor. O `aspect="keep"` mantém as margens pretas em monitores
que não sejam 9:16 exatos, em vez de esticar a marca.

## Como a máquina se comporta

```
ABERTURA → (START) → ENTRADA → 3, 2, 1 → SENSOR ARMADO → RESULTADO
```

**Abertura.** É a tela que fica ligada o dia inteiro no salão, e é ela que
faz alguém atravessar o corredor para jogar: a logo da Lazer & Sport em
tamanho grande, com brilho, raios girando e uma luz varrendo a marca a
cada quatro segundos; o nome do jogo em néon; e o convite piscando. Sem
crédito no modo ficha, o convite troca de texto em vez de sumir — quem
chegou perto precisa saber o que fazer.

**START entra no jogo.** A marca vem para a frente, estoura num clarão e
a contagem começa. Em modo ficha, o crédito é debitado aqui; em modo
livre, START entra direto.

**O resultado tem três finais**, e é isso que faz o cliente jogar de novo:

| Faixa | O que a tela faz |
| --- | --- |
| **Forte** (padrão: 700+) | `NOCAUTE!` — confete, fogos, raios dourados girando, tremor e clarão. Animação de vitória. |
| **Médio** (padrão: 330 a 699) | `BOM GOLPE` — âmbar, faíscas e anéis pulsando. Nem festa, nem derrota. |
| **Fraco** (padrão: até 329) | `FRACO!` — moldura vermelha pulsando, estilhaços caindo e o carimbo escorregando para baixo. Animação de derrota. |

As duas faixas são ajustáveis na Central Técnica: a mecânica de cada
máquina responde diferente, e uma faixa errada faz todo mundo ganhar (ou
todo mundo perder), que é o jeito mais rápido de esvaziar a fila.

**A contagem é o suspense.** O número sobe de zero até a pontuação em
cerca de dois segundos, com tique a cada passo e o ponteiro colorindo o
arco conforme cruza as faixas. O veredito só entra quando a contagem
termina — é o momento pelo qual o cliente pagou.

## O que já está pronto

- Interface vertical em 1080 × 1920, adaptável para outras resoluções.
- Abertura com a marca da casa, efeito de luz, partículas e convite piscando.
- Contagem regressiva animada `3, 2, 1` e janela de oito segundos para o golpe.
- Pontuação de potência de 0 a 999 baseada na velocidade medida.
- Três animações de resultado: vitória, intermediária e derrota.
- Recorde, número total de partidas e saldo de créditos persistentes.
- Modo Livre ou 1 Ficha selecionável na Central Técnica.
- `START`: entra no jogo e joga de novo depois do resultado.
- `SELECT`: adiciona um crédito.
- `F9`: abre e fecha a Central Técnica.
- `ESC`: fecha a configuração ou cancela uma rodada sem travar a interface.
- Seleção de COM1 a COM99, teste visual do sensor e calibração mínima/máxima.
- Aprendizado dos botões da placa zero delay, sem mexer em código.
- Ícone, abertura e identificação próprios — sem símbolo padrão do Godot.

## Hardware recomendado

- Arduino Nano ou Uno.
- Sensor óptico encoder LM393 igual ao da referência, alimentado entre 3,3 e 5 V e com saídas digital e analógica.
- Disco ranhurado fixado no eixo móvel da máquina.
- Placa USB Zero Delay para os botões arcade.

### Ligação do sensor

| Sensor | Arduino |
| --- | --- |
| VCC / + | 5V |
| GND / - | GND |
| D0 / saída digital | D2 |
| A0 / saída analógica | Não conectar neste projeto |

Confira sempre as marcações impressas no seu módulo, pois a ordem física dos pinos pode variar. O modelo B22-004 utiliza comparador LM393, alimentação de 3,3–5 V e passagem de aproximadamente 5 mm para o disco. O fio do sensor deve ficar afastado de motor, solenoide e cabos de potência. Em uma máquina com ruído elétrico, use fonte estabilizada, aterramento correto e cabo de sinal blindado.

## Ajustes obrigatórios no Arduino

Abra `arduino/punch_sensor/punch_sensor.ino` e confira:

```cpp
const uint16_t PULSOS_POR_VOLTA = 20;
const float RAIO_METROS = 0.100f;
```

`PULSOS_POR_VOLTA` é o número de janelas do disco. `RAIO_METROS` é a distância do centro do eixo até o ponto cuja velocidade deve ser calculada. Se esses valores estiverem errados, a velocidade exibida também ficará errada.

O sensor óptico mede velocidade; ele não mede força física em newtons ou quilogramas-força. O jogo transforma a velocidade em uma pontuação arcade calibrada.

## Instalação

1. Grave o arquivo `.ino` no Arduino com velocidade serial de `115200`.
2. Instale o Python 3 no Windows, marcando **Add Python to PATH**.
3. Execute uma vez `tools/INSTALAR_PONTE_SERIAL.bat`.
4. Abra `project.godot` no Godot 4.3 ou mais recente.
5. Execute o projeto e pressione `F9`.
6. Escolha a porta COM do Arduino e pressione **RECONECTAR**.
7. Gire manualmente o disco: a entrada deve piscar e mostrar a frequência.

## Placa Zero Delay

As ações já aceitam estas entradas:

| Função | Teclado | Controle USB |
| --- | --- | --- |
| START | `1`, `Enter` ou `Espaço` | botão 7 |
| SELECT / crédito | `5` ou `C` | botão 6 |
| Configuração | `F9` | teclado técnico |

Cada placa zero delay numera os botões de um jeito, e o número que
funciona numa não funciona na outra. Em vez de mexer em código, use a
Central Técnica (`F9`): aperte **APRENDER START**, depois o botão físico
da máquina; repita em **APRENDER SELECT**. O número aprendido fica salvo
e aparece na linha de diagnóstico. Uma vez por máquina, e acabou.

## Calibração da pontuação

1. Na Central Técnica, deixe o mínimo inicialmente em `1,0 m/s` e o máximo em `12,0 m/s`.
2. Faça dez golpes leves e anote aproximadamente as velocidades.
3. Faça dez golpes fortes com segurança e anote o maior valor repetível.
4. Use como mínimo o valor de um golpe fraco verdadeiro.
5. Use como máximo o maior golpe que a mecânica suporta de forma repetível.

Valores abaixo do mínimo ficam próximos de 0; valores no máximo ou acima chegam a 999.

Depois disso, ajuste as faixas na mesma tela: **ATÉ AQUI É FRACO** e
**DAQUI É FORTE**. Uma referência que costuma funcionar em máquina nova é
deixar a criança tirando "médio" e o adulto empenhado tirando "forte" —
se todo mundo estiver tirando nocaute, suba o limite; se ninguém
conseguir, desça.

## Teste sem Arduino

Abra o jogo, pressione `F9` e depois a tecla `T` para simular pulsos. Durante uma rodada, `T` também simula um golpe. Esse recurso existe apenas para montagem e teste da interface.

Com o Arduino ligado, o comando `TEST` pela serial devolve um golpe
sintético: se ele aparece na tela e o soco real não, o problema é o
sensor, e não o software.

## Exportação Windows

O preset já está incluído. No Godot, instale os templates de exportação e use **Projeto → Exportar → Windows Desktop**. O executável será criado em `build/PunchChallenge.exe` com o pacote incorporado.

## Segurança mecânica

Instale batentes, proteções e amortecimento adequados para impedir que o mecanismo alcance o operador. O sensor e o Arduino não substituem proteções físicas, parada de emergência nem projeto mecânico seguro.
