/*
  PUNCH CHALLENGE -- FIRMWARE V9 (MPU-6050)
  Placas: Arduino Uno / Nano (ATmega328P)
  Sensor: MPU-6050 no barramento I2C (A4 = SDA, A5 = SCL), endereco 0x68/0x69.
  Botoes: D2 = START, D3 = CREDIT (liga no GND; INPUT_PULLUP interno).

  PROTOCOLO SERIAL (115200 bps, uma linha por mensagem, campos com virgula):
    Enviados:  READY / CALIBRATING / CALIBRATED / PONG / BUTTON / PINS /
               TELEMETRY / HIT / SATURATION / ERROR / OK
    Recebidos: PING / RESET / TEST / CALIBRATE / LEDS,permil /
               CONFIG,eixo,raio,vmin,amin[,vmax]
  Referencia completa: docs/PROTOCOLO_SERIAL.md no projeto Godot.

  ====================================================================
  POR QUE ESTA VERSAO EXISTE
  ====================================================================

  A V2 media assim: quando |aceleracao do eixo| passava de um limiar,
  integrava a aceleracao por ate 400 ms e mandava o resultado. Tres
  defeitos vinham juntos, e sao exatamente os sintomas relatados:

  1. SENSOR PARADO GERANDO SOCO. O "zero" de cada eixo era medido UMA VEZ
     na calibracao e nunca mais. Se a montagem inclinasse depois -- um
     saco que fica torto, um suporte que cede -- a gravidade se
     reprojetava no eixo e virava "aceleracao dinamica" PERMANENTE. Pior:
     se alguem encostasse na maquina durante os 2 segundos da calibracao
     do arranque, o zero nascia errado e ficava errado a noite inteira.

  2. DERIVA VIRANDO VELOCIDADE. Integrar por 400 ms sem ancora nenhuma:
     um vies residual de 0,2 g dava 0,2 * 9,81 * 0,4 = 0,78 m/s do nada --
     em cima de um piso de 0,8 m/s. Ou seja, ruido produzia "golpes" no
     limiar.

  3. REBOTE CONSUMINDO TENTATIVA. O tempo morto era de 650 ms. Um saco
     pendurado balanca MUITO mais que isso, e cada volta do balanco
     cruzava o limiar de novo: um soco virava dois.

  E media numa escala que o jogo nao esperava. O `score_curve.gd` esta
  escrito para um firmware que mede HONESTAMENTE (0,3 a 5,2 m/s); a V2
  integrando por 400 ms produzia numeros varias vezes maiores. Dai
  "todos os impactos valiam a mesma coisa": tudo saturava no teto.

  ====================================================================
  COMO A V9 MEDE
  ====================================================================

  TRES ESTADOS SEPARADOS, e nenhum deles se confunde com o outro:
  porta aberta != placa identificada != sensor pronto e em repouso.

  A) LINHA DE BASE VIVA, em vez de um zero de uma vez so.
     Enquanto a maquina esta QUIETA, a base de cada eixo persegue a
     leitura crua devagar (constante de tempo ~2 s). Isso absorve
     gravidade, inclinacao da montagem e deriva termica sozinho. Quando
     ha movimento, a base CONGELA -- um soco nunca contamina o proprio
     zero.

  B) O SOCO SO PODE COMECAR A PARTIR DO REPOUSO.
     E preciso um periodo continuo de quietude (AMOSTRAS_DE_REPOUSO)
     antes de qualquer golpe ser aceito. Esta unica regra mata quatro
     coisas de uma vez: sensor parado, inclinacao sustentada, empurrao
     lento e a oscilacao depois do primeiro golpe.

  C) A FORMA DO EVENTO PRECISA SER DE SOCO.
     Subida rapida (o pico chega em ate SUBIDA_MAX_MS), amostras
     consecutivas acima do gatilho (um pico eletrico de uma amostra nao
     passa), e -- obrigatorio -- A QUEDA: o sinal precisa voltar para
     baixo do gatilho dentro da janela. Um empurrao sustentado nunca
     fecha essa forma, e por isso NAO VIRA GOLPE. A janela e curta
     (JANELA_MAX_MS), que e a duracao fisica de um impacto de verdade.

  D) A MEDIDA E A INTEGRAL, e o giroscopio e TESTEMUNHA, nao somatorio.
     A velocidade sai da integracao por trapezio da aceleracao dinamica,
     com a base congelada no instante do gatilho. O giroscopio serve
     para (i) confirmar que o alvo REALMENTE se moveu e (ii) substituir
     a medida quando o acelerometro satura. A V2 usava o MAIOR entre os
     dois e somava |gx|+|gy|+|gz| -- somar tres eixos so soma tres
     ruidos, e o "maior" deixava esse ruido inflar a nota.

  E) SEPARACAO EXPLICITA, que e o que o jogo pediu:
       - VALIDAR se foi um impacto fisico  -> B e C
       - MEDIR o impacto ja aceito          -> D
       - CONVERTER medida em pontuacao      -> NAO ACONTECE AQUI.
     A pontuacao e do `score_curve.gd`. Daqui sai medida em m/s, e nada
     mais. Nao ha newtons: nao ha modelo de massa nem calibracao de
     forca que sustente essa palavra, entao ela nao aparece.

  F) CALIBRACAO QUE SE RECUSA A CALIBRAR ERRADO.
     Ela mede a dispersao enquanto amostra. Se a maquina estava se
     mexendo, ela NAO grava o zero novo, mantem o anterior e avisa
     (ERROR,CALIB_MOVIMENTO). Um zero nascido torto era o defeito mais
     caro da V2, porque estragava a noite inteira em silencio.

  G) A SERIAL NUNCA FICA SURDA.
     A calibracao da V2 bloqueava por ~2 s (400 amostras x delay(5)),
     e nesse intervalo PING, START e CREDITO morriam -- bem no momento
     em que o jogo acabara de abrir a porta e estava decidindo se aquela
     COM tinha placa. Aqui a calibracao atende comandos e botoes a cada
     volta.
*/

#include <Wire.h>

/*  AS FITAS SAO OPCIONAIS -- E O SKETCH COMPILA SEM ELAS.

    O `#include` da biblioteca das fitas e condicional de proposito: numa
    IDE sem a Adafruit NeoPixel instalada, um include incondicional faz o
    sketch NAO COMPILAR, nao ha upload, e a placa continua com o firmware
    velho -- ou com nenhum. O sintoma nao e "as fitas nao acendem": e "o
    Arduino nao faz nada", com START e CREDITO mortos junto.
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

    LIGACAO (WS2812B / NeoPixel, 5 V):
      dado da fita esquerda  -> D5   (com resistor de 330 ohm em serie)
      dado da fita direita   -> D6   (idem)
      +5 V e GND das fitas   -> FONTE PROPRIA de 5 V, nunca pelo Arduino
      GND da fonte           -> GND do Arduino (terra comum, obrigatorio)

    Trinta LEDs por fita a brilho maximo pedem quase dois amperes: tirar
    isso do regulador do Uno queima a placa. Um capacitor de 1000 uF
    entre +5 V e GND da fita, junto do primeiro LED, segura o pico.
*/
#define PINO_FITA_ESQ 5
#define PINO_FITA_DIR 6
#define LEDS_POR_FITA 30
#define BRILHO_FITA 140

#if TEM_FITAS
Adafruit_NeoPixel fitaEsq(LEDS_POR_FITA, PINO_FITA_ESQ, NEO_GRB + NEO_KHZ800);
Adafruit_NeoPixel fitaDir(LEDS_POR_FITA, PINO_FITA_DIR, NEO_GRB + NEO_KHZ800);
#endif

float nivelFita = 0.0f;
float nivelAlvo = 0.0f;
unsigned long fitaComandadaMs = 0;
unsigned long ultimaFitaMs = 0;
const unsigned long FITA_COMANDO_VALE_MS = 3000;
const unsigned long FITA_QUADRO_MS = 25;
float velocidadeMaxima = 5.20f;   // teto da coluna; igual ao teto do jogo

// Prototipos declarados a mao: assim o arquivo compila como C++ comum e
// da para conferir a compilacao fora da IDE do Arduino.
void executarComando(const char *cmd);
void configurar(const char *cmd);
void calibrar();
void enviarTelemetria();
void processarAmostra();
void processarBotoes();
void processarComandos();
bool mpuVivo();
bool mpuResponde(uint8_t endereco);
bool ligarMpu();
void insistirNoMpu();
void enviarPinos();
void escreverReg(uint8_t reg, uint8_t valor);
void atualizarFitas();
bool mpuLer(float *accelG, float *gyroDps);

/*  A PLACA FUNCIONA COM OU SEM O SENSOR. */
bool mpuPronto = false;
unsigned long ultimaTentativaMpu = 0;
uint8_t enderecoMpu = MPU_ADDR;

// Escalas do MPU-6050 com a configuracao abaixo (+/-16 g, +/-2000 graus/s).
const float LSB_POR_G = 2048.0f;
const float LSB_POR_DPS = 16.4f;

// Ritmo de amostragem e da telemetria.
const unsigned long AMOSTRA_US = 4000;      // 250 Hz
const unsigned long TELEMETRIA_MS = 250;

/*  ------------------------------------------------------------------
    OS NUMEROS DA DETECCAO, e o raciocinio de cada um.
    ------------------------------------------------------------------ */

/*  O QUE CONTA COMO "QUIETO".
    Com o MPU na escala de +/-16 g, um LSB vale 1/2048 g. O ruido tipico
    de repouso fica bem abaixo de 0,05 g; 0,12 g da folga para vibracao
    de salao (som alto, gente passando, ventilador do gabinete) sem
    deixar passar movimento de verdade. */
const float RUIDO_G = 0.12f;
const float RUIDO_DPS = 15.0f;

/*  QUANTO TEMPO DE QUIETUDE ANTES DE ACEITAR UM SOCO.
    50 amostras a 250 Hz = 200 ms. E a regra que sozinha resolve
    "sensor parado dispara", inclinacao sustentada, empurrao lento e
    rebote: nenhum deles apresenta 200 ms de quietude antes do evento. */
const uint16_t AMOSTRAS_DE_REPOUSO = 50;

/*  A JANELA DO IMPACTO.
    Um soco num saco/alvo e um evento de dezenas de milissegundos. 160 ms
    cobre o impacto inteiro com folga; passar disso e balanco, nao soco.
    Era 400 ms na V2 -- tempo de sobra para a deriva virar velocidade. */
const unsigned long JANELA_MAX_MS = 160;

/*  A SUBIDA PRECISA SER RAPIDA.
    Num impacto o pico chega quase junto com o inicio. Um empurrao
    forte, ainda que passe do gatilho, sobe devagar. 70 ms separa os
    dois sem apertar demais um golpe fraco e legitimo. */
const unsigned long SUBIDA_MAX_MS = 70;

/*  A QUEDA E OBRIGATORIA.
    O evento so fecha quando o sinal volta abaixo de gatilho*FATOR_QUEDA
    e fica la por MS_DE_QUEDA. Sinal que NAO cai dentro da janela e
    inclinacao ou empurrao sustentado, e e descartado sem virar golpe. */
const float FATOR_QUEDA = 0.35f;
const unsigned long MS_DE_QUEDA = 24;

/*  Duas amostras consecutivas acima do gatilho. Um pico eletrico de uma
    amostra so -- ruido de I2C, interferencia do cabo -- nao passa. */
const uint8_t AMOSTRAS_DE_SUBIDA = 2;

/*  Duracao minima de um impacto real. Abaixo disso e artefato. */
const unsigned long DURACAO_MIN_MS = 14;

/*  TEMPO MORTO, contado do FIM do golpe aceito.
    Maior que o balanco tipico do alvo. Alem dele, o proximo golpe ainda
    precisa dos 200 ms de repouso -- sao duas travas, nao uma. */
const unsigned long TEMPO_MORTO_MS = 1200;

/*  O giroscopio como TESTEMUNHA: o alvo precisa ter se mexido de
    verdade. Um tranco no gabinete sacode o acelerometro sem girar o
    pendulo. Valor baixo de proposito -- e prova de movimento, nao
    medida de forca, e golpe fraco legitimo precisa passar. */
const float GIRO_MINIMO_DPS = 25.0f;

/*  Velocidade com que a base persegue a leitura crua ENQUANTO QUIETO.
    0,002 por amostra a 250 Hz da constante de tempo de ~2 s: rapido o
    bastante para acompanhar a maquina sendo reposicionada, lento o
    bastante para nao comer o comeco de um soco. */
const float BASE_ALFA = 0.002f;

// Configuracao ativa (chega pelo comando CONFIG; padroes sensatos).
char eixoMedicao = 'X';
float raioMetros = 0.45f;
/*  O PISO DE VELOCIDADE ACOMPANHA O PISO DA PONTUACAO.
    Era 0,8 aqui contra 0,30 no `score_curve.gd`: a faixa 0,30-0,80
    existia na curva e era jogada fora pelo firmware, ou seja, golpe
    fraco legitimo sumia antes de chegar ao jogo. */
float velocidadeMinima = 0.30f;
float accelMinG = 3.00f;

// Linha de base viva (em g e em graus/s).
float baseAccel[3] = {0, 0, 0};
float baseGyro[3] = {0, 0, 0};
bool baseIniciada = false;

// Estado da medicao em andamento.
bool golpeAtivo = false;
bool baseValida = false;
unsigned long golpeInicioMs = 0;
unsigned long golpeAbaixoMs = 0;
unsigned long instanteDoPicoMs = 0;
float picoG = 0.0f;
float velocidadeIntegral = 0.0f;
float velocidadePico = 0.0f;
float picoGyroDps = 0.0f;
float aAnterior = 0.0f;
float sinalDoGolpe = 1.0f;
float baseCongelada[3] = {0, 0, 0};
uint8_t amostrasAcima = 0;
bool saturouAccel = false;
bool saturouGyro = false;
bool caiu = false;
unsigned long fimDoUltimoGolpeMs = 0;

// Contador de quietude.
uint16_t amostrasQuietas = 0;
/*  A TRAVA DE REPOUSO, e por que ela e um ESTADO e nao uma pergunta.

    "A maquina esta em repouso?" perguntado a cada amostra nunca pode
    autorizar um soco: a amostra que inicia o golpe ja nao esta quieta, e
    a seguinte ja tem o contador zerado pela primeira. Medido na bancada:
    a placa rejeitava repouso, inclinacao, empurrao e ruido -- e rejeitava
    junto TODOS os socos de verdade.

    Entao o repouso vira uma AUTORIZACAO que se conquista e se gasta: ela
    acende depois de AMOSTRAS_DE_REPOUSO amostras quietas seguidas, e so
    apaga quando um golpe comeca, e aceito, ou e descartado. Depois disso
    e preciso ficar quieto de novo para reconquista-la. E isso que impede
    o rebote do saco de virar um segundo soco: entre uma volta e outra do
    balanco nunca ha 200 ms de quietude. */
bool prontoParaGolpe = false;

// Ultima medida, para a telemetria.
float ultimaVelocidade = 0.0f;
float ultimoPicoG = 0.0f;

unsigned long ultimaAmostraUs = 0;
unsigned long ultimaTelemetriaMs = 0;

/*  BUFFER DE COMANDO EM char[], e nao em String.
    O `String` do Arduino fragmenta os 2 KB de RAM do ATmega328P ao
    longo de horas de operacao. Numa maquina que fica ligada a noite
    toda, isso termina em travamento sem causa aparente. */
char bufferSerial[52];
uint8_t bufferUso = 0;

// ---------------------------------------------------------------- MPU-6050
/*  POR QUE TODA CHAMADA AO Wire LEVA UM (uint8_t) NA FRENTE.
    A biblioteca Wire declara duas versoes de `requestFrom` -- (int,int) e
    (uint8_t,uint8_t). Chamar com um #define (int) e um (uint8_t) deixa as
    duas igualmente ruins e o compilador acusa ambiguidade. Convertendo
    os dois lados, a escolha e unica. */
void escreverReg(uint8_t reg, uint8_t valor) {
  Wire.beginTransmission((uint8_t)enderecoMpu);
  Wire.write((uint8_t)reg);
  Wire.write((uint8_t)valor);
  Wire.endTransmission();
}

bool mpuResponde(uint8_t endereco) {
  Wire.beginTransmission((uint8_t)endereco);
  return Wire.endTransmission() == 0;
}

/*  O MPU-6050 pode estar em 0x68 ou 0x69, conforme o pino AD0. Modulo
    generico com AD0 em alta responde so no segundo -- e o sintoma e
    identico ao de sensor queimado. Procurar nos dois custa nada. */
bool mpuVivo() {
  if (mpuResponde(MPU_ADDR)) { enderecoMpu = MPU_ADDR; return true; }
  if (mpuResponde(MPU_ADDR + 1)) { enderecoMpu = MPU_ADDR + 1; return true; }
  return false;
}

bool mpuLer(float *accelG, float *gyroDps) {
  Wire.beginTransmission((uint8_t)enderecoMpu);
  Wire.write((uint8_t)0x3B);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((uint8_t)enderecoMpu, (uint8_t)14) != 14) return false;

  int16_t bruto[7];
  for (uint8_t i = 0; i < 7; i++) {
    bruto[i] = (int16_t)((Wire.read() << 8) | Wire.read());
  }
  // bruto[0..2] = accel, bruto[3] = temperatura, bruto[4..6] = giro
  saturouAccel = false;
  saturouGyro = false;
  for (uint8_t i = 0; i < 3; i++) {
    if (bruto[i] >= 32700 || bruto[i] <= -32700) saturouAccel = true;
    if (bruto[4 + i] >= 32700 || bruto[4 + i] <= -32700) saturouGyro = true;
    accelG[i] = (float)bruto[i] / LSB_POR_G;
    gyroDps[i] = (float)bruto[4 + i] / LSB_POR_DPS;
  }
  return true;
}

/*  ------------------------------------------------------------------
    CALIBRACAO QUE SE RECUSA A CALIBRAR ERRADO.
    ------------------------------------------------------------------
    A V2 gravava a media sem olhar a dispersao. Se alguem encostasse na
    maquina durante os 2 s da calibracao do arranque -- e no arranque
    alguem quase sempre esta com a mao na maquina --, o zero nascia
    torto e ficava torto. Dai o "sensor parado dispara" que nao tinha
    explicacao: o sensor estava parado, o ZERO e que estava errado.

    Agora a dispersao e medida junto. Se a maquina estava se mexendo, o
    zero anterior e mantido e o jogo e avisado.
*/
void calibrar() {
  const uint16_t AMOSTRAS = 300;      // 300 x 4 ms = 1,2 s
  float somaA[3] = {0, 0, 0};
  float somaG[3] = {0, 0, 0};
  float maxA[3], minA[3];
  bool primeira = true;
  uint16_t validas = 0;

  for (uint16_t n = 0; n < AMOSTRAS; n++) {
    float a[3], g[3];
    if (mpuLer(a, g)) {
      for (uint8_t i = 0; i < 3; i++) {
        somaA[i] += a[i];
        somaG[i] += g[i];
        if (primeira) { maxA[i] = a[i]; minA[i] = a[i]; }
        else {
          if (a[i] > maxA[i]) maxA[i] = a[i];
          if (a[i] < minA[i]) minA[i] = a[i];
        }
      }
      primeira = false;
      validas++;
    }
    if (n % 30 == 0) {
      Serial.print(F("CALIBRATING,"));
      Serial.println((int)((long)n * 100L / (long)AMOSTRAS));
    }
    /*  A SERIAL NAO PODE FICAR SURDA AQUI.
        Este e exatamente o instante em que o jogo acabou de abrir a
        porta (o DTR resetou a placa) e esta decidindo se esta COM tem
        Arduino. Uma calibracao que nao responde PING faz o jogo
        descartar a porta CERTA e seguir procurando. */
    processarComandos();
    processarBotoes();
    delay(4);
  }

  if (validas < AMOSTRAS / 2) {
    Serial.println(F("ERROR,CALIB_LEITURA"));
    return;
  }

  // A maquina se mexeu durante a medida? Entao este zero nao presta.
  float dispersao = 0.0f;
  for (uint8_t i = 0; i < 3; i++) {
    const float d = maxA[i] - minA[i];
    if (d > dispersao) dispersao = d;
  }
  if (dispersao > RUIDO_G * 3.0f) {
    Serial.println(F("ERROR,CALIB_MOVIMENTO"));
    return;                    // mantem a base anterior, de proposito
  }

  for (uint8_t i = 0; i < 3; i++) {
    baseAccel[i] = somaA[i] / (float)validas;
    baseGyro[i] = somaG[i] / (float)validas;
  }
  baseIniciada = true;
  amostrasQuietas = 0;

  Serial.print(F("CALIBRATED,"));
  Serial.print(baseAccel[0], 3);
  Serial.print(',');
  Serial.print(baseAccel[1], 3);
  Serial.print(',');
  Serial.println(baseAccel[2], 3);
}

// ---------------------------------------------------------------- golpe
uint8_t indiceEixo() {
  switch (eixoMedicao) {
    case 'Y': return 1;
    case 'Z': return 2;
    default: return 0;
  }
}

/*  A magnitude do giro, e nao a soma dos tres eixos.
    Somar |gx|+|gy|+|gz| soma tres ruidos e infla o numero; a magnitude
    e a grandeza fisica de verdade e nao depende de a montagem estar
    torta. */
float magnitudeGiro(const float *g) {
  const float x = g[0] - baseGyro[0];
  const float y = g[1] - baseGyro[1];
  const float z = g[2] - baseGyro[2];
  return sqrtf(x * x + y * y + z * z);
}

/*  DESCARTA O EVENTO EM ANDAMENTO sem reportar nada.
    Usado quando a forma nao fechou como soco: empurrao sustentado,
    subida lenta demais, ou a janela estourando sem queda. */
void abandonarGolpe() {
  golpeAtivo = false;
  prontoParaGolpe = false;
  amostrasAcima = 0;
  digitalWrite(LED_STATUS, LOW);
  fimDoUltimoGolpeMs = millis();
  amostrasQuietas = 0;
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

  // Primeira leitura depois de ligar: a base comeca de onde o sensor esta.
  if (!baseIniciada) {
    for (uint8_t i = 0; i < 3; i++) { baseAccel[i] = a[i]; baseGyro[i] = g[i]; }
    baseIniciada = true;
    return;
  }

  // Aceleracao dinamica: a leitura crua menos a base viva. E o que tira
  // a gravidade E a inclinacao da montagem, continuamente.
  float din[3];
  for (uint8_t i = 0; i < 3; i++) din[i] = a[i] - baseAccel[i];
  const float giro = magnitudeGiro(g);

  // A amostra e "quieta"? Todos os eixos dentro do ruido, e o giro tambem.
  bool quieta = (fabsf(din[0]) < RUIDO_G && fabsf(din[1]) < RUIDO_G
                 && fabsf(din[2]) < RUIDO_G && giro < RUIDO_DPS);

  if (!golpeAtivo) {
    if (quieta) {
      if (amostrasQuietas < 65000) amostrasQuietas++;
      // Conquistou a autorizacao de socar. Ver `prontoParaGolpe`.
      if (amostrasQuietas >= AMOSTRAS_DE_REPOUSO) prontoParaGolpe = true;
      /*  A BASE SO ANDA ENQUANTO ESTA QUIETO.
          E o que absorve inclinacao e deriva termica sem nunca deixar um
          soco contaminar o proprio zero. */
      for (uint8_t i = 0; i < 3; i++) {
        baseAccel[i] += (a[i] - baseAccel[i]) * BASE_ALFA;
        baseGyro[i] += (g[i] - baseGyro[i]) * BASE_ALFA;
      }
    } else {
      amostrasQuietas = 0;
    }

    const float aEixo = din[indiceEixo()];
    const float aAbs = fabsf(aEixo);

    // AS TRES TRAVAS PARA COMECAR UM GOLPE, e todas precisam passar.
    const bool passouOTempoMorto = (millis() - fimDoUltimoGolpeMs) >= TEMPO_MORTO_MS;

    if (aAbs > accelMinG && prontoParaGolpe && passouOTempoMorto) {
      amostrasAcima++;
      if (amostrasAcima < AMOSTRAS_DE_SUBIDA) return;  // pico de uma amostra nao vale
      golpeAtivo = true;
      prontoParaGolpe = false;   // gasta a autorizacao; reconquista-se no repouso
      golpeInicioMs = millis();
      golpeAbaixoMs = 0;
      instanteDoPicoMs = golpeInicioMs;
      picoG = aAbs;
      velocidadeIntegral = 0.0f;
      velocidadePico = 0.0f;
      picoGyroDps = giro;
      sinalDoGolpe = (aEixo >= 0.0f) ? 1.0f : -1.0f;
      aAnterior = aAbs;
      caiu = false;
      for (uint8_t i = 0; i < 3; i++) baseCongelada[i] = baseAccel[i];
      digitalWrite(LED_STATUS, HIGH);
    } else if (aAbs <= accelMinG) {
      amostrasAcima = 0;
    }
    return;
  }

  // ------------------------------------------------ golpe em andamento
  // A base fica CONGELADA daqui ate o fim: o golpe nao mexe no proprio zero.
  const float aEixoAssinado = (a[indiceEixo()] - baseCongelada[indiceEixo()]) * sinalDoGolpe;
  const float aAbs = fabsf(aEixoAssinado);

  /*  INTEGRACAO POR TRAPEZIO.
      A soma retangular da V2 superestima sistematicamente a subida de um
      impacto -- e superestimar a subida e superestimar a nota. O trapezio
      usa a media entre a amostra anterior e a atual. */
  velocidadeIntegral += ((aAnterior + aEixoAssinado) * 0.5f) * 9.81f * dt;
  aAnterior = aEixoAssinado;
  if (velocidadeIntegral < 0.0f) velocidadeIntegral = 0.0f;
  // A velocidade do golpe e o PICO da integral: depois do pico vem a
  // desaceleracao, que e fisica real e nao deve apagar a medida.
  if (velocidadeIntegral > velocidadePico) velocidadePico = velocidadeIntegral;

  if (aAbs > picoG) {
    picoG = aAbs;
    instanteDoPicoMs = millis();
  }
  if (giro > picoGyroDps) picoGyroDps = giro;

  if (aAbs < accelMinG * FATOR_QUEDA) {
    if (golpeAbaixoMs == 0) golpeAbaixoMs = millis();
    if (millis() - golpeAbaixoMs >= MS_DE_QUEDA) caiu = true;
  } else {
    golpeAbaixoMs = 0;
  }

  const unsigned long duracao = millis() - golpeInicioMs;
  const bool estourou = duracao >= JANELA_MAX_MS;
  if (!caiu && !estourou) return;

  /*  A JANELA ESTOUROU SEM A QUEDA FORMAL: E EMPURRAO OU E SOCO?

      A regra "sem queda, sem soco" e quase certa, e o "quase" custava um
      golpe forte legitimo. Medido na bancada: soco de 14 g num alvo que
      sai balancando forte NAO fecha a queda dentro da janela -- o
      balanco mantem o sinal acima do piso -- e o soco era descartado.
      A pessoa bate com tudo e a maquina nao marca nada.

      O que separa os dois casos nao e a queda ate o piso, e sim ONDE o
      sinal esta quando a janela fecha, comparado ao proprio pico:

        - EMPURRAO SUSTENTADO: a forca continua aplicada, e o sinal
          termina a janela ainda perto do pico.
        - SOCO: o contato ja acabou; o que sobra e o alvo balancando,
          muito abaixo do pico do impacto.

      Metade do pico separa os dois com folga larga, e nao depende de
      calibrar mais nenhum numero. */
  if (!caiu) {
    if (aAbs >= picoG * 0.5f) {
      abandonarGolpe();      // ainda perto do pico: forca sustentada
      return;
    }
    // ja decaiu: foi impacto, e o que sobrou e o alvo balancando
  }

  golpeAtivo = false;
  prontoParaGolpe = false;
  amostrasAcima = 0;
  digitalWrite(LED_STATUS, LOW);
  fimDoUltimoGolpeMs = millis();
  amostrasQuietas = 0;

  if (saturouAccel) Serial.println(F("SATURATION,ACCEL"));
  if (saturouGyro) Serial.println(F("SATURATION,GYRO"));

  // ------------------------------------------------ validacao da forma
  if (duracao < DURACAO_MIN_MS) return;                       // artefato
  if (instanteDoPicoMs - golpeInicioMs > SUBIDA_MAX_MS) return; // subida lenta
  if (picoGyroDps < GIRO_MINIMO_DPS) return;                  // o alvo nao se moveu

  // ------------------------------------------------ medida
  /*  O ACELEROMETRO E A MEDIDA; o giroscopio so assume quando ele
      satura. A V2 usava `max(integral, giro)` sempre -- e era por ai que
      ruido de giro virava nota. */
  float velocidade = velocidadePico;
  if (saturouAccel) {
    const float vGiro = (picoGyroDps * 0.01745329f) * raioMetros;
    if (vGiro > velocidade) velocidade = vGiro;
  }

  if (velocidade < velocidadeMinima) return;   // encostou, nao socou

  ultimaVelocidade = velocidade;
  ultimoPicoG = picoG;

  // A fita sobe no mesmo instante do golpe, sem esperar o jogo.
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

/*  O ESTADO CRU DOS DOIS PINOS, QUATRO VEZES POR SEGUNDO.
    `PINS,1,0` quer dizer START apertado, CREDITO solto. Com INPUT_PULLUP
    o pino em repouso le ALTO e o aperto o leva ao terra, entao o valor
    aqui ja vai invertido: 1 e APERTADO. Se este numero nao muda quando o
    botao e apertado, o problema e ANTES do firmware. */
void enviarPinos() {
  Serial.print(F("PINS,"));
  Serial.print(digitalRead(PINO_BOTAO_START) == LOW ? 1 : 0);
  Serial.print(',');
  Serial.println(digitalRead(PINO_BOTAO_CREDIT) == LOW ? 1 : 0);
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
/*  A TELEMETRIA MOSTRA A ACELERACAO DINAMICA, nao a crua.
    E o numero que a deteccao realmente usa. Mostrar o cru fazia a
    Central exibir ~1 g parado (a gravidade) e quem olhava concluia que o
    sensor estava enlouquecendo. Com o dinamico, sensor parado mostra
    zero -- e isso e verificavel a olho. */
void enviarTelemetria() {
  if (golpeAtivo) return;   // durante o golpe a serial fica livre para o HIT
  float a[3], g[3];
  if (!mpuLer(a, g)) return;
  Serial.print(F("TELEMETRY,"));
  Serial.print(a[0] - baseAccel[0], 2); Serial.print(',');
  Serial.print(a[1] - baseAccel[1], 2); Serial.print(',');
  Serial.print(a[2] - baseAccel[2], 2); Serial.print(',');
  Serial.print(g[0] - baseGyro[0], 1); Serial.print(',');
  Serial.print(g[1] - baseGyro[1], 1); Serial.print(',');
  Serial.print(g[2] - baseGyro[2], 1); Serial.print(',');
  Serial.print(ultimaVelocidade, 2); Serial.print(',');
  Serial.println(ultimoPicoG, 2);
}

// ---------------------------------------------------------------- comandos
void processarComandos() {
  while (Serial.available() > 0) {
    const char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (bufferUso > 0) {
        bufferSerial[bufferUso] = '\0';
        executarComando(bufferSerial);
        bufferUso = 0;
      }
    } else if (bufferUso < sizeof(bufferSerial) - 1) {
      bufferSerial[bufferUso++] = c;
    }
  }
}

void executarComando(const char *cmd) {
  // Comparacao sem diferenciar maiuscula, sem alocar String.
  if (strcasecmp(cmd, "PING") == 0) {
    Serial.println(F("PONG"));
  } else if (strcasecmp(cmd, "RESET") == 0) {
    golpeAtivo = false;
    prontoParaGolpe = false;
    amostrasAcima = 0;
    amostrasQuietas = 0;
    digitalWrite(LED_STATUS, LOW);
    Serial.println(F("OK,RESET"));
  } else if (strcasecmp(cmd, "CALIBRATE") == 0) {
    calibrar();
    Serial.println(F("OK,CALIBRATE"));
  } else if (strcasecmp(cmd, "TEST") == 0) {
    /*  Golpe sintetico: confere a corrente inteira -- Arduino, serial e
        jogo -- sem ninguem socar o saco. Se o TEST aparece na tela e o
        soco real nao, o problema e mecanico, nao de software.
        O valor fica no meio da escala nova (0,30 a 5,20 m/s). */
    Serial.print(F("HIT,2.60,8.00,45,"));
    Serial.println(eixoMedicao);
  } else if (strncasecmp(cmd, "LEDS,", 5) == 0) {
    long permil = atol(cmd + 5);
    if (permil < 0) permil = 0;
    if (permil > 1000) permil = 1000;
    nivelAlvo = (float)permil / 1000.0f;
    fitaComandadaMs = millis();
  } else if (strncasecmp(cmd, "CONFIG,", 7) == 0) {
    configurar(cmd);
  } else {
    Serial.println(F("ERROR,COMANDO"));
  }
}

/*  CONFIG,eixo,raio,vmin,amin[,vmax]
    A placa REVALIDA tudo: um valor absurdo vindo de um arquivo de
    ajustes corrompido nao pode virar uma maquina que nunca detecta nada
    (ou que detecta tudo). */
void configurar(const char *cmd) {
  char copia[52];
  strncpy(copia, cmd, sizeof(copia) - 1);
  copia[sizeof(copia) - 1] = '\0';

  char *campo = strtok(copia, ",");      // "CONFIG"
  campo = strtok(NULL, ",");             // eixo
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  const char e = (char)toupper(campo[0]);
  if (e == 'X' || e == 'Y' || e == 'Z') eixoMedicao = e; else eixoMedicao = 'X';

  campo = strtok(NULL, ",");             // raio
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  raioMetros = constrain(atof(campo), 0.05f, 1.50f);

  campo = strtok(NULL, ",");             // vmin
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  velocidadeMinima = constrain(atof(campo), 0.10f, 20.0f);

  campo = strtok(NULL, ",");             // amin
  if (campo == NULL) { Serial.println(F("ERROR,CONFIG")); return; }
  accelMinG = constrain(atof(campo), 0.5f, 15.0f);

  campo = strtok(NULL, ",");             // vmax (opcional)
  if (campo != NULL) {
    velocidadeMaxima = constrain(atof(campo), velocidadeMinima + 0.5f, 40.0f);
  }

  Serial.println(F("OK,CONFIG"));
}

/*  A COR DE CADA ALTURA -- a mesma escala do jogo: do azul frio ao
    branco estourado, e a fita repete essa escala de baixo para cima. */
#if TEM_FITAS
uint32_t corDaAltura(float f, Adafruit_NeoPixel &fita) {
  if (f < 0.25f)      return fita.Color(0, 90, 200);
  else if (f < 0.50f) return fita.Color(0, 200, 140);
  else if (f < 0.70f) return fita.Color(230, 190, 0);
  else if (f < 0.88f) return fita.Color(255, 90, 0);
  else                return fita.Color(255, 255, 255);
}
#endif

void atualizarFitas() {
#if TEM_FITAS
  const unsigned long agora = millis();
  if (agora - ultimaFitaMs < FITA_QUADRO_MS) return;
  ultimaFitaMs = agora;

  // Passados tres segundos sem comando do jogo, a placa volta a se virar
  // sozinha -- a fita continua funcionando com o PC desligado.
  if (agora - fitaComandadaMs > FITA_COMANDO_VALE_MS) {
    nivelAlvo *= 0.94f;      // decai devagar depois do golpe
    if (nivelAlvo < 0.004f) nivelAlvo = 0.0f;
  }

  nivelFita += (nivelAlvo - nivelFita) * 0.25f;
  if (fabsf(nivelAlvo - nivelFita) < 0.002f) nivelFita = nivelAlvo;

  const int acesos = (int)(nivelFita * (float)LEDS_POR_FITA + 0.5f);
  for (int i = 0; i < LEDS_POR_FITA; i++) {
    const float altura = (float)(i + 1) / (float)LEDS_POR_FITA;
    const uint32_t cor = (i < acesos) ? corDaAltura(altura, fitaEsq) : 0;
    fitaEsq.setPixelColor(i, cor);
    fitaDir.setPixelColor(i, cor);
  }
  fitaEsq.show();
  fitaDir.show();
#endif
}

void setup() {
  Serial.begin(115200);
  pinMode(PINO_BOTAO_START, INPUT_PULLUP);
  pinMode(PINO_BOTAO_CREDIT, INPUT_PULLUP);
  pinMode(LED_STATUS, OUTPUT);
  digitalWrite(LED_STATUS, LOW);

#if TEM_FITAS
  fitaEsq.begin(); fitaEsq.setBrightness(BRILHO_FITA); fitaEsq.show();
  fitaDir.begin(); fitaDir.setBrightness(BRILHO_FITA); fitaDir.show();
#endif

  /*  O `READY` SAI ANTES DE QUALQUER COISA QUE POSSA FALHAR.

      A placa SEMPRE chega ao `loop()`. Sem sensor ela avisa, segue
      funcionando -- botoes, serial, fitas -- e tenta o sensor de novo a
      cada dois segundos. Um fio de I2C mal encaixado que alguem empurre
      de volta passa a funcionar sozinho, sem desligar nada.

      E o `READY` vem primeiro porque e ele que faz o jogo reconhecer
      esta COM como sendo a do Arduino. Qualquer coisa antes dele que
      possa travar -- procurar sensor, calibrar -- e uma porta certa
      sendo descartada como muda. */
  Serial.println(F("READY,PUNCH_MPU6050,V9"));

  Wire.begin();
  Wire.setClock(400000);   // I2C rapido: a leitura nao pode atrasar a amostragem

  ultimaAmostraUs = micros();

  if (ligarMpu()) {
    calibrar();
  } else {
    Serial.println(F("ERROR,NO_MPU"));
  }
  ultimaAmostraUs = micros();
}

/*  Acorda o MPU e o deixa na escala do jogo. Devolve falso se ele nao
    responde -- e nesse caso a placa continua trabalhando sem ele. */
bool ligarMpu() {
  if (!mpuVivo()) {
    mpuPronto = false;
    return false;
  }
  escreverReg(0x6B, 0x01);   // PWR_MGMT_1: acorda, clock do giroscopio X
  escreverReg(0x1A, 0x03);   // CONFIG: DLPF ~44 Hz -- corta ruido, mantem o golpe
  escreverReg(0x1B, 0x18);   // GYRO_CONFIG: +/-2000 graus/s
  escreverReg(0x1C, 0x18);   // ACCEL_CONFIG: +/-16 g
  delay(50);
  mpuPronto = true;
  baseIniciada = false;      // base nova para um sensor recem-ligado
  return true;
}

/*  Tenta o sensor de novo, de dois em dois segundos, enquanto ele
    faltar. E o que permite consertar um fio com a maquina ligada. */
void insistirNoMpu() {
  if (mpuPronto) return;
  const unsigned long agora = millis();
  if (agora - ultimaTentativaMpu < 2000) return;
  ultimaTentativaMpu = agora;
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
    enviarPinos();
  }
  atualizarFitas();
}
