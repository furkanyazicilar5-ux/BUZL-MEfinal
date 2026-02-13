import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/panels/admin_panel_page.dart';
import '../pages/panels/service_panel_page.dart';

class AdminKeypadDialog extends StatefulWidget {
  final int length;
  const AdminKeypadDialog({super.key, this.length = 8});

  @override
  State<AdminKeypadDialog> createState() => _AdminKeypadDialogState();
}

class _AdminKeypadDialogState extends State<AdminKeypadDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  Future<void> _login() async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final uid = userCredential.user!.uid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final role = doc['role'];
      if (role == 'admin') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminPanelPage()));
      } else if (role == 'service') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ServicePanelPage()));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yetkisiz kullanıcı')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Giriş başarısız: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 220,
            maxWidth: 240,
            maxHeight: 400,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Admin Girişi', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Şifre',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _login,
                child: const Text('Giriş Yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}