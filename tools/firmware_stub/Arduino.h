#pragma once
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#define HIGH 1
#define LOW 0
#define INPUT_PULLUP 2
#define OUTPUT 1
#define DEG_TO_RAD 0.0174532925f
#define F(x) (x)
typedef uint8_t byte;
unsigned long millis();
unsigned long micros();
void delay(unsigned long);
void pinMode(int, int);
void digitalWrite(int, int);
int digitalRead(int);
long random(long, long);
struct String {
  String(); String(const char*); String(int); String(char);
  const char* c_str() const;
  bool startsWith(const char*) const;
  String substring(int) const;
  long toInt() const;
  void trim();
  void toUpperCase();
  int length() const;
  bool operator==(const char*) const;
  String& operator+=(char);
  String& operator+=(const char*);
};
struct SerialC {
  void begin(long);
  int available();
  int read();
  String readStringUntil(char);
  void print(const char*); void print(char); void print(float, int); void print(int); void print(unsigned long); void print(long);
  void println(const char*); void println(char); void println(float, int); void println(int); void println(unsigned long); void println(long);
};
extern SerialC Serial;
