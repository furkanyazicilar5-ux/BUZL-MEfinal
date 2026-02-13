const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const nodemailer = require("nodemailer");

initializeApp();

const mailTransport = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "buzisoftapp@gmail.com",
    pass: "ehbfhdgdxbkzzhjf",
  },
});

// --- Refund Mail ---
exports.sendRefundEmail = onDocumentCreated(
  "machines/{machineId}/profit_logs/refund_logs/{date}/{logId}",
  async (event) => {
    try {
      const data = event.data.data();
      if (!data) {
        console.error("Boş veri alındı, e-posta gönderilmiyor.");
        return;
      }

      const machineId = event.params.machineId;
      const date = event.params.date;
      const errorCode = data.errorCode || "Bilinmiyor";
      const cupType = data.cupType || "none";
      const amountTl = data.amountTl || 0;
      const amountMl = data.amountMl || 0;

      const mailOptions = {
        from: '"Buzi Kiosk" <buzisoftapp@gmail.com>',
        to: "buzisoftapp@gmail.com",
        subject: `Yeni iade kaydı (${errorCode})`,
        text: `
Yeni iade işlemi gerçekleşti:
- Makine: ${machineId}
- Tarih: ${date}
- Hata tipi: ${errorCode}
- Bardak tipi: ${cupType}
- Tutar: ${amountTl} TL
- Miktar: ${amountMl} ml
- Zaman: ${new Date().toLocaleString("tr-TR")}
        `,
      };

      console.log(`📨 E-posta gönderiliyor: ${machineId} / ${errorCode}`);
      await mailTransport.sendMail(mailOptions);
      console.log(`✅ E-posta gönderildi: ${machineId} (${errorCode})`);
    } catch (err) {
      console.error("❌ E-posta gönderim hatası:", err);
    }
  }
);

// --- Unified Level Monitor ---
exports.notifyMachineLevels = onDocumentUpdated(
  "machines/M-0001",
  async (event) => {
    try {
      const beforeData = event.data.before.data();
      const afterData = event.data.after.data();
      if (!beforeData || !afterData) {
        console.error("Veri alınamadı.");
        return;
      }

      const machineId = "M-0001";
      const beforeInv = beforeData.inventory || {};
      const afterInv = afterData.inventory || {};
      const beforeLevels = beforeData.levels || {};
      const afterLevels = afterData.levels || {};

      // --- Bardak Stokları ---
      const beforeSmall = beforeInv.smallCups || 0;
      const afterSmall = afterInv.smallCups || 0;
      const beforeLarge = beforeInv.largeCups || 0;
      const afterLarge = afterInv.largeCups || 0;

      // 🟠 Küçük bardak <30
      if (afterSmall < 30 && beforeSmall >= 30 && afterSmall > 0) {
        await mailTransport.sendMail({
          from: '"Buzi Kiosk" <buzisoftapp@gmail.com>',
          to: "buzisoftapp@gmail.com",
          subject: `⚠️ [${machineId}] Küçük bardak stoğu azaldı!`,
          text: `Makine: ${machineId}\nKüçük bardak stoğu ${afterSmall} adede düştü. Yenileme önerilir.`,
        });
        console.log("📨 Küçük bardak uyarı e-postası gönderildi.");
      }

      // 🔴 Küçük bardak bitti
      if (afterSmall === 0 && beforeSmall > 0) {
        await mailTransport.sendMail({
          from: '"Buzi Kiosk" <buzisoftapp@gmail.com>',
          to: "buzisoftapp@gmail.com",
          subject: `🛑 [${machineId}] Küçük bardak stoğu bitti — Satış kapatıldı`,
          text: `Makine: ${machineId}\nKüçük bardak stoğu 0'a düştü. Satışlar durduruldu.`,
        });
        console.log("📨 Küçük bardak bitiş e-postası gönderildi.");
      }

      // 🟠 Büyük bardak <30
      if (afterLarge < 30 && beforeLarge >= 30 && afterLarge > 0) {
        await mailTransport.sendMail({
          from: '"Buzi Kiosk" <buzisoftapp@gmail.com>',
          to: "buzisoftapp@gmail.com",
          subject: `⚠️ [${machineId}] Büyük bardak stoğu azaldı!`,
          text: `Makine: ${machineId}\nBüyük bardak stoğu ${afterLarge} adede düştü. Yenileme önerilir.`,
        });
        console.log("📨 Büyük bardak uyarı e-postası gönderildi.");
      }

      // 🔴 Büyük bardak bitti
      if (afterLarge === 0 && beforeLarge > 0) {
        await mailTransport.sendMail({
          from: '"Buzi Kiosk" <buzisoftapp@gmail.com>',
          to: "buzisoftapp@gmail.com",
          subject: `🛑 [${machineId}] Büyük bardak stoğu bitti — Satış kapatıldı`,
          text: `Makine: ${machineId}\nBüyük bardak stoğu 0'a düştü. Satışlar durduruldu.`,
        });
        console.log("📨 Büyük bardak bitiş e-postası gönderildi.");
      }

      // --- Sıvı Seviyesi ---
      const beforeLiquid = beforeLevels.liquid || 0;
      const afterLiquid = afterLevels.liquid || 0;
      const maxLiquid = 20000;
      const beforePct = (beforeLiquid / maxLiquid) * 100;
      const afterPct = (afterLiquid / maxLiquid) * 100;

      // 🟠 Kritik seviye (%15 altı)
      if (afterPct < 15 && beforePct >= 15 && afterLiquid > 0) {
        await mailTransport.sendMail({
          from: '"Buzi Kiosk" <buzisoftapp@gmail.com>',
          to: "buzisoftapp@gmail.com",
          subject: `🚨 [${machineId}] Sıvı seviyesi kritik seviyeye düştü!`,
          text: `Makine: ${machineId}\nSıvı seviyesi %15 altına indi (${afterLiquid} ml). Acil müdahale gerekli.`,
        });
        console.log("📨 Sıvı kritik seviye e-postası gönderildi.");
      }

      // 🔴 Sıfır seviye (makine kapatıldı)
      if (afterLiquid === 0 && beforeLiquid > 0) {
        await mailTransport.sendMail({
          from: '"Buzi Kiosk" <buzisoftapp@gmail.com>',
          to: "buzisoftapp@gmail.com",
          subject: `🛑 [${machineId}] Sıvı tükendi — Makine kapatıldı`,
          text: `Makine: ${machineId}\nSıvı seviyesi 0 ml'ye düştü. Satışlar durduruldu.`,
        });
        console.log("📨 Sıvı bitiş e-postası gönderildi.");
      }

      console.log("✅ Seviye kontrolü tamamlandı.");
    } catch (err) {
      console.error("❌ Seviye e-posta gönderim hatası:", err);
    }
  }
);