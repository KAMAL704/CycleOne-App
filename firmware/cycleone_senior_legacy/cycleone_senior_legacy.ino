#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <EEPROM.h>
#include <AES.h>
#include <CBC.h>
#include <CryptoAES_CBC.h>

#define SERVER_SSID "CycleOneS1"
#define SERVER_PASS "CycleOne"
#define KEY "1E171366E3EDDCE2923BC768623606F1"

#define RELAY_PIN1 D6
#define RELAY_PIN2 D7

constexpr uint8_t kLocked = 0;
constexpr uint8_t kUnlocked = 1;
constexpr size_t kTokenLength = 40;
constexpr size_t kPayloadLength = 16;
constexpr uint32_t kClientWaitMs = 2000;
constexpr uint32_t kTokenReadTimeoutMs = 8000;

CBC<AES128> aes128;
WiFiServer server(80);

IPAddress ip(10, 10, 10, 10);
IPAddress gateway(10, 10, 10, 10);
IPAddress subnet(255, 255, 255, 0);

volatile uint8_t unlocked = kLocked;

void sendError(WiFiClient *client, const String &message);
void sendStatusWithoutRfidPing(WiFiClient *client, bool strike);
void lock();
void unlock();

int hexCharToInt(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

int hexStringToBytes(const char *hexString, int len, unsigned char *bytes) {
  if (hexString == nullptr || bytes == nullptr || len < 0 || (len % 2) != 0) {
    return -1;
  }
  for (int i = 0; i < len; i += 2) {
    const int high = hexCharToInt(hexString[i]);
    const int low = hexCharToInt(hexString[i + 1]);
    if (high < 0 || low < 0) return -2;
    bytes[i / 2] = static_cast<unsigned char>((high << 4) | low);
  }
  return 0;
}

// TCP is a stream; one read() is not guaranteed to return the full packet.
bool readExact(WiFiClient *client, uint8_t *bytes, size_t length,
               uint32_t timeoutMs) {
  size_t received = 0;
  const uint32_t started = millis();
  while (received < length && client->connected() &&
         millis() - started < timeoutMs) {
    while (client->available() && received < length) {
      const int value = client->read();
      if (value < 0) return false;
      bytes[received++] = static_cast<uint8_t>(value);
    }
    if (received < length) {
      delay(1);
      yield();
    }
  }
  return received == length;
}

// Decrypts the senior/current transformed token and returns its requested
// state. The token's first 8 bytes are the verification nonce.
static inline int8_t isRespOk(const unsigned char *iv,
                              const uint64_t verificationInt,
                              const unsigned char *serverResp) {
  unsigned char decryptedResp[kPayloadLength] = {0};
  aes128.setIV(iv, kPayloadLength);
  // CryptoAES_CBC decrypt() returns void.
  aes128.decrypt(decryptedResp, serverResp, kPayloadLength);

  uint64_t decryptedNonce = 0;
  memcpy(&decryptedNonce, decryptedResp, sizeof(decryptedNonce));
  if (verificationInt != decryptedNonce) return -1;

  const int8_t desired = static_cast<int8_t>(decryptedResp[8]);
  if (desired != kLocked && desired != kUnlocked) return -1;
  return desired;
}

int encryptWithRandomIv(uint8_t *inputBuf, unsigned int inputLen,
                        uint8_t *outputBuf, unsigned int outputBufLen) {
  const int outputLen = static_cast<int>(inputLen) + 16;
  if (outputBuf == nullptr || inputBuf == nullptr ||
      outputBufLen < static_cast<unsigned int>(outputLen)) {
    return -1;
  }
  for (int i = 0; i < outputLen; ++i) outputBuf[i] = 0;
  for (int i = 0; i < 16; ++i) {
    outputBuf[i] = static_cast<uint8_t>(random(0, 256));
  }
  aes128.setIV(outputBuf, 16);
  // CryptoAES_CBC encrypt() returns void.
  aes128.encrypt(&outputBuf[16], inputBuf, inputLen);
  return outputLen;
}

void handleTrigger(WiFiClient *client) {
  uint8_t request[kTokenLength] = {0};
  if (!readExact(client, request, kTokenLength, kTokenReadTimeoutMs)) {
    sendError(client, "Invalid data length");
    Serial.println(F("T rejected: incomplete token"));
    return;
  }

  uint64_t verificationInt = 0;
  memcpy(&verificationInt, request, sizeof(verificationInt));
  const unsigned char *iv = request + 8;
  const unsigned char *encryptedResponse = request + 24;
  const int8_t responseState =
      isRespOk(iv, verificationInt, encryptedResponse);

  if (responseState < 0) {
    sendError(client, "Invalid Server Response");
    Serial.println(F("T rejected: invalid legacy/current token"));
    return;
  }

  if (responseState == unlocked) {
    // Senior behavior: report desynchronisation without pulsing a relay.
    Serial.println(F("T rejected: requested state already set"));
    sendStatusWithoutRfidPing(client, true);
    return;
  }

  if (responseState == kLocked) {
    lock();
  } else {
    unlock();
  }
  sendStatusWithoutRfidPing(client, false);
}

void sendError(WiFiClient *client, const String &message) {
  // The first two bytes preserve the senior error framing (status + length),
  // while the fixed 41-byte frame keeps the new app's TCP reader synchronized.
  uint8_t frame[kTokenLength + 1] = {0};
  frame[0] = 1;
  const size_t length = min(message.length(), kTokenLength - 2);
  frame[1] = static_cast<uint8_t>(length);
  memcpy(frame + 2, message.c_str(), length);
  client->write(frame, sizeof(frame));
  client->flush();
}

void sendStatusWithoutRfidPing(WiFiClient *client, bool strike) {
  uint8_t response[40] = {0};
  for (int i = 0; i < 8; ++i) response[i] = random(0, 256);

  uint8_t rawData[kPayloadLength] = {0};
  for (int i = 0; i < 8; ++i) rawData[i] = response[i];
  rawData[8] = strike ? static_cast<uint8_t>(2 | unlocked) : unlocked;
  // Bytes 9..14 are checked by the new Supabase token transformer.
  WiFi.softAPmacAddress(&rawData[9]);

  const int encryptedLength =
      encryptWithRandomIv(rawData, kPayloadLength, response + 8, 32);
  if (encryptedLength != 32) {
    sendError(client, "Encryption failed");
    return;
  }
  client->write(static_cast<uint8_t>(0));
  client->write(response, encryptedLength + 8);  // status + 40-byte token
  client->flush();
}

void sendPresenceStatus(WiFiClient *client) {
  client->write(static_cast<uint8_t>(0));
  client->write(static_cast<uint8_t>(unlocked));
  // No reed/IR sensor is used by this senior wiring. A locked dock is the
  // conservative presence signal expected by both app generations.
  client->write(unlocked == kLocked ? static_cast<uint8_t>(1)
                                    : static_cast<uint8_t>(0));
  client->flush();
}

void setup() {
  Serial.begin(74880);

  pinMode(RELAY_PIN1, OUTPUT);
  pinMode(RELAY_PIN2, OUTPUT);
  digitalWrite(RELAY_PIN1, LOW);
  digitalWrite(RELAY_PIN2, LOW);

  unsigned char key[16] = {0};
  if (hexStringToBytes(KEY, 32, key) != 0) {
    Serial.println(F("Invalid AES key"));
    while (true) delay(1000);
  }
  aes128.setKey(key, 16);

  EEPROM.begin(16);
  const uint8_t savedState = EEPROM.read(0);
  if (savedState == kUnlocked) {
    unlock();
  } else {
    lock();
  }

  randomSeed(static_cast<uint32_t>(micros()) ^ ESP.getChipId());
  WiFi.mode(WIFI_AP);
  WiFi.disconnect();
  WiFi.setPhyMode(WIFI_PHY_MODE_11B);
  WiFi.setOutputPower(20.5);
  WiFi.setSleepMode(WIFI_NONE_SLEEP);
  WiFi.softAPConfig(ip, gateway, subnet);
  // false = visible AP; required for Android Wi-Fi discovery.
  WiFi.softAP(SERVER_SSID, SERVER_PASS, 1, false, 4);
  delay(100);

  server.begin();
  Serial.println(F("CycleOne dual-compatible lock ready"));
  Serial.print(F("IP="));
  Serial.println(WiFi.softAPIP());
  Serial.print(F("BSSID="));
  Serial.println(WiFi.softAPmacAddress());
  Serial.print(F("STATE="));
  Serial.println(unlocked ? F("unlocked") : F("locked"));
}

void loop() {
  WiFiClient client = server.accept();
  if (client) {
    client.setTimeout(kTokenReadTimeoutMs);
    const uint32_t started = millis();
    while (client.connected() && !client.available() &&
           millis() - started < kClientWaitMs) {
      delay(1);
      yield();
    }

    // Both app generations may send S -> U -> T on one TCP connection.
    while (client.connected()) {
      if (!client.available()) {
        delay(1);
        yield();
        continue;
      }

      const int command = client.read();
      switch (command) {
        case 'S':
          client.write(static_cast<uint8_t>(0));
          client.write(static_cast<uint8_t>(unlocked));
          client.flush();
          break;
        case 'P':
          // New CycleOne app inventory probe.
          sendPresenceStatus(&client);
          break;
        case 'U':
          // Senior and new app secure token request.
          sendStatusWithoutRfidPing(&client, false);
          break;
        case 'T':
          // Senior and new app transformed-token command.
          handleTrigger(&client);
          break;
        default:
          Serial.printf("Unknown command: %c\n", command);
          client.stop();
          break;
      }
    }
    client.stop();
  }

  while (Serial.available()) {
    const char command = static_cast<char>(Serial.read());
    if (command == 'm') {
      Serial.print(F("IP="));
      Serial.println(WiFi.softAPIP());
      Serial.print(F("BSSID="));
      Serial.println(WiFi.softAPmacAddress());
    } else if (command == 's') {
      Serial.print(F("STATE="));
      Serial.println(unlocked ? F("unlocked") : F("locked"));
    } else if (command == 'l') {
      lock();
    } else if (command == 'u') {
      unlock();
    }
  }
  yield();
}

void lock() {
  Serial.println(F("Lock"));
  digitalWrite(RELAY_PIN1, HIGH);
  digitalWrite(RELAY_PIN2, LOW);
  delay(200);
  digitalWrite(RELAY_PIN1, LOW);
  unlocked = kLocked;
  EEPROM.write(0, unlocked);
  EEPROM.commit();
}

void unlock() {
  Serial.println(F("Unlock"));
  digitalWrite(RELAY_PIN1, LOW);
  digitalWrite(RELAY_PIN2, HIGH);
  delay(200);
  digitalWrite(RELAY_PIN2, LOW);
  unlocked = kUnlocked;
  EEPROM.write(0, unlocked);
  EEPROM.commit();
}
