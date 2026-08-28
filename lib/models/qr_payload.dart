import '../core/errors/app_exception.dart';

enum QrKind { cycle, stand }

class QrPayload {
  const QrPayload._(this.kind, this.id);

  final QrKind kind;
  final String id;

  /// Accepts only the canonical, server-resolved CycleOne QR form.
  /// No MAC address or arbitrary device address is trusted from a QR code.
  factory QrPayload.parse(String raw, {required QrKind expectedKind}) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'cycleone') {
      throw const AppException('This is not a CycleOne QR code.');
    }

    final kind = switch (uri.host) {
      'cycle' => QrKind.cycle,
      'stand' => QrKind.stand,
      _ => throw const AppException('The QR code has an unknown CycleOne type.'),
    };
    if (kind != expectedKind || uri.pathSegments.length != 1) {
      throw AppException('Please scan a ${expectedKind.name} QR code.');
    }

    final id = uri.pathSegments.single;
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(id)) {
      throw const AppException('The QR code identifier is invalid.');
    }
    return QrPayload._(kind, id);
  }
}
