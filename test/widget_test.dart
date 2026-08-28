import 'package:flutter_test/flutter_test.dart';

import 'package:cycle_one/models/qr_payload.dart';
import 'package:cycle_one/services/pending_operation_store.dart';

void main() {
  test('accepts only canonical CycleOne QR payloads', () {
    const id = '11111111-1111-4111-8111-111111111111';
    final payload = QrPayload.parse('cycleone://cycle/$id', expectedKind: QrKind.cycle);
    expect(payload.kind, QrKind.cycle);
    expect(payload.id, id);
  });

  test('rejects a QR for the wrong resource type', () {
    expect(
      () => QrPayload.parse('cycleone://stand/11111111-1111-4111-8111-111111111111', expectedKind: QrKind.cycle),
      throwsA(isA<Exception>()),
    );
  });

  test('recovery markers are scoped to the authenticated user', () {
    const operation = PendingOperation(type: PendingOperationType.start, cycleId: 'cycle', standId: 'stand', userId: 'user-a');
    expect(operation.matches(PendingOperationType.start, 'cycle', 'stand', 'user-a'), isTrue);
    expect(operation.matches(PendingOperationType.start, 'cycle', 'stand', 'user-b'), isFalse);
  });
}
