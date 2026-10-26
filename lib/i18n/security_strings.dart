/// Strings for anti-kill service hardening (#4) and biometric lock (#5).
/// Keys use the `battery.` and `lock.` prefixes.
library;

const Map<String, Map<String, String>> securityStrings = {
  'battery.title': {
    'en': 'Keep-alive (anti-kill)',
    'id': 'Tetap hidup (anti-kill)',
  },
  'battery.hint': {
    'en': 'Vendors like Xiaomi, Huawei, Samsung and Oppo/Realme kill background services aggressively. Whitelist the app so mining keeps running.',
    'id': 'Vendor seperti Xiaomi, Huawei, Samsung, dan Oppo/Realme mematikan layanan latar belakang secara agresif. Whitelist aplikasi agar mining tetap berjalan.',
  },
  'battery.statusOk': {
    'en': 'Battery optimization: IGNORED (good)',
    'id': 'Optimisasi baterai: DIABAIKAN (baik)',
  },
  'battery.statusBad': {
    'en': 'Battery optimization: ACTIVE (service can be killed)',
    'id': 'Optimisasi baterai: AKTIF (layanan bisa dimatikan)',
  },
  'battery.requestExemption': {
    'en': 'Request battery optimization exemption',
    'id': 'Minta pengecualian optimisasi baterai',
  },
  'battery.vendorGuide': {
    'en': 'Vendor-specific setup',
    'id': 'Pengaturan khusus vendor',
  },
  'battery.vendorGeneric': {
    'en': 'Settings → Battery → Unrestricted / Don\'t optimize for Sible Miner.',
    'id': 'Pengaturan → Baterai → Tanpa batasan / Jangan optimalkan untuk Sible Miner.',
  },
  'battery.vendorXiaomi': {
    'en': 'Xiaomi/Redmi/POCO: Security app → App details → Battery saver → No restrictions, AND enable Autostart.',
    'id': 'Xiaomi/Redmi/POCO: Aplikasi Keamanan → Detail app → Penghemat baterai → Tanpa batasan, lalu aktifkan Autostart.',
  },
  'battery.vendorHuawei': {
    'en': 'Huawei/Honor: Settings → Battery → App launch → Manage manually → enable all three toggles.',
    'id': 'Huawei/Honor: Pengaturan → Baterai → Peluncuran app → Kelola manual → aktifkan ketiga saklar.',
  },
  'battery.vendorSamsung': {
    'en': 'Samsung: Settings → Battery → Background usage limits → Remove Sible Miner from Sleeping apps; never "Put unused apps to sleep".',
    'id': 'Samsung: Pengaturan → Baterai → Batas pemakaian latar → keluarkan Sible Miner dari Sleeping apps.',
  },
  'battery.vendorOppo': {
    'en': 'Oppo/Realme/OnePlus: Settings → Battery → More settings → Optimize battery use → Sible Miner → Don\'t optimize; enable "Allow auto-start".',
    'id': 'Oppo/Realme/OnePlus: Pengaturan → Baterai → Setelan lainnya → Optimalkan baterai → Sible Miner → Jangan optimalkan; aktifkan "Izinkan auto-start".',
  },
  'battery.bootStart': {
    'en': 'Restart service after phone reboot',
    'id': 'Jalankan ulang layanan setelah HP di-restart',
  },
  'battery.relaunchOnKill': {
    'en': 'Auto-relaunch service if killed',
    'id': 'Jalankan ulang layanan jika dimatikan',
  },
  'lock.title': {'en': 'App lock', 'id': 'Kunci aplikasi'},
  'lock.enable': {
    'en': 'Require biometric / device credential',
    'id': 'Wajibkan biometrik / kredensial perangkat',
  },
  'lock.enableHint': {
    'en': 'Lock the app behind fingerprint, face or your device PIN.',
    'id': 'Kunci aplikasi dengan sidik jari, wajah, atau PIN perangkat.',
  },
  'lock.lockNow': {
    'en': 'Lock now',
    'id': 'Kunci sekarang',
  },
  'lock.unlockPrompt': {
    'en': 'Unlock Sible Miner',
    'id': 'Buka kunci Sible Miner',
  },
  'lock.unlockSubtitle': {
    'en': 'Authenticate to access your accounts',
    'id': 'Autentikasi untuk mengakses akunmu',
  },
  'lock.failed': {
    'en': 'Authentication failed — try again',
    'id': 'Autentikasi gagal — coba lagi',
  },
  'lock.unavailable': {
    'en': 'No biometric hardware or none enrolled — using device PIN instead.',
    'id': 'Tidak ada biometrik atau belum terdaftar — memakai PIN perangkat.',
  },
  'lock.notEnrolled': {
    'en': 'Enroll a fingerprint/face in Android settings first.',
    'id': 'Daftarkan sidik jari/wajah di pengaturan Android dulu.',
  },
};
