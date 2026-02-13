/// Uygulama kimlik bilgileri (MCU handshake + loglarda görünür).
///
/// Not: package_info_plus eklemeden, pubspec.yaml içindeki version'dan türetilen sabit.
/// Bu değer CI'da pubspec version güncellendikçe güncellenmelidir.
const String kAppVersion = '1.0.0';

/// Protokol versiyonu (PDF v2)
const int kProtoVersion = 2;

/// Firestore / saha kurulumunda kullanılan makine id.
/// Not: Projede 'M-0001' gibi hard-code kullanım yapılmamalı; her yer buradan okumalı.
const String kMachineId = 'M-0001';
