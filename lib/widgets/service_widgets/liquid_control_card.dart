import 'package:flutter/material.dart';

class LiquidControlCard extends StatelessWidget {
  final int value;
  final int maxVal;
  final void Function(int newValue, int duration) onChange;

  const LiquidControlCard({
    super.key,
    required this.value,
    required this.maxVal,
    required this.onChange,
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
            const Text('İçecek Seviyesi (ml)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            LinearProgressIndicator(value: pct.clamp(0.0, 1.0), color: barColor),
            const SizedBox(height: 8),
            Text('$value ml'),
            const SizedBox(height: 12),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  int inputValue = value;
                  int selectedDuration = 60;
                  String? errorText;
                  final TextEditingController controller = TextEditingController(text: inputValue.toString());
                  await showDialog(
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(
                        builder: (context, setState) {
                          return AlertDialog(
                            title: const Text('İçecek Seviyesi Ayarla'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: controller,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'İçecek seviyesi (ml)',
                                    errorText: errorText,
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      errorText = null;
                                      inputValue = int.tryParse(val) ?? 0;
                                    });
                                  },
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Text('Süre:'),
                                    const SizedBox(width: 16),
                                    DropdownButton<int>(
                                      value: selectedDuration,
                                      items: const [
                                        DropdownMenuItem(value: 0, child: Text('0 dk')),
                                        DropdownMenuItem(value: 30, child: Text('30 dk')),
                                        DropdownMenuItem(value: 60, child: Text('60 dk')),
                                        DropdownMenuItem(value: 90, child: Text('90 dk')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            selectedDuration = val;
                                          });
                                        }
                                      },
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          controller.text = '80000';
                                          inputValue = 80000;
                                        });
                                      },
                                      child: const Text('Tamamla (80000)'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                child: const Text('İptal'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  final val = int.tryParse(controller.text);
                                  if (val == null || val < 0 || val > 80000) {
                                    setState(() {
                                      errorText = '0 ile 80.000 arasında bir değer girin';
                                    });
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  onChange(val, selectedDuration);
                                },
                                child: const Text('Kaydet'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
                icon: const Icon(Icons.local_drink),
                label: const Text('İçecek Seviyesi Ayarla'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}