# Punch Challenge

Jogo arcade de soco desenvolvido em Godot 4, preparado para máquina física com Arduino e sensor óptico de encoder.

## O que já está pronto

- Interface moderna em 1920 × 1080, adaptável para outras resoluções.
- Contagem regressiva animada `3, 2, 1` e janela de oito segundos para o golpe.
- Pontuação de potência de 0 a 999 baseada na velocidade medida.
- Recorde, número total de partidas e saldo de créditos persistentes.
- Modo Livre ou 1 Ficha selecionável na Central Técnica.
- `START`: inicia a partida.
- `SELECT`: adiciona um crédito.
- `F9`: abre e fecha a Central Técnica.
- `ESC`: fecha a configuração ou cancela uma rodada sem travar a interface.
- Seleção de COM1 a COM99, teste visual do sensor e calibração mínima/máxima.
- Ícone, tela de abertura e identificação próprios — sem símbolo padrão do Godot.

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

Caso sua Zero Delay apareça com números de botões diferentes, altere os números `6` e `7` no método `_input()` de `scripts/main.gd`. O teste de controle do Godot informa qual número cada botão está enviando.

## Calibração da pontuação

1. Na Central Técnica, deixe o mínimo inicialmente em `1,0 m/s` e o máximo em `12,0 m/s`.
2. Faça dez golpes leves e anote aproximadamente as velocidades.
3. Faça dez golpes fortes com segurança e anote o maior valor repetível.
4. Use como mínimo o valor de um golpe fraco verdadeiro.
5. Use como máximo o maior golpe que a mecânica suporta de forma repetível.

Valores abaixo do mínimo ficam próximos de 0; valores no máximo ou acima chegam a 999.

## Teste sem Arduino

Abra o jogo, pressione `F9` e depois a tecla `T` para simular pulsos. Durante uma rodada, `T` também simula um golpe. Esse recurso existe apenas para montagem e teste da interface.

## Exportação Windows

O preset já está incluído. No Godot, instale os templates de exportação e use **Projeto → Exportar → Windows Desktop**. O executável será criado em `build/PunchChallenge.exe` com o pacote incorporado.

## Segurança mecânica

Instale batentes, proteções e amortecimento adequados para impedir que o mecanismo alcance o operador. O sensor e o Arduino não substituem proteções físicas, parada de emergência nem projeto mecânico seguro.
