/*
  PUNCH CHALLENGE -- FIRMWARE V2 (MPU-6050)
  Placas: Arduino Uno / Nano (ATmega328P)
  Sensor: MPU-6050 no barramento I2C (A4 = SDA, A5 = SCL), endereco 0x68.
  Botoes: D2 = START, D3 = CREDIT (liga no GND; INPUT_PULLUP interno).

  PROTOCOLO SERIAL (115200 bps, uma linha por mensagem, campos com virgula):
    Enviados:  READY / CALIBRATING / CALIBRATED / PONG / BUTTON /
               TELEMETRY / HIT / SATURATION / ERROR / OK
    Recebidos: PING / RESET / TEST / CALIBRATE / LEDS,permil /
               CONFIG,eixo,raio,vmin,amin[,vmax]
  Referencia completa: docs/PROTOCOLO_SERIAL.md no projeto Godot.

  COMO MEDE: a aceleracao dinamica do eixo escolhido (bruta menos o
  repouso calibrado) dispara a medicao quando passa de ACCEL_MIN_G.
  Durante o golpe o firmware integra a aceleracao para obter a
  velocidade de pico e guarda a aceleracao maxima. O giroscopio da uma
  segunda estimativa (velocidade angular x raio do pendulo); vale a
  maior das duas. A PONTUACAO e calculada no Godot -- aqui sai so medida.
*/

#include <Wire.h>

/*  AS FITAS SAO OPCIONAIS -- E O SKETCH COMPILA SEM ELAS.

    AQUI ESTAVA O PIOR DEFEITO DESTE ARQUIVO. O `#include` da biblioteca
    das fitas era incondicional: numa IDE sem a Adafruit NeoPixel
    instalada, o sketch NAO COMPILA, nao ha upload, e a placa continua com
    o firmware velho -- ou com nenhum. O sintoma nao e "as fitas nao
    acendem": e "o Arduino nao faz nada", com START e CREDITO mortos
    junto, porque nada chegou a ser gravado.

    Uma peca de enfeite nunca pode impedir o botao de funcionar. Com o
    `__has_include`, a placa sem a biblioteca grava, mede o soco e
    responde aos botoes; quando a biblioteca for instalada, as fitas
    entram sozinhas na proxima gravacao.
*/
#if defined(__has_include)
  #if __has_include(<Adafruit_NeoPixel.h>)
    #include <Adafruit_NeoPixel.h>
    #define TEM_FITAS 1
  #endif
#endif
#ifndef TEM_FITAS
  #define TEM_FITAS 0
  #warning "Adafruit NeoPixel nao encontrada: o jogo funciona, as fitas de LED ficam desligadas. Instale pelo Gerenciador de Bibliotecas para liga-las."
#endif

#define MPU_ADDR 0x68
#define PINO_BOTAO_START 2
#define PINO_BOTAO_CREDIT 3
#define LED_STATUS 13

/*  AS DUAS FITAS DE LED DA MAQUINA
    -------------------------------
    Uma de cada lado do gabinete, subindo. Elas sao o placar que se le do
    outro lado do salao: quem esta na fila nao consegue ler 9610 a dez
    metros, mas ve a coluna de luz subir ate o topo e estourar em branco.
    E o que faz a pessoa seguinte querer bater.

    LIGACAO (WS2812B / NeoPixel, 5 V):
      dado da fita esquerda  -> D5   (com resistor de 330 ohm em serie)
      dado da fita direita   -> D6   (idem)
      +5 V e GND das fitas   -> FONTE PROPRIA de 5 V, nunca pelo Arduino
      GND da fonte           -> GND do Arduino (terra comum, obrigatorio)

    Trinta LEDs por fita a brilho maximo pedem quase dois amperes: tirar
    isso do regulador do Uno queima a placa. A fonte e separada, e o unico
    fio que volta ao Arduino e o terra.

    Um capacitor de 1000 uF entre +5 V e GND da fita, junto do primeiro
    LED, segura o pico da ligada.

    BIBLIOTECA: Adafruit NeoPixel, pelo Gerenciador de Bibliotecas da
    IDE do Arduino (Ferramentas > Gerenciar Bibliotecas > "Adafruit
    NeoPixel"). Sem ela este sketch nao compila.
*/
#define PINO_FITA_ESQ 5
#define PINO_FITA_DIR 6
#define LEDS_POR_FITA 30

// Brilho maximo. 140 de 255 e o teto pratico com uma fonte de 2 A para as
// duas fitas; 255 num salao escuro cega mais do que mostra.
#define BRILHO_FITA 140

#if TEM_FITAS
Adafruit_NeoPixel fitaEsq(LEDS_POR_FITA, PINO_FITA_ESQ, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaDir(LEDS_POR_FITA, PINO_FITA_DIR, NEO_GRB + NEO_KHZ800);
#endif

// A altura da coluna, de 0 a 1. Quem manda nela e, por ordem de
// prioridade, o jogo (comando LEDS) e, na falta dele, a propria medicao.
float nivelFita = 0.0f;
float nivelAlvo = 0.0f;
unsigned long fitaComandadaMs = 0;   // ultimo LEDS recebido do jogo
unsigned long ultimaFitaMs = 0;

// Enquanto o jogo estiver mandando LEDS, a medicao local nao mexe na
// coluna. Passados tres segundos sem comando, a placa volta a se virar
// sozinha -- e a maquina continua tendo fita mesmo com o PC desligado.
const unsigned long FITA_COMANDO_VALE_MS = 3000;
const unsigned long FITA_QUADRO_MS = 25;      // 40 quadros por segundo

// A velocidade que enche a coluna inteira. Chega pelo CONFIG; o padrao e
// o mesmo teto de fabrica do jogo.
float velocidadeMaxima = 16.0f;

/*  PROTOTIPOS DECLARADOS A MAO.

    A IDE do Arduino gera esses prototipos sozinha antes de compilar, e
    e por isso que o sketch funciona sem eles. Mas essa geracao e um
    truque do preprocessador da IDE: ela falha em casos que o C++ aceita
    (funcao que devolve tipo declarado depois, macro no meio da
    assinatura), e quando falha o erro que aparece nao tem nada a ver com
    a causa. Declarando a mao, o arquivo compila como C++ comum -- e da
    para conferir a compilacao fora da IDE, que foi como este arquivo
    passou a ser verificado antes de sair daqui.
*/
void executarComando(String cmd);
void configurar(const String &cmd);
void atualizarFitas();
void calibrar();
void enviarTelemetria();
void processarAmostra();
void processarBotoes();
void processarComandos();
void fecharGolpe();
bool mpuVivo();
bool mpuResponde(uint8_t endereco);
bool ligarMpu();
void insistirNoMpu();
void escreverReg(uint8_t reg, uint8_t valor);

/*  A PLACA FUNCIONA COM OU SEM O SENSOR.

    `mpuPronto` diz qual dos dois casos e o de agora -- e nenhum dos dois
    impede botao, serial ou fita de funcionar.
*/
bool mpuPronto = false;
unsigned long ultimaTentativaMpu = 0;
uint8_t enderecoMpu = MPU_ADDR;   // 0x68 ou 0x69, decidido ao procurar

// Escalas do MPU-6050 com a configuracao abaixo (+/-16 g, +/-2000  graus/s).
const float LSB_POR_G = 2048.0f;
const float LSB_POR_DPS = 16.4f;

// Ritmo de amostragem e da telemetria.
const unsigned long AMOSTRA_US = 4000;      // 250 Hz
const unsigned long TELEMETRIA_MS = 250;

// Reconhecimento do golpe.
const float FIM_GOLPE_FATOR = 0.40f;        // encerra abaixo de 40% do limiar
const unsigned long FIM_GOLPE_MS = 60;      // ...por este tempo
const unsigned long GOLPE_MAX_MS = 400;     // golpe nao dura mais que isso
const unsigned long COOLDOWN_MS = 650;      // um golpe por vez

// Configuracao ativa (chega pelo comando CONFIG; padroes sensatos).
char eixoMedicao = 'X';
float raioMetros = 0.45f;
float velocidadeMinima = 0.8f;   // m/s -- abaixo disso nem reporta
float accelMinG = 3.5f;          // g -- evita balanco/toque como golpe

// Offsets de repouso, medidos na calibracao.
float offAccel[3] = {0, 0, 0};   // em g
float offGyro[3] = {0, 0, 0};    // em  graus/s

// Estado da medicao em andamento.
bool golpeAtivo = false;
unsigned long golpeInicioMs = 0;
unsigned long golpeAbaixoMs = 0;
float picoG = 0.0f;
float velocidadeIntegral = 0.0f; // m/s, integracao da aceleracao
float picoGyroDps = 0.0f;
bool saturouAccel = false;
bool saturouGyro = false;
unsigned long ultimoGolpeMs = 0;

// Ultima medida, para a telemetria.
float ultimaVelocidade = 0.0f;
float ultimoPicoG = 0.0f;

unsigned long ultimaAmostraUs = 0;
unsigned long ultimaTelemetriaMs = 0;
String bufferSerial = "";

// ---------------------------------------------------------------- MPU-6050
/*  POR QUE TODA CHAMADA AO Wire LEVA UM (uint8_t) NA FRENTE.

    A biblioteca Wire declara DUAS versoes de `requestFrom`: uma que
    recebe (int, int) e outra (uint8_t, uint8_t). Chamando com
    `MPU_ADDR` -- que e um #define, ou seja, um int -- e um `(uint8_t)`
    no segundo argumento, NENHUMA das duas e melhor que a outra: a
    primeira precisa promover o segundo argumento, a segunda precisa
    converter o primeiro. O compilador chama isso de ambiguidade e
    despeja meia tela de "note: candidate 1 / candidate 2" em vermelho a
    cada compilacao.

    Nao era erro -- o sketch gravava --, mas ambiguidade e o compilador
    dizendo que NAO SABE qual funcao voce quis. Um dia ele escolhe a
    outra, o endereco vira 0x68 truncado de um int diferente, e o defeito
    aparece como "o sensor parou de ler" numa maquina que estava boa.

    Com os dois argumentos em uint8_t, so uma versao serve, e a
    compilacao sai limpa.
*/
void escreverReg(uint8_t reg, uint8_t valor) {
  Wire.beginTransmission(enderecoMpu);
  Wire.write(reg);
  Wire.write(valor);
  Wire.endTransmission();
}

/*  PROCURA O SENSOR NOS DOIS ENDERECOS, E ACEITA QUALQUER CLONE.

    Duas armadilhas moravam aqui, e as duas reprovavam modulo bom:

    ENDERECO. O MPU-6050 responde em 0x68 com o pino AD0 no terra e em
    0x69 com ele no positivo. O AD0 do GY-521 tem um resistor na placa
    que o puxa para baixo, mas em varios clones esse resistor nao existe
    e o pino fica solto -- e pino solto flutua. Procurar so em 0x68 e
    apostar.

    WHO_AM_I. Exigia-se que o registrador 0x75 devolvesse exatamente
    0x68. Metade dos modulos vendidos como "MPU-6050" traz na verdade um
    MPU-6500, um MPU-9250 ou um ICM-20608, que devolvem 0x70, 0x71, 0x73
    ou 0x98 -- e medem aceleracao igualzinho. Exigir 0x68 era reprovar
    hardware que funciona.

    O que interessa e se ALGUEM RESPONDE no barramento. Quem responder,
    serve.
*/
bool mpuResponde(uint8_t endereco) {
  Wire.beginTransmission(endereco);
  if (Wire.endTransmission() != 0) return false;
  Wire.beginTransmission(endereco);
  Wire.write((uint8_t)0x75); // WHO_AM_I
  if (Wire.endTransmission(false) != 0) return false;
  Wire.requestFrom(endereco, (uint8_t)1);
  if (Wire.available() < 1) return false;
  const uint8_t quem = (uint8_t)Wire.read();
  // Zero e 0xFF sao barramento mudo ou em curto, nao um chip.
  return quem != 0x00 && quem != 0xFF;
}

bool mpuVivo() {
  if (mpuResponde(0x68)) { enderecoMpu = 0x68; return true; }
  if (mpuResponde(0x69)) { enderecoMpu = 0x69; return true; }
  return false;
}

bool mpuLer(float accelG[3], float gyroDps[3]) {
  Wire.beginTransmission(enderecoMpu);
  Wire.write((uint8_t)0x3B); // ACCEL_XOUT_H: 14 bytes seguidos (accel, temp, gyro)
  if (Wire.endTransmission(false) != 0) return false;
  Wire.requestFrom(enderecoMpu, (uint8_t)14);
  if (Wire.available() < 14) return false;
  int16_t bruto[7];
  for (uint8_t i = 0; i < 7; i++) {
    /*  DOIS `Wire.read()` NA MESMA EXPRESSAO ERA UM DEFEITO ESPERANDO A
        VEZ DELE.

        Estava escrito `(Wire.read() << 8) | Wire.read()`. O C++ NAO
        define qual dos dois roda primeiro -- e a ordem aqui e tudo: o
        MPU-6050 manda o byte alto e depois o baixo, e trocar os dois
        transforma uma leitura de 1,02 g num numero sem sentido. Hoje o
        compilador do AVR calha de avaliar na ordem que da certo; uma
        atualizacao da IDE, um nivel de otimizacao diferente, e o sensor
        "para de funcionar" sem ninguem ter mexido no hardware.

        Com duas variaveis nomeadas, a ordem esta escrita e nao depende
        de sorte.
    */
    const uint8_t alto = (uint8_t)Wire.read();
    const uint8_t baixo = (uint8_t)Wire.read();
    bruto[i] = (int16_t)(((uint16_t)alto << 8) | (uint16_t)baixo);
  }
  for (uint8_t i = 0; i < 3; i++) {
    if (bruto[i] >= 32760 || bruto[i] <= -32760) saturouAccel = true;
    if (bruto[4 + i] >= 32760 || bruto[4 + i] <= -32760) saturouGyro = true;
    accelG[i] = (float)bruto[i] / LSB_POR_G - offAccel[i];
    gyroDps[i] = (float)bruto[4 + i] / LSB_POR_DPS - offGyro[i];
  }
  return true;
}

void calibrar() {
  // A maquina precisa estar PARADA. A media do repouso vira o zero de
  // cada eixo -- e o que tira a gravidade e a inclinacao da montagem.
  const uint16_t AMOSTRAS = 400;
  double somaA[3] = {0, 0, 0};
  double somaG[3] = {0, 0, 0};
  for (uint8_t i = 0; i < 3; i++) { offAccel[i] = 0; offGyro[i] = 0; }

  for (uint16_t n = 0; n < AMOSTRAS; n++) {
    float a[3], g[3];
    if (mpuLer(a, g)) {
      for (uint8_t i = 0; i < 3; i++) {
        somaA[i] += a[i];
        somaG[i] += g[i];
      }
    }
    if (n % 40 == 0) {
      Serial.print(F("CALIBRATING,"));
      Serial.println((int)(n * 100L / AMOSTRAS));
    }
    delay(5);
  }
  for (uint8_t i = 0; i < 3; i++) {
    offAccel[i] = (float)(somaA[i] / AMOSTRAS);
    offGyro[i] = (float)(somaG[i] / AMOSTRAS);
  }
  Serial.print(F("CALIBRATED,"));
  Serial.print(offAccel[0], 3);
  Serial.print(',');
  Serial.print(offAccel[1], 3);
  Serial.print(',');
  Serial.println(offAccel[2], 3);
}

// ---------------------------------------------------------------- golpe
uint8_t indiceEixo() {
  switch (eixoMedicao) {
    case 'Y': return 1;
    case 'Z': return 2;
    default: return 0;
  }
}

void processarAmostra() {
  float a[3], g[3];
  if (!mpuLer(a, g)) {
    Serial.println(F("ERROR,MPU_LEITURA"));
    return;
  }

  const unsigned long agora = micros();
  float dt = (float)(agora - ultimaAmostraUs) / 1000000.0f;
  ultimaAmostraUs = agora;
  if (dt <= 0.0f || dt > 0.05f) dt = 0.004f;

  const float aEixo = a[indiceEixo()];
  const float aAbs = fabsf(aEixo);
  const float giroAbs = fabsf(g[0]) + fabsf(g[1]) + fabsf(g[2]); // soma = robustez a montagem torta

  if (!golpeAtivo) {
    if (aAbs > accelMinG && millis() - ultimoGolpeMs >= COOLDOWN_MS) {
      golpeAtivo = true;
      golpeInicioMs = millis();
      golpeAbaixoMs = 0;
      picoG = aAbs;
      velocidadeIntegral = 0.0f;
      picoGyroDps = giroAbs;
      saturouAccel = false;
      saturouGyro = false;
      digitalWrite(LED_STATUS, HIGH);
    }
    return;
  }

  // Golpe em andamento: acumula velocidade e guarda os picos.
  velocidadeIntegral += aEixo * 9.81f * dt;
  if (velocidadeIntegral < 0.0f) velocidadeIntegral = 0.0f; // pendulo voltando nao desconta
  if (aAbs > picoG) picoG = aAbs;
  if (giroAbs > picoGyroDps) picoGyroDps = giroAbs;

  if (aAbs < accelMinG * FIM_GOLPE_FATOR) {
    if (golpeAbaixoMs == 0) golpeAbaixoMs = millis();
  } else {
    golpeAbaixoMs = 0;
  }

  const bool acabou = (golpeAbaixoMs != 0 && millis() - golpeAbaixoMs >= FIM_GOLPE_MS)
                      || (millis() - golpeInicioMs >= GOLPE_MAX_MS);
  if (!acabou) return;

  golpeAtivo = false;
  digitalWrite(LED_STATUS, LOW);
  ultimoGolpeMs = millis();

  // Duas estimativas de velocidade; vale a maior.
  const float vGyro = (picoGyroDps * DEG_TO_RAD) * raioMetros;
  const float velocidade = fmaxf(velocidadeIntegral, vGyro);
  const unsigned long duracao = millis() - golpeInicioMs;

  if (saturouAccel) Serial.println(F("SATURATION,ACCEL"));
  if (saturouGyro) Serial.println(F("SATURATION,GYRO"));

  if (velocidade < velocidadeMinima) return; // encostou, nao socou

  ultimaVelocidade = velocidade;
  ultimoPicoG = picoG;

  /*  A FITA SOBE NO MESMO INSTANTE DO GOLPE.

      Sem esperar o jogo: o PC ainda vai receber a linha, calcular a
      pontuacao e comecar a animar o placar, e sao decimos de segundo em
      que a luz ficaria parada logo depois da pancada. Quando o comando
      LEDS chegar, ele assume -- e o que a coluna fizer daqui ate la
      apenas antecipa o mesmo destino.
  */
  const float faixa = velocidadeMaxima - velocidadeMinima;
  float f = (faixa > 0.01f) ? (velocidade - velocidadeMinima) / faixa : 0.0f;
  if (f < 0.0f) f = 0.0f;
  if (f > 1.0f) f = 1.0f;
  if (f > nivelAlvo) nivelAlvo = f;

  Serial.print(F("HIT,"));
  Serial.print(velocidade, 2);
  Serial.print(',');
  Serial.print(picoG, 2);
  Serial.print(',');
  Serial.print(duracao);
  Serial.print(',');
  Serial.println(eixoMedicao);
}

// ---------------------------------------------------------------- botoes
void processarBotoes() {
  static bool antesStart = HIGH, antesCredit = HIGH;
  static unsigned long tStart = 0, tCredit = 0;
  const bool start = digitalRead(PINO_BOTAO_START);
  const bool credit = digitalRead(PINO_BOTAO_CREDIT);
  const unsigned long agora = millis();
  if (antesStart == HIGH && start == LOW && agora - tStart > 250) {
    tStart = agora;
    Serial.println(F("BUTTON,START"));
  }
  if (antesCredit == HIGH && credit == LOW && agora - tCredit > 250) {
    tCredit = agora;
    Serial.println(F("BUTTON,CREDIT"));
  }
  antesStart = start;
  antesCredit = credit;
}

// ---------------------------------------------------------------- telemetria
void enviarTelemetria() {
  if (golpeAtivo) return; // durante o golpe a serial fica livre para o HIT
  float a[3], g[3];
  if (!mpuLer(a, g)) return;
  Serial.print(F("TELEMETRY,"));
  Serial.print(a[0], 2); Serial.print(',');
  Serial.print(a[1], 2); Serial.print(',');
  Serial.print(a[2], 2); Serial.print(',');
  Serial.print(g[0], 1); Serial.print(',');
  Serial.print(g[1], 1); Serial.print(',');
  Serial.print(g[2], 1); Serial.print(',');
  Serial.print(ultimaVelocidade, 2); Serial.print(',');
  Serial.println(ultimoPicoG, 2);
}

// ---------------------------------------------------------------- comandos
void processarComandos() {
  while (Serial.available() > 0) {
    const char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      bufferSerial.trim();
      if (bufferSerial.length() > 0) executarComando(bufferSerial);
      bufferSerial = "";
    } else if (bufferSerial.length() < 48) {
      bufferSerial += c;
    }
  }
}

void executarComando(String cmd) {
  cmd.toUpperCase();
  if (cmd == "PING") {
    Serial.println(F("PONG"));
  } else if (cmd == "RESET") {
    golpeAtivo = false;
    digitalWrite(LED_STATUS, LOW);
    Serial.println(F("OK,RESET"));
  } else if (cmd == "CALIBRATE") {
    calibrar();
    Serial.println(F("OK,CALIBRATE"));
  } else if (cmd == "TEST") {
    /* Golpe sintetico: confere a corrente inteira -- Arduino, serial e
       jogo -- sem ninguem socar o saco. Se o TEST aparece na tela e o
       soco real nao, o problema e mecanico, nao de software. */
    Serial.print(F("HIT,7.50,9.20,120,"));
    Serial.println(eixoMedicao);
  } else if (cmd.startsWith("LEDS,")) {
    /*  A COLUNA COMANDADA PELO JOGO.

        `LEDS,0` a `LEDS,1000` (por mil). E o jogo que manda enquanto o
        placar sobe na tela, e por isso a fita acompanha o NUMERO subindo
        em vez do golpe cru: as duas coisas ficam no mesmo compasso, que
        e o que faz a maquina parecer uma peca so em vez de um monitor com
        uma fita pendurada.

        Passados tres segundos sem comando, a placa volta a se virar
        sozinha -- a fita continua funcionando com o PC desligado.
    */
    long permil = cmd.substring(5).toInt();
    if (permil < 0) permil = 0;
    if (permil > 1000) permil = 1000;
    nivelAlvo = (float)permil / 1000.0f;
    fitaComandadaMs = millis();
    Serial.println(F("OK,LEDS"));
  } else if (cmd.startsWith("CONFIG,")) {
    configurar(cmd);
  } else {
    Serial.println(F("ERROR,COMANDO_DESCONHECIDO"));
  }
}

void configurar(const String &cmd) {
  // CONFIG,eixo,raio_m,velocidade_min,accel_min_g
  char eixo = 0;
  float raio = 0, vmin = 0, amin = 0;
  // O quinto campo (vmax) e OPCIONAL de proposito: uma placa nova tem de
  // continuar aceitando o CONFIG de quatro campos de uma versao antiga do
  // jogo, senao atualizar um lado quebra o outro.
  float vmax = velocidadeMaxima;
  int campos = sscanf(cmd.c_str(), "CONFIG,%c,%f,%f,%f,%f", &eixo, &raio, &vmin, &amin, &vmax);
  const bool eixoOk = (eixo == 'X' || eixo == 'Y' || eixo == 'Z');
  const bool faixaOk = raio >= 0.05f && raio <= 1.50f
                       && vmin >= 0.2f && vmin <= 20.0f
                       && amin >= 0.5f && amin <= 15.0f;
  const bool tetoOk = vmax > vmin && vmax <= 40.0f;
  if ((campos != 4 && campos != 5) || !eixoOk || !faixaOk || !tetoOk) {
    Serial.println(F("ERROR,PARAM"));
    return;
  }
  eixoMedicao = eixo;
  raioMetros = raio;
  velocidadeMinima = vmin;
  accelMinG = amin;
  velocidadeMaxima = vmax;
  Serial.println(F("OK,CONFIG"));
}

// ------------------------------------------------------------- as fitas
#if TEM_FITAS
/*  A COR DE CADA ALTURA -- a mesma escala do jogo.
    As oito faixas de pontuacao do Punch Challenge vao do azul frio ao
    branco estourado, e a fita repete essa escala de baixo para cima. Quem
    olha a maquina de longe aprende a ler a cor antes de ler o numero: azul
    e "passou por aqui", vermelho e "bateu forte", branco e "chamou todo
    mundo".
*/
uint32_t corDoNivel(Adafruit_NeoPixel &fita, float f) {
  if (f < 0.25f) {           // azul-aco -> verde
    float k = f / 0.25f;
    return fita.Color((uint8_t)(20 * k), (uint8_t)(90 + 130 * k), (uint8_t)(180 - 120 * k));
  }
  if (f < 0.55f) {           // verde -> ambar
    float k = (f - 0.25f) / 0.30f;
    return fita.Color((uint8_t)(20 + 235 * k), (uint8_t)(220 - 40 * k), (uint8_t)(60 - 50 * k));
  }
  if (f < 0.85f) {           // ambar -> vermelho
    float k = (f - 0.55f) / 0.30f;
    return fita.Color(255, (uint8_t)(180 - 150 * k), (uint8_t)(10 + 20 * k));
  }
  float k = (f - 0.85f) / 0.15f;   // vermelho -> branco estourado
  return fita.Color(255, (uint8_t)(30 + 225 * k), (uint8_t)(30 + 225 * k));
}

/*  O DESENHO DA COLUNA.

    Abaixo do nivel, a cor cheia. NO nivel, um LED branco: e a ponta da
    coluna, e sem ela o topo se confunde com o resto. Acima, apagado --
    mas nao preto: um azul quase invisivel mantem a fita VISIVEL como
    objeto quando esta vazia, que e o que impede a maquina desligada de
    parecer quebrada.
*/
void desenharFita(Adafruit_NeoPixel &fita, float nivel) {
  const int acesos = (int)(nivel * LEDS_POR_FITA + 0.5f);
  for (int i = 0; i < LEDS_POR_FITA; i++) {
    const float f = (float)i / (float)(LEDS_POR_FITA - 1);
    if (i < acesos - 1) {
      fita.setPixelColor(i, corDoNivel(fita, f));
    } else if (i == acesos - 1) {
      fita.setPixelColor(i, fita.Color(255, 255, 255));
    } else {
      fita.setPixelColor(i, fita.Color(0, 0, 6));
    }
  }
  fita.show();
}

/*  A RESPIRACAO DE QUEM ESTA ESPERANDO.

    Maquina parada com fita apagada parece maquina desligada, e ninguem
    poe ficha em maquina desligada. Uma onda lenta subindo diz "estou
    ligada, venha bater" sem gastar a luz que o golpe vai precisar.
*/
void fitaEmEspera(unsigned long agora) {
  for (int i = 0; i < LEDS_POR_FITA; i++) {
    const float fase = (float)i / (float)LEDS_POR_FITA;
    float onda = sinf((agora * 0.0016f) - fase * 3.4f);
    onda = onda > 0.0f ? onda * onda : 0.0f;
    const uint8_t v = (uint8_t)(onda * 70.0f);
    const uint32_t cor = fitaEsq.Color(v, (uint8_t)(v / 4), (uint8_t)(v / 3));
    fitaEsq.setPixelColor(i, cor);
    fitaDir.setPixelColor(i, cor);
  }
  fitaEsq.show();
  fitaDir.show();
}

void atualizarFitas() {
  const unsigned long agora = millis();
  if (agora - ultimaFitaMs < FITA_QUADRO_MS) return;
  ultimaFitaMs = agora;

  const bool comandada = (agora - fitaComandadaMs) < FITA_COMANDO_VALE_MS;
  if (!comandada && nivelAlvo <= 0.001f && !golpeAtivo) {
    fitaEmEspera(agora);
    return;
  }

  /*  A COLUNA SOBE DEPRESSA E DESCE DEVAGAR.

      Subir junto com o golpe e o ponto do efeito -- se ela demorasse, a
      luz chegaria depois do soco e ninguem ligaria uma coisa a outra.
      Descer devagar e o que deixa a marca no ar tempo suficiente para a
      fila ver ate onde a pessoa chegou.
  */
  const float passo = (nivelAlvo > nivelFita) ? 0.22f : 0.012f;
  nivelFita += (nivelAlvo - nivelFita) * passo * 4.0f;
  if (nivelFita < 0.0f) nivelFita = 0.0f;
  if (nivelFita > 1.0f) nivelFita = 1.0f;
  desenharFita(fitaEsq, nivelFita);
  desenharFita(fitaDir, nivelFita);

  // Sem comando do jogo, a coluna desinfla sozinha depois do golpe.
  if (!comandada && !golpeAtivo) {
    nivelAlvo -= 0.006f;
    if (nivelAlvo < 0.0f) nivelAlvo = 0.0f;
  }
}

#else   // TEM_FITAS
// Sem a biblioteca, as fitas viram uma funcao vazia. Todo o resto do
// firmware -- sensor, botoes, serial -- continua igual.
void atualizarFitas() {}
#endif  // TEM_FITAS

// ---------------------------------------------------------------- ciclo
void setup() {
  pinMode(PINO_BOTAO_START, INPUT_PULLUP);
  pinMode(PINO_BOTAO_CREDIT, INPUT_PULLUP);
  pinMode(LED_STATUS, OUTPUT);
  digitalWrite(LED_STATUS, LOW);

#if TEM_FITAS
  fitaEsq.begin();
  fitaDir.begin();
  fitaEsq.setBrightness(BRILHO_FITA);
  fitaDir.setBrightness(BRILHO_FITA);
  fitaEsq.clear();
  fitaDir.clear();
  fitaEsq.show();
  fitaDir.show();
#endif

  Serial.begin(115200);

  /*  O `READY` VEM ANTES DE TUDO, E A PLACA NUNCA TRAVA.

      AQUI ESTAVA O DEFEITO QUE MATAVA A MAQUINA INTEIRA. Estava assim:

          if (!mpuVivo()) {
            Serial.println(F("ERROR,NO_MPU"));
            while (true) { pisca o LED; }     // <- para sempre
          }
          ...
          Serial.println(F("READY,..."));     // <- nunca chegava aqui

      Sem o sensor respondendo, a placa entrava num laco infinito ANTES
      de chegar ao `loop()`. Consequencia: `processarBotoes()` nunca
      rodava, e START e CREDITO ficavam MORTOS. O `READY` tambem nunca
      saia, entao o jogo nunca reconhecia a porta e ficava trocando de
      COM a noite inteira. As fitas idem.

      Um problema no sensor derrubava os botoes, a serial e a
      iluminacao -- tres coisas que nao dependem dele para nada. E o LED
      piscando em D13, unica pista que sobrava, ninguem ve dentro do
      gabinete fechado.

      A regra agora e outra: a placa SEMPRE chega ao `loop()`. Sem
      sensor ela avisa, segue funcionando -- botoes, serial, fitas -- e
      tenta o sensor de novo a cada dois segundos. Um fio de I2C mal
      encaixado que alguem empurre de volta passa a funcionar sozinho,
      sem desligar nada.
  */
  Serial.println(F("READY,PUNCH_MPU6050,V3"));

  Wire.begin();
  Wire.setClock(400000); // I2C rapido: a leitura nao pode atrasar a amostragem

  if (ligarMpu()) {
    calibrar();
  } else {
    Serial.println(F("ERROR,NO_MPU"));
  }
  ultimaAmostraUs = micros();
}

/*  Acorda o MPU e o deixa na escala do jogo. Devolve falso se ele nao
    responde -- e nesse caso a placa continua trabalhando sem ele.
*/
bool ligarMpu() {
  if (!mpuVivo()) {
    mpuPronto = false;
    return false;
  }
  escreverReg(0x6B, 0x01); // PWR_MGMT_1: acorda, clock do giroscopio X
  escreverReg(0x1A, 0x03); // CONFIG: DLPF ~44 Hz -- corta ruido, mantem o golpe
  escreverReg(0x1B, 0x18); // GYRO_CONFIG: +/-2000  graus/s
  escreverReg(0x1C, 0x18); // ACCEL_CONFIG: +/-16 g
  delay(50);
  mpuPronto = true;
  return true;
}

/*  Tenta o sensor de novo, de dois em dois segundos, enquanto ele
    faltar. E o que permite consertar um fio com a maquina ligada.
*/
void insistirNoMpu() {
  if (mpuPronto) return;
  const unsigned long agora = millis();
  if (agora - ultimaTentativaMpu < 2000) return;
  ultimaTentativaMpu = agora;
  // O LED de status pisca enquanto falta sensor: e a pista de quem esta
  // com a tampa aberta.
  digitalWrite(LED_STATUS, !digitalRead(LED_STATUS));
  if (ligarMpu()) {
    digitalWrite(LED_STATUS, LOW);
    Serial.println(F("OK,MPU"));
    calibrar();
  }
}

void loop() {
  // A ORDEM IMPORTA: botoes e serial vem PRIMEIRO, e sem condicao
  // nenhuma. Eles nao dependem do sensor e nao podem ficar presos a ele.
  processarComandos();
  processarBotoes();
  insistirNoMpu();

  if (mpuPronto && (long)(micros() - ultimaAmostraUs) >= (long)AMOSTRA_US) {
    processarAmostra();
  }
  if (millis() - ultimaTelemetriaMs >= TELEMETRIA_MS) {
    ultimaTelemetriaMs = millis();
    enviarTelemetria();
  }
  atualizarFitas();
}
