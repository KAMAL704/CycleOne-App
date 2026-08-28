#pragma once

// Copy this file to secrets.h before compiling. Do not commit secrets.h.
// Provision the same AES-128 key as the CYCLEONE_AES_KEY_HEX Supabase Edge
// Function secret. The mobile application must never contain this key.
#define CYCLEONE_AP_SSID "CycleOneS1"
#define CYCLEONE_AP_PASSWORD "CycleOne"
#define CYCLEONE_AES_KEY_HEX "1E171366E3EDDCE2923BC768623606F1"

// The mobile app connects to this fixed address on the ESP access point.
// These comma-separated values are passed to the ESP8266 IPAddress class.
#define CYCLEONE_AP_IP 10, 10, 10, 10
#define CYCLEONE_AP_GATEWAY 10, 10, 10, 1
#define CYCLEONE_AP_SUBNET 255, 255, 255, 0

// Single-relay fallback pin. In the required dual-relay setup this macro is
// ignored; D6 and D7 below are used instead.
#define CYCLEONE_RELAY_PIN D6
#define CYCLEONE_RELAY_ACTIVE HIGH

// Set to 1 for the two-direction relay board. In that mode D6 (GPIO12)
// pulses the lock relay and D7 (GPIO13) pulses the unlock relay. Change
// these two pins only if your physical wiring is different.
#define CYCLEONE_DUAL_RELAY 1
#define CYCLEONE_RELAY_LOCK_PIN D6
#define CYCLEONE_RELAY_UNLOCK_PIN D7
#define CYCLEONE_DUAL_RELAY_ACTIVE HIGH

// A reed/IR sensor is recommended so the app can distinguish a locked empty
// dock from a dock that actually contains a bicycle. If no sensor is wired,
// set this to 0; the firmware then uses the lock state as a conservative
// presence proxy (locked = present, unlocked = absent).
#define CYCLEONE_HAS_PRESENCE_SENSOR 1
#define CYCLEONE_PRESENCE_PIN D5
#define CYCLEONE_PRESENCE_ACTIVE LOW
