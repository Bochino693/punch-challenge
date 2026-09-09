#pragma once
#include <stdint.h>
struct TwoWire {
  void begin(); void setClock(long);
  void beginTransmission(int); void write(int); int endTransmission(int v = 1);
  int requestFrom(int, int); int available(); int read();
};
extern TwoWire Wire;
