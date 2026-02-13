// lib/core/error_codes.dart
class RefundErrorCodes {
  static const overfreeze = 'overfreeze';
  static const cupDrop = 'cupDrop';
  static const other = 'other';

  static const allowed = {overfreeze, cupDrop, other};

  static bool isValid(String code) => allowed.contains(code);
}
