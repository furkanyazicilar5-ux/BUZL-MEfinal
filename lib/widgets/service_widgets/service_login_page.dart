import 'package:flutter/material.dart';

class ServiceLoginPage extends StatelessWidget {
  const ServiceLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Servis Girişi')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Hoş geldiniz, Servis Kullanıcısı',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Servis paneline yönlendirme
                Navigator.of(context).pushReplacementNamed('/servicePanel');
              },
              child: const Text('Servis Paneline Git'),
            ),
          ],
        ),
      ),
    );
  }
}