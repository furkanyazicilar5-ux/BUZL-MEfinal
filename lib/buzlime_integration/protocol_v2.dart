import 'dart:convert';

/// USB-CDC JSON protocol (newline-delimited)
///
/// Flutter tarafı minimum: sadece komut gönderir ve event dinler.
/// MCU tarafı süreç + MDB ödeme + hata yönetimi.

const int kProtoV = 2;

String encodeLine(Map<String, dynamic> json) => jsonEncode(json) + '\n';

Map<String, dynamic>? tryDecodeLine(String line) {
  try {
    final v = jsonDecode(line);
    if (v is Map<String, dynamic>) return v;
    return null;
  } catch (_) {
    return null;
  }
}

class ProtoError implements Exception {
  final String code;
  final String message;
  ProtoError(this.code, this.message);

  @override
  String toString() => 'ProtoError($code): $message';
}

class ProtoResponse {
  final int id;
  final String cmd;
  final String status; // ok | busy | error
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? error;
  final int v;

  ProtoResponse({
    required this.id,
    required this.cmd,
    required this.status,
    required this.data,
    required this.error,
    required this.v,
  });

  factory ProtoResponse.fromJson(Map<String, dynamic> j) {
    return ProtoResponse(
      id: (j['id'] is num) ? (j['id'] as num).toInt() : int.parse(j['id'].toString()),
      cmd: (j['cmd'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      data: (j['data'] is Map) ? Map<String, dynamic>.from(j['data'] as Map) : null,
      error: (j['error'] is Map) ? Map<String, dynamic>.from(j['error'] as Map) : null,
      v: (j['v'] is num) ? (j['v'] as num).toInt() : kProtoV,
    );
  }

  ProtoError? toError() {
    if (status == 'ok') return null;
    final code = (error?['code'] ?? 'UNKNOWN').toString();
    final msg = (error?['msg'] ?? 'Unknown error').toString();
    return ProtoError(code, msg);
  }
}

class ProtoEvent {
  /// ORDER_STATUS | ORDER_DONE | ORDER_ERROR
  ///
  /// Bazı MCU sürümlerinde `event` yerine `cmd` veya `name` alanı gelebilir.
  final String event;

  /// order_id bazen `orderId` gibi farklı isimle gelebilir.
  final int orderId;
  final Map<String, dynamic> raw;
  final int v;

  ProtoEvent({required this.event, required this.orderId, required this.raw, required this.v});

  factory ProtoEvent.fromJson(Map<String, dynamic> j) {
    final evName = (j['event'] ?? j['cmd'] ?? j['name'] ?? '').toString();
    final oidRaw = j.containsKey('order_id')
        ? j['order_id']
        : (j.containsKey('orderId') ? j['orderId'] : j['orderID']);
    final oid = (oidRaw is num) ? oidRaw.toInt() : int.parse(oidRaw.toString());
    return ProtoEvent(
      event: evName,
      orderId: oid,
      raw: Map<String, dynamic>.from(j),
      v: (j['v'] is num) ? (j['v'] as num).toInt() : kProtoV,
    );
  }
}

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String? asString(dynamic v) => (v == null) ? null : v.toString();

Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}
