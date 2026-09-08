/*
  PUNCH CHALLENGE — FIRMWARE V2 (MPU-6050)
  Placas: Arduino Uno / Nano (ATmega328P)
  Sensor: MPU-6050 no barramento I2C (A4 = SDA, A5 = SCL), endereço 0x68.
  Botões: D2 = START, D3 = CREDIT (liga no GND; INPUT_PULLUP interno).

  PROTOCOLO SERIAL (115200 bps, uma linha por mensagem, campos com vírgula):
    Enviados:  READY / CALIBRATING / CALIBRATED / PONG / BUTTON /
               TELEMETRY / HIT / SATURATION / ERROR / OK
    Recebidos: PING / RESET / TEST / CALIBRATE / CONFIG,eixo,raio,vmin,amin
  Referência completa: docs/PROTOCOLO_SERIAL.md no projeto Godot.

  COMO MEDE: a aceleração dinâmica do eixo escolhido (bruta menos o
  repouso calibrado) dispara a medição quando passa de ACCEL_MIN_G.
  Durante o golpe o firmware integra a aceleração para obter a
  velocidade de pico e guarda a aceleração máxima. O giroscópio dá uma
  segunda estimativa (velocidade angular × raio do pêndulo); vale a
  maior das duas. A PONTUAÇÃO é calculada no Godot — aqui sai só medida.
*/

#include <Wire.h>

#define MPU_ADDR 0x68
#define PINO_BOTAO_START 2
#define PINO_BOTAO_CREDIT 3
#define LED_STATUS 13

// Escalas do MPU-6050 com a configuração abaixo (±16 g, ±2000 °/s).
const float LSB_POR_G = 2048.0f;
const float LSB_POR_DPS = 16.4f;

// Ritmo de amostragem e da telemetria.
const unsigned long AMOSTRA_US = 4000;      // 250 Hz
const unsigned long TELEMETRIA_MS = 250;

// Reconhecimento do golpe.
const float FIM_GOLPE_FATOR = 0.40f;        // encerra abaixo de 40% do limiar
const unsigned long FIM_GOLPE_MS = 60;      // ...por este tempo
const unsigned long GOLPE_MAX_MS = 400;     // golpe não dura mais que isso
const unsigned long COOLDOWN_MS = 650;      // um golpe por vez

// Configuração ativa (chega pelo comando CONFIG; padrões sensatos).
char eixoMedicao = 'X';
float raioMetros = 0.45f;
float velocidadeMinima = 0.8f;   // m/s — abaixo disso nem reporta
float accelMinG = 3.5f;          // g — evita balanço/toque como golpe

// Offsets de repouso, medidos na calibração.
float offAccel[3] = {0, 0, 0};   // em g
float offGyro[3] = {0, 0, 0};    // em °/s

// Estado da medição em andamento.
bool golpeAtivo = false;
unsigned long golpeInicioMs = 0;
unsigned long golpeAbaixoMs = 0;
float picoG = 0.0f;
float velocidadeIntegral = 0.0f; // m/s, integração da aceleração
float picoGyroDps = 0.0f;
bool saturouAccel = false;
bool saturouGyro = false;
unsigned long ultimoGolpeMs = 0;

// Última medida, para a telemetria.
float ultimaVelocidade = 0.0f;
float ultimoPicoG = 0.0f;

unsigned long ultimaAmostraUs = 0;
unsigned long ultimaTelemetriaMs = 0;
String bufferSerial = "";

// ---------------------------------------------------------------- MPU-6050
void escreverReg(uint8_t reg, uint8_t valor) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(valor);
  Wire.endTransmission();
}

bool mpuVivo() {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x75); // WHO_AM_I
  if (Wire.endTransmission(false) != 0) return false;
  Wire.requestFrom(MPU_ADDR, (uint8_t)1);
  if (Wire.available() < 1) return false;
  return Wire.read() == 0x68;
}

bool mpuLer(float accelG[3], float gyroDps[3]) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B); // ACCEL_XOUT_H: 14 bytes seguidos (accel, temp, gyro)
  if (Wire.endTransmission(false) != 0) return false;
  Wire.requestFrom(MPU_ADDR, (uint8_t)14);
  if (Wire.available() < 14) return false;
  int16_t bruto[7];
  for (uint8_t i = 0; i < 7; i++) {
    bruto[i] = (int16_t)((Wire.read() << 8) | Wire.read());
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
  // A máquina precisa estar PARADA. A média do repouso vira o zero de
  // cada eixo — é o que tira a gravidade e a inclinação da montagem.
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
  const float giroAbs = fabsf(g[0]) + fabsf(g[1]) + fabsf(g[2]); // soma = robustez à montagem torta

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
  if (velocidadeIntegral < 0.0f) velocidadeIntegral = 0.0f; // pêndulo voltando não desconta
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

  if (velocidade < velocidadeMinima) return; // encostou, não socou

  ultimaVelocidade = velocidade;
  ultimoPicoG = picoG;
  Serial.print(F("HIT,"));
  Serial.print(velocidade, 2);
  Serial.print(',');
  Serial.print(picoG, 2);
  Serial.print(',');
  Serial.print(duracao);
  Serial.print(',');
  Serial.println(eixoMedicao);
}

// ---------------------------------------------------------------- botões
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
    /* Golpe sintético: confere a corrente inteira — Arduino, serial e
       jogo — sem ninguém socar o saco. Se o TEST aparece na tela e o
       soco real não, o problema é mecânico, não de software. */
    Serial.print(F("HIT,7.50,9.20,120,"));
    Serial.println(eixoMedicao);
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
  int campos = sscanf(cmd.c_str(), "CONFIG,%c,%f,%f,%f", &eixo, &raio, &vmin, &amin);
  const bool eixoOk = (eixo == 'X' || eixo == 'Y' || eixo == 'Z');
  const bool faixaOk = raio >= 0.05f && raio <= 1.50f
                       && vmin >= 0.2f && vmin <= 20.0f
                       && amin >= 0.5f && amin <= 15.0f;
  if (campos != 4 || !eixoOk || !faixaOk) {
    Serial.println(F("ERROR,PARAM"));
    return;
  }
  eixoMedicao = eixo;
  raioMetros = raio;
  velocidadeMinima = vmin;
  accelMinG = amin;
  Serial.println(F("OK,CONFIG"));
}

// ---------------------------------------------------------------- ciclo
void setup() {
  pinMode(PINO_BOTAO_START, INPUT_PULLUP);
  pinMode(PINO_BOTAO_CREDIT, INPUT_PULLUP);
  pinMode(LED_STATUS, OUTPUT);
  digitalWrite(LED_STATUS, LOW);

  Serial.begin(115200);
  Wire.begin();
  Wire.setClock(400000); // I2C rápido: a leitura não pode atrasar a amostragem

  if (!mpuVivo()) {
    Serial.println(F("ERROR,NO_MPU"));
    // Sem sensor não há o que medir; pisca o LED até alguém religar.
    while (true) {
      digitalWrite(LED_STATUS, !digitalRead(LED_STATUS));
      delay(200);
    }
  }

  escreverReg(0x6B, 0x01); // PWR_MGMT_1: acorda, clock do giroscópio X
  escreverReg(0x1A, 0x03); // CONFIG: DLPF ~44 Hz — corta ruído, mantém o golpe
  escreverReg(0x1B, 0x18); // GYRO_CONFIG: ±2000 °/s
  escreverReg(0x1C, 0x18); // ACCEL_CONFIG: ±16 g
  delay(100);

  Serial.println(F("READY,PUNCH_MPU6050,V2"));
  calibrar();
  ultimaAmostraUs = micros();
}

void loop() {
  processarComandos();
  processarBotoes();

  if ((long)(micros() - ultimaAmostraUs) >= (long)AMOSTRA_US) {
    processarAmostra();
  }
  if (millis() - ultimaTelemetriaMs >= TELEMETRIA_MS) {
    ultimaTelemetriaMs = millis();
    enviarTelemetria();
  }
}
