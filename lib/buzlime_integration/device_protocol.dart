
import 'dart:convert';

String encode(Map<String, dynamic> json) => jsonEncode(json) + '\n';

Map<String, dynamic>? tryDecode(String line) {
  try { 
    return jsonDecode(line) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
