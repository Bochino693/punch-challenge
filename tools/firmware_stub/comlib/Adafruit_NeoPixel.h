#pragma once
#include <stdint.h>
#define NEO_GRB 0
#define NEO_KHZ800 0
struct Adafruit_NeoPixel {
  Adafruit_NeoPixel(int, int, int);
  void begin(); void show(); void clear();
  void setBrightness(int);
  void setPixelColor(int, uint32_t);
  uint32_t Color(uint8_t, uint8_t, uint8_t);
};
