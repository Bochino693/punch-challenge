#pragma once
#include <stdint.h>
#include <stddef.h>

/*  COPIA FIEL DA API DO Wire DO ARDUINO -- inclusive das armadilhas.

    Este cabecalho e falso: nao fala com hardware nenhum. Mas ele so
    presta se reproduzir a biblioteca de verdade nos pontos em que ela
    morde, e o Wire morde num lugar especifico: `requestFrom` tem DUAS
    versoes, (int,int) e (uint8_t,uint8_t). Chamar com um argumento de
    cada tipo nao e erro -- e AMBIGUIDADE, e o compilador despeja meia
    tela de "candidate 1 / candidate 2" em vermelho sem parar a
    compilacao.

    Um stub com uma versao so nunca acusaria isso, e o aviso continuaria
    aparecendo na maquina do cliente a cada gravacao. Por isso as duas
    estao aqui.
*/
struct TwoWire {
  void begin();
  void setClock(long);
  void beginTransmission(uint8_t);
  void beginTransmission(int);
  size_t write(uint8_t);
  size_t write(const uint8_t*, size_t);
  uint8_t endTransmission();
  uint8_t endTransmission(uint8_t sendStop);
  uint8_t requestFrom(uint8_t, uint8_t);
  uint8_t requestFrom(int, int);
  int available();
  int read();
};
extern TwoWire Wire;
