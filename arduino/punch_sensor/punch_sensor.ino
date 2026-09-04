/*
  PUNCH CHALLENGE - MEDIDOR DE VELOCIDADE
  Placas: Arduino Uno ou Nano
  Sensor: módulo encoder óptico LM393 (VCC, GND, D0 e A0)

  IMPORTANTE:
  - Este firmware mede velocidade. A pontuação é calculada no Godot.
  - Ajuste PULSOS_POR_VOLTA e RAIO_METROS para sua roda/disco.
  - Use fonte e aterramento corretos. Não ligue cargas de potência ao Arduino.
*/

// Conecte a saída digital D0 do módulo ao pino D2 do Arduino.
#define PINO_SENSOR 2
#define LED_STATUS 13

// Quantidade de janelas/ranhuras que passam pelo sensor em uma volta completa.
const uint16_t PULSOS_POR_VOLTA = 20;

// Distância do centro do eixo até o ponto de medição, em metros.
const float RAIO_METROS = 0.100f;

// Filtragem e reconhecimento do golpe.
const unsigned long DEBOUNCE_US = 180;
const unsigned long FIM_MOVIMENTO_US = 140000;
const unsigned long COOLDOWN_MS = 650;
const float VELOCIDADE_MINIMA_MS = 0.35f;

volatile unsigned long ultimoPulsoUs = 0;
volatile unsigned long menorIntervaloUs = 0xFFFFFFFFUL;
volatile uint16_t totalPulsos = 0;
volatile bool houvePulso = false;

unsigned long ultimoEnvioPulsoMs = 0;
unsigned long ultimoGolpeMs = 0;
bool movimentoAtivo = false;
String bufferSerial = "";

void contarPulso() {
  const unsigned long agora = micros();
  const unsigned long intervalo = agora - ultimoPulsoUs;

  if (ultimoPulsoUs != 0 && intervalo < DEBOUNCE_US) {
    return;
  }

  if (ultimoPulsoUs != 0 && intervalo < menorIntervaloUs) {
    menorIntervaloUs = intervalo;
  }

  ultimoPulsoUs = agora;
  totalPulsos++;
  houvePulso = true;
}

void setup() {
  pinMode(PINO_SENSOR, INPUT_PULLUP);
  pinMode(LED_STATUS, OUTPUT);
  digitalWrite(LED_STATUS, LOW);

  Serial.begin(115200);
  attachInterrupt(digitalPinToInterrupt(PINO_SENSOR), contarPulso, FALLING);

  delay(300);
  Serial.println("READY,PUNCH_SENSOR_V1");
}

void loop() {
  processarComandos();

  bool pulsoLocal = false;
  unsigned long ultimoLocal;
  unsigned long menorLocal;
  uint16_t pulsosLocal;

  noInterrupts();
  pulsoLocal = houvePulso;
  houvePulso = false;
  ultimoLocal = ultimoPulsoUs;
  menorLocal = menorIntervaloUs;
  pulsosLocal = totalPulsos;
  interrupts();

  if (pulsoLocal) {
    movimentoAtivo = true;
    digitalWrite(LED_STATUS, HIGH);

    if (menorLocal != 0xFFFFFFFFUL && millis() - ultimoEnvioPulsoMs >= 45) {
      const float frequencia = 1000000.0f / (float)menorLocal;
      Serial.print("PULSE,");
      Serial.println(frequencia, 2);
      ultimoEnvioPulsoMs = millis();
    }
  }

  if (movimentoAtivo && ultimoLocal != 0 && (micros() - ultimoLocal) > FIM_MOVIMENTO_US) {
    finalizarMovimento(menorLocal, pulsosLocal);
    movimentoAtivo = false;
    digitalWrite(LED_STATUS, LOW);
    limparMedicao();
  }
}

void finalizarMovimento(unsigned long menorIntervalo, uint16_t pulsos) {
  if (pulsos < 2 || menorIntervalo == 0 || menorIntervalo == 0xFFFFFFFFUL) {
    return;
  }

  const float frequenciaHz = 1000000.0f / (float)menorIntervalo;
  const float voltasPorSegundo = frequenciaHz / (float)PULSOS_POR_VOLTA;
  const float velocidadeMs = voltasPorSegundo * 2.0f * PI * RAIO_METROS;

  if (velocidadeMs < VELOCIDADE_MINIMA_MS || millis() - ultimoGolpeMs < COOLDOWN_MS) {
    return;
  }

  ultimoGolpeMs = millis();
  Serial.print("HIT,");
  Serial.print(velocidadeMs, 3);
  Serial.print(",");
  Serial.print(frequenciaHz, 2);
  Serial.print(",");
  Serial.println(pulsos);
}

void limparMedicao() {
  noInterrupts();
  ultimoPulsoUs = 0;
  menorIntervaloUs = 0xFFFFFFFFUL;
  totalPulsos = 0;
  houvePulso = false;
  interrupts();
}

void processarComandos() {
  while (Serial.available() > 0) {
    const char c = Serial.read();
    if (c == '\n' || c == '\r') {
      bufferSerial.trim();
      bufferSerial.toUpperCase();
      if (bufferSerial == "PING") {
        Serial.println("PONG");
      } else if (bufferSerial == "RESET") {
        limparMedicao();
        Serial.println("OK,RESET");
      }
      bufferSerial = "";
    } else if (bufferSerial.length() < 40) {
      bufferSerial += c;
    }
  }
}
