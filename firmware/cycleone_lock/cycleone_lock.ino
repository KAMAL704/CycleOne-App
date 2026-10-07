// CycleOne ESP8266 smart-lock firmware.
// Binary TCP protocol: S -> 2 bytes, P -> 3 bytes, U -> 41 bytes,
// T+40 bytes -> 41 bytes.
// Install the ESP8266-compatible CryptoAES_CBC library and create secrets.h
// from secrets.example.h before compiling.

#include <Arduino.h>
#include <EEPROM.h>
#include <ESP8266WiFi.h>
#include <user_interface.h>
// CryptoAES_CBC is the ESP8266-compatible fork. It intentionally exposes
// the same AES/CBC headers but encrypt()/decrypt() return void.
#include <CryptoAES_CBC.h>
#include <AES.h>
#include <CBC.h>
#include "secrets.h"

// Keep older local secrets.h copies buildable while users migrate to the
// current template. New installations should copy secrets.example.h.
#ifndef CYCLEONE_AP_IP
#define CYCLEONE_AP_IP 10, 10, 10, 10
#endif
#ifndef CYCLEONE_AP_GATEWAY
#define CYCLEONE_AP_GATEWAY 10, 10, 10, 1
#endif
#ifndef CYCLEONE_AP_SUBNET
#define CYCLEONE_AP_SUBNET 255, 255, 255, 0
#endif
#ifndef CYCLEONE_DUAL_RELAY_ACTIVE
#define CYCLEONE_DUAL_RELAY_ACTIVE HIGH
#endif

namespace {
constexpr uint16_t kPort = 80;
constexpr size_t kTokenLength = 40;
constexpr size_t kPayloadLength = 16;
constexpr uint8_t kProtocolVersion = 1;
constexpr uint8_t kStatusOk = 0;
constexpr uint8_t kStatusMalformed = 1;
constexpr uint8_t kStatusExpired = 2;
constexpr uint8_t kStatusUnauthorised = 3;
constexpr uint8_t kLocked = 0;
constexpr uint8_t kUnlocked = 1;
constexpr uint32_t kTokenTtlMs = 15000;
constexpr uint32_t kRelayPulseMs = 500;
constexpr uint8_t kEepromSize = 8;
constexpr uint8_t kStateAddress = 0;
constexpr uint8_t kStateMarkerAddress = 1;
constexpr uint8_t kStateMarker = 0xC1;

WiFiServer server(kPort);
uint8_t aesKey[16];
uint8_t ownMac[6];
uint8_t lockState = kLocked;
uint8_t outstandingNonce[8];
uint32_t outstandingAt = 0;
bool nonceOutstanding = false;

bool hexToBytes(const char* hex, uint8_t* output, size_t length) {
  for (size_t i = 0; i < length; ++i) {
    const char high = hex[i * 2];
    const char low = hex[i * 2 + 1];
    const auto nibble = [](char value) -> int {
      if (value >= '0' && value <= '9') return value - '0';
      if (value >= 'a' && value <= 'f') return value - 'a' + 10;
      if (value >= 'A' && value <= 'F') return value - 'A' + 10;
      return -1;
    };
    const int a = nibble(high);
    const int b = nibble(low);
    if (a < 0 || b < 0) return false;
    output[i] = static_cast<uint8_t>((a << 4) | b);
  }
  return hex[length * 2] == '\0';
}

bool parseMac(const String& value, uint8_t* bytes) {
  unsigned int parsed[6];
  if (sscanf(value.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x", &parsed[0], &parsed[1], &parsed[2], &parsed[3], &parsed[4], &parsed[5]) != 6) {
    return false;
  }
  for (uint8_t index = 0; index < 6; ++index) bytes[index] = static_cast<uint8_t>(parsed[index]);
  return true;
}

void randomBytes(uint8_t* bytes, size_t length) {
  for (size_t index = 0; index < length; ++index) bytes[index] = static_cast<uint8_t>(os_random() & 0xFF);
}

bool equalBytes(const uint8_t* left, const uint8_t* right, size_t length) {
  uint8_t difference = 0;
  for (size_t index = 0; index < length; ++index) difference |= left[index] ^ right[index];
  return difference == 0;
}

bool readExact(WiFiClient& client, uint8_t* bytes, size_t length, uint32_t timeoutMs) {
  size_t received = 0;
  const uint32_t started = millis();
  while (received < length && client.connected() && millis() - started < timeoutMs) {
    while (client.available() && received < length) {
      const int value = client.read();
      if (value < 0) return false;
      bytes[received++] = static_cast<uint8_t>(value);
    }
    delay(1);
    yield();
  }
  return received == length;
}

void writeResponse(WiFiClient& client, uint8_t status, const uint8_t* payload) {
  client.write(status);
  client.write(payload, kTokenLength);
  client.flush();
}

void writeTokenError(WiFiClient& client, uint8_t status) {
  uint8_t empty[kTokenLength] = {0};
  writeResponse(client, status, empty);
}

void writeStatus(WiFiClient& client) {
  client.write(kStatusOk);
  client.write(lockState);
  client.flush();
}

bool cyclePresent() {
#if CYCLEONE_HAS_PRESENCE_SENSOR
  return digitalRead(CYCLEONE_PRESENCE_PIN) == CYCLEONE_PRESENCE_ACTIVE;
#else
  // Without a physical sensor, a locked dock is the only safe presence proxy.
  return lockState == kLocked;
#endif
}

void writePresenceStatus(WiFiClient& client) {
  client.write(kStatusOk);
  client.write(lockState);
  client.write(cyclePresent() ? 1 : 0);
  client.flush();
}

void loadLockState() {
  EEPROM.begin(kEepromSize);
  if (EEPROM.read(kStateMarkerAddress) == kStateMarker) {
    const uint8_t stored = EEPROM.read(kStateAddress);
    lockState = stored == kUnlocked ? kUnlocked : kLocked;
  } else {
    EEPROM.write(kStateAddress, kLocked);
    EEPROM.write(kStateMarkerAddress, kStateMarker);
    EEPROM.commit();
  }
}

void setLockState(uint8_t nextState) {
  if (nextState == lockState) return; // Never pulse relay for an unchanged state.
#if CYCLEONE_DUAL_RELAY
  const uint8_t pulsePin = nextState == kLocked ? CYCLEONE_RELAY_LOCK_PIN : CYCLEONE_RELAY_UNLOCK_PIN;
  digitalWrite(pulsePin, CYCLEONE_DUAL_RELAY_ACTIVE);
  delay(kRelayPulseMs);
  digitalWrite(pulsePin, CYCLEONE_DUAL_RELAY_ACTIVE == HIGH ? LOW : HIGH);
#else
  digitalWrite(CYCLEONE_RELAY_PIN, CYCLEONE_RELAY_ACTIVE);
  delay(kRelayPulseMs);
  digitalWrite(CYCLEONE_RELAY_PIN, CYCLEONE_RELAY_ACTIVE == HIGH ? LOW : HIGH);
#endif
  lockState = nextState;
  EEPROM.write(kStateAddress, lockState);
  EEPROM.write(kStateMarkerAddress, kStateMarker);
  EEPROM.commit();
}

bool encryptPayload(const uint8_t* payload, const uint8_t* iv, uint8_t* ciphertext) {
  CBC<AES128> cbc;
  if (!cbc.setKey(aesKey, sizeof(aesKey)) || !cbc.setIV(iv, 16)) {
    cbc.clear();
    return false;
  }
  cbc.encrypt(ciphertext, payload, kPayloadLength);
  cbc.clear();
  return true;
}

bool decryptPayload(const uint8_t* ciphertext, const uint8_t* iv, uint8_t* payload) {
  CBC<AES128> cbc;
  if (!cbc.setKey(aesKey, sizeof(aesKey)) || !cbc.setIV(iv, 16)) {
    cbc.clear();
    return false;
  }
  cbc.decrypt(payload, ciphertext, kPayloadLength);
  cbc.clear();
  return true;
}

void handleU(WiFiClient& client) {
  uint8_t token[kTokenLength];
  uint8_t payload[kPayloadLength] = {0};
  randomBytes(outstandingNonce, sizeof(outstandingNonce));
  randomBytes(token + 8, 16);
  memcpy(payload, outstandingNonce, 8);
  payload[8] = lockState;
  memcpy(payload + 9, ownMac, 6);
  payload[15] = kProtocolVersion;
  memcpy(token, outstandingNonce, 8);
  if (!encryptPayload(payload, token + 8, token + 24)) {
    writeTokenError(client, kStatusMalformed);
    return;
  }
  outstandingAt = millis();
  nonceOutstanding = true;
  writeResponse(client, kStatusOk, token);
}

void handleT(WiFiClient& client) {
  uint8_t token[kTokenLength];
  uint8_t payload[kPayloadLength];
  if (!readExact(client, token, kTokenLength, 5000)) return;
  if (!nonceOutstanding || millis() - outstandingAt > kTokenTtlMs || !equalBytes(token, outstandingNonce, 8)) {
    nonceOutstanding = false;
    writeTokenError(client, kStatusExpired);
    return;
  }
  nonceOutstanding = false; // transformed tokens are single-use, even if validation fails.
  if (!decryptPayload(token + 24, token + 8, payload) ||
      !equalBytes(payload, token, 8) ||
      !equalBytes(payload + 9, ownMac, 6) ||
      // Version 0 is the senior app's legacy token. It authenticates the
      // same nonce and AP MAC but has no protocol-version byte; accepting it
      // keeps this controller interoperable with both app generations.
      (payload[15] != 0 && payload[15] != kProtocolVersion) ||
      (payload[8] != kLocked && payload[8] != kUnlocked)) {
    writeTokenError(client, kStatusUnauthorised);
    return;
  }
  setLockState(payload[8]);
  // The complete 41-byte response is required by the Android bridge. Echoing
  // the authenticated transformed token introduces no new secret material.
  writeResponse(client, kStatusOk, token);
}

void handleSerialDiagnostics() {
  while (Serial.available()) {
    const char command = static_cast<char>(Serial.read());
    switch (command) {
      case '?':
        Serial.println(F("Commands: m=network, s=lock state, p=presence, l=lock, u=unlock"));
        break;
      case 'm':
        Serial.print(F("SSID="));
        Serial.println(CYCLEONE_AP_SSID);
        Serial.print(F("IP="));
        Serial.println(WiFi.softAPIP());
        Serial.print(F("BSSID="));
        Serial.println(WiFi.softAPmacAddress());
        break;
      case 's':
        Serial.print(F("LOCK_STATE="));
        Serial.println(lockState == kLocked ? F("locked") : F("unlocked"));
        break;
      case 'p':
        Serial.print(F("CYCLE_PRESENT="));
        Serial.println(cyclePresent() ? F("present") : F("absent"));
        break;
      case 'l':
        setLockState(kLocked);
        Serial.println(F("LOCK_COMMAND_DONE"));
        break;
      case 'u':
        setLockState(kUnlocked);
        Serial.println(F("UNLOCK_COMMAND_DONE"));
        break;
      default:
        break;
    }
  }
}
} // namespace

void setup() {
  Serial.begin(115200);
#if CYCLEONE_DUAL_RELAY
  pinMode(CYCLEONE_RELAY_LOCK_PIN, OUTPUT);
  pinMode(CYCLEONE_RELAY_UNLOCK_PIN, OUTPUT);
  digitalWrite(CYCLEONE_RELAY_LOCK_PIN, CYCLEONE_DUAL_RELAY_ACTIVE == HIGH ? LOW : HIGH);
  digitalWrite(CYCLEONE_RELAY_UNLOCK_PIN, CYCLEONE_DUAL_RELAY_ACTIVE == HIGH ? LOW : HIGH);
#else
  pinMode(CYCLEONE_RELAY_PIN, OUTPUT);
  digitalWrite(CYCLEONE_RELAY_PIN, CYCLEONE_RELAY_ACTIVE == HIGH ? LOW : HIGH);
#endif
#if CYCLEONE_HAS_PRESENCE_SENSOR
  pinMode(CYCLEONE_PRESENCE_PIN, INPUT_PULLUP);
#endif
  if (!hexToBytes(CYCLEONE_AES_KEY_HEX, aesKey, sizeof(aesKey))) {
    Serial.println(F("Invalid CYCLEONE_AES_KEY_HEX"));
    while (true) delay(1000);
  }
  loadLockState();
  WiFi.mode(WIFI_AP);
  IPAddress apIp(CYCLEONE_AP_IP);
  IPAddress apGateway(CYCLEONE_AP_GATEWAY);
  IPAddress apSubnet(CYCLEONE_AP_SUBNET);
  if (!WiFi.softAPConfig(apIp, apGateway, apSubnet)) {
    Serial.println(F("Failed to configure access point IP"));
    while (true) delay(1000);
  }
  if (!WiFi.softAP(CYCLEONE_AP_SSID, CYCLEONE_AP_PASSWORD)) {
    Serial.println(F("Failed to start access point"));
    while (true) delay(1000);
  }
  if (!parseMac(WiFi.softAPmacAddress(), ownMac)) {
    Serial.println(F("Could not read AP MAC"));
    while (true) delay(1000);
  }
  server.begin();
  Serial.println(F("CycleOne lock ready"));
}

void loop() {
  handleSerialDiagnostics();
  WiFiClient client = server.available();
  if (!client) {
    yield();
    return;
  }
  client.setTimeout(5000);
  while (client.connected()) {
    if (!client.available()) {
      delay(1);
      yield();
      continue;
    }
    const int command = client.read();
    if (command == 'S') writeStatus(client);
    else if (command == 'P') writePresenceStatus(client);
    else if (command == 'U') handleU(client);
    else if (command == 'T') handleT(client);
    else {
      // Unknown bytes cannot be safely framed; close and force a clean session.
      client.stop();
    }
  }
}
