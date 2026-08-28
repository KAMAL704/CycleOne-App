# CycleOne

CycleOne is a Flutter campus bicycle-sharing client backed by Supabase and an ESP8266 smart-lock controller. The ride lifecycle is hardware-first: the app verifies the selected cycle and stand, connects to the exact stand BSSID, completes the binary lock protocol, verifies the physical state, and only then commits the ride transaction.

## Repository layout

- `lib/` — Flutter app, Provider state, QR validation, Supabase services, hardware-first ride orchestration, animated theme, Google Maps, and stand activity feed.
- `android/app/src/main/kotlin/com/example/cycleone/MainActivity.kt` — Android Wi-Fi NetworkSpecifier and bound TCP socket bridge.
- `supabase/migrations/20260819000000_cycleone_schema.sql` — tables, RLS, partial unique indexes, and transactional ride RPCs.
- `supabase/functions/transform-token/` — server-side AES-128-CBC token transformation. The AES key is never shipped in Flutter.
- `firmware/cycleone_lock/` — ESP8266 AP/TCP firmware, EEPROM state persistence, and the matching token protocol.

## Prerequisites

- Flutter 3.35+ / Dart 3.11+
- Android SDK with API 29 or newer for `WifiNetworkSpecifier` (the bridge retains a legacy path for older Android versions).
- A Supabase project and the Supabase CLI for migrations/functions.
- An ESP8266 controller per stand and a relay wired to the configured pin.

## Configure Flutter

The public Supabase URL and anon key are build-time defines. The checked-in defaults point at the existing project, but release builds should pass their own values:

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY \
  --dart-define=COLLEGE_EMAIL_DOMAIN=sliet.ac.in
```

Only addresses ending in the configured college domain are accepted. No service-role key or AES key belongs in `--dart-define`.

## Configure Supabase

The Flutter client is already pointed at the project in `AppConfig`. The backend
source in this repository is not deployed automatically. A reachable Supabase
URL alone is not enough: the database migration and the ride RPCs must be
applied to the same project before the app can load stands or start a ride.

Run the read-only contract check before opening the app:

```bash
./scripts/backend_smoke_test.sh
```

The script reads the checked-in defaults automatically; set `SUPABASE_URL` and
`SUPABASE_ANON_KEY` only when testing another project.

If the check reports missing columns or missing `start_cycle_ride`/
`end_cycle_ride`, the project still has the older CycleOne schema. The checked-in
migration now detects that schema, copies compatible rows into the production
tables, and retains the old tables with a `_legacy` suffix for audit. Back up
the project before applying it (or use a fresh Supabase project). Do not put a
service-role key in Flutter or in this script.

1. Link the project and apply the schema:

   ```bash
   supabase link --project-ref lqzazbejzpxjndoegoly
   supabase db push
   ```

   If you are using another Supabase project, replace the project ref and pass
   its URL/key to Flutter with `--dart-define`.

2. Set the Edge Function secret. Use the same 32-hex-character AES-128 key in every controller and in Supabase, but never in the Flutter app:

   ```bash
   supabase secrets set CYCLEONE_AES_KEY_HEX=1E171366E3EDDCE2923BC768623606F1
   for function_name in transform-token invite-user toggle-block-user delete-user reset-user-password; do
     supabase functions deploy "$function_name"
   done
   ```

3. Confirm email settings in Supabase Auth. Production should enable email confirmations and configure SMTP. Local development may leave confirmations disabled.

The migration creates `profiles`, `stands`, `cycles`, and `rides`; RLS limits student reads to their own profile/rides and active stand data. `start_cycle_ride` and `end_cycle_ride` are the only student ride-state write paths. Partial unique indexes prevent two active rides for one user or one cycle.

Legacy stands are intentionally imported as `maintenance` with `UNCONFIGURED`
Wi-Fi values. Before a stand can appear in the student map, an administrator
must enter the controller's real BSSID, AP SSID/password, IP, and port in
Admin → Stands. Imported cycles keep their generated canonical QR codes, but
the student app only counts them after that stand's ESP reports `P = present`.

Create the first administrator by updating a profile directly in the Supabase dashboard (never from the client):

```sql
update public.profiles set role = 'admin' where email = 'kamal_254034051@sliet.ac.in';
```

## Provision a stand and controller

1. Copy `firmware/cycleone_lock/secrets.example.h` to `secrets.h`.
2. Set `CYCLEONE_AP_SSID`, `CYCLEONE_AP_PASSWORD`, the AES key, relay pin, and relay active level. The example config uses the static ESP AP address `10.10.10.10`, matching the app's stand endpoint. For the two-relay setup used by CycleOne, keep `CYCLEONE_DUAL_RELAY 1`, wire D6 (GPIO12) to the lock relay input and D7 (GPIO13) to the unlock relay input, and change `CYCLEONE_DUAL_RELAY_ACTIVE` to `LOW` if the relay board is active-low.
3. Build and flash with PlatformIO:

   ```bash
   cd firmware/cycleone_lock
   pio run --target upload
   pio device monitor
   ```

   The serial monitor is `115200` baud. Type `?` for diagnostics, then use
   `m` to print the AP BSSID/IP, `s` for lock state, `p` for presence, and
   `l`/`u` to pulse lock/unlock while testing the relay wiring before using the
   mobile app.

   Arduino IDE is also supported. Install the ESP8266 board package using
   `https://arduino.esp8266.com/stable/package_esp8266com_index.json`, select
   **NodeMCU 1.0 (ESP-12E Module)**, and install the **Crypto** library by
   Rhys Weatherley from Library Manager. Open
   `firmware/cycleone_lock/cycleone_lock.ino`; keep the copied `secrets.h` in
   the same folder, select the ESP serial port, then use **Verify** followed
   by **Upload**. Open Serial Monitor at `115200` baud.

4. Read the controller's AP BSSID from the serial log or the access point scan. In the Admin → Stands screen, create a stand with that exact `esp_mac`, the same SSID/password, `10.10.10.10`, port `80`, capacity, and coordinates.

The controller speaks a framed binary protocol:

| Request | Response |
| --- | --- |
| `S` | status byte + lock state byte (2 bytes) |
| `P` | status byte + lock state + physical cycle-present byte (3 bytes) |
| `U` | status byte + 40-byte nonce/IV/ciphertext token (41 bytes) |
| `T` + 40-byte transformed token | status byte + 40-byte response (41 bytes) |

The ESP persists `locked`/`unlocked` in EEPROM and does not pulse the relay when the requested state is already set. With the optional reed/IR sensor enabled in `secrets.h`, `P` reports actual bicycle presence; without a sensor it conservatively treats a locked dock as occupied.

Use this repository firmware rather than the older sketch that uses
`ESP_EEPROM.h`, `CryptoAES_CBC.h`, or the legacy response format. The app
expects `P` and the authenticated 40-byte `U`/`T` framing shown above.

The student map uses Google Maps on Android/iOS and the Google Maps JavaScript
loader on web. Restrict the supplied API key in Google Cloud Console by app
package/bundle id, web referrers, and only the Maps SDKs/Places API required by
this project. Tapping a stand loads its five most recent checkout/return events
through the `get_stand_activity` RPC; rider names are shown without exposing
email addresses or user ids.

## Ride flow

The Cycle tab accepts a canonical QR such as `cycleone://cycle/<UUID>` or `cycleone://stand/<UUID>`. QR contents are parsed as identifiers only; the app always resolves the record from Supabase. Start and return operations show progress, serialize hardware commands, bind sockets to the selected Wi-Fi network, verify the requested BSSID, and never retry an ambiguous `T` command.

If hardware succeeds but a Supabase RPC fails, a recovery record is stored locally. The UI asks the rider to repeat the same operation; recovery never sends another relay pulse. A different cycle/stand is rejected until the pending operation is committed.

## Test and build

```bash
flutter analyze
flutter test
flutter build apk --debug
```

For a phone-sized production build, use the optimized per-ABI command. Install
`app-arm64-v8a-release.apk` on almost every modern Android phone; do not install
the debug APK because it contains the Dart kernel and development symbols.

```bash
./scripts/build_phone_release.sh
```

The automated tests cover canonical QR acceptance and wrong-resource rejection. End-to-end lock tests require a flashed controller, a configured stand, and a reachable Supabase project; the hardware/database ordering is implemented in `RideOperationService`, the Android bridge, the firmware, and the two transactional RPCs.

## Operational notes

- Android location and nearby-Wi-Fi permissions are required by the platform before connecting to an ESP access point.
- Do not use the legacy HTTP `/lock` or `/unlock` endpoints; CycleOne uses only the authenticated TCP protocol above.
- Do not log AES keys, transformed tokens, passwords, or service-role credentials.
- A returned bicycle is not marked available until the destination ESP confirms the physical lock and `end_cycle_ride` commits the cycle move and ride completion in one transaction.
- A stand has one capacity-checked cycle slot by default. Cycle placement, removal, and assignment use administrator RPCs; direct client cycle writes are revoked.
- The inventory sync verifies the exact stand BSSID before accepting the ESP's physical presence result. A cycle is shown as available only when the database says available and the ESP has freshly reported `present`; `unknown` and `absent` are hidden and cannot be unlocked.
- The legacy prototype tables and unused `device_logs` table are removed by the migrations; the remaining public tables are `profiles`, `stands`, `cycles`, `rides`, `settings`, and `feedback`.
