import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MachineService {
  final String machineId;
  late final DocumentReference machineRef;

  MachineService({required this.machineId})
      : machineRef = FirebaseFirestore.instance.collection('machines').doc(machineId);

  Stream<Map<String, dynamic>> get machineStream => machineRef.snapshots().map(
          (doc) => doc.data() as Map<String, dynamic>? ?? {});

  Future<void> updateStock(String field, int delta, int maxVal) async {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(machineRef);
      final inv = Map<String, dynamic>.from(snap['inventory'] ?? {});
      final current = inv[field] ?? 0;
      inv[field] = (current + delta).clamp(0, maxVal);
      tx.update(machineRef, {'inventory': inv});
    });
  }

  Future<void> setStockFull(String field, int maxVal) async {
    await machineRef.update({'inventory.$field': maxVal});
  }

  Future<void> toggleMachineStatus(bool isActive) async {
    await machineRef.update({'status.isActive': !isActive});
  }

  Future<void> changeLiquid(BuildContext context) async {
    // Buraya senin _changeLiquid fonksiyonunun içeriği taşınacak.
  }

  Future<void> finishMaintenance(BuildContext context, {bool exit = false}) async {
    try {
      final email = FirebaseAuth.instance.currentUser?.email ?? 'unknown';
      final logRef = machineRef.collection('maintenance_logs').doc();
      await logRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'performedBy': email,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bakım kaydı başarıyla eklendi ($email).')),
      );
      if (exit) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata oluştu: $e')),
      );
    }
  }

  String bandForLiquid(int value, int maxVal) {
    final ratio = maxVal == 0 ? 0.0 : value / maxVal;
    if (ratio < 0.2) return 'red';
    else if (ratio < 0.5) return 'orange';
    else return 'green';
  }
}