import 'package:flutter/material.dart';

class StockControlCard extends StatelessWidget {
  final String label;
  final int value;
  final String field;
  final int maxVal;
  final Function(String, int, int) onUpdate;
  final Function(String, int) onFull;

  const StockControlCard({
    super.key,
    required this.label,
    required this.value,
    required this.field,
    required this.maxVal,
    required this.onUpdate,
    required this.onFull,
  });

  @override
  Widget build(BuildContext context) {
    final double pct = value / maxVal;
    Color barColor = pct < 0.2
        ? Colors.red
        : pct < 0.5
        ? Colors.orange
        : Colors.teal;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: pct.clamp(0.0, 1.0), color: barColor),
            const SizedBox(height: 6),
            Text('$value adet'),
            Row(
              children: [
                IconButton(onPressed: () => onUpdate(field, -5, maxVal), icon: const Icon(Icons.remove_circle_outline)),
                IconButton(onPressed: () => onUpdate(field, 5, maxVal), icon: const Icon(Icons.add_circle_outline)),
                ElevatedButton(
                  onPressed: () => onFull(field, maxVal),
                  style: ElevatedButton.styleFrom(backgroundColor: barColor, foregroundColor: Colors.white),
                  child: Text('Tam ($maxVal)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}