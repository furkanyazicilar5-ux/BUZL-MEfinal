package com.example.buzi_kiosk_tmp

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onResume() {
        super.onResume()
        try {
            startLockTask()   // Kiosk kilidini başlatır
        } catch (e: Exception) {
            // Eğer cihaz lock-task whitelist'e alınmamışsa hata verebilir
            e.printStackTrace()
        }
    }
}