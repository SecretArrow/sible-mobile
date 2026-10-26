/// ACCOUNT / AUTH / KEEPALIVE / ERROR-ADVISOR strings (English / Indonesian).
///
/// Owned by the accounts + auth features: manual gmail.com account adding,
/// manual OTP verification, the 10-minute token keepalive and the
/// error-advisor ("cara atasi error") sheets.
const Map<String, Map<String, String>> accountStrings = {
  // -- Add account (manual gmail flow) --------------------------------------
  'account.add.title': {'en': 'Add account', 'id': 'Tambah akun'},
  'account.add.manualTab': {'en': 'Manual login', 'id': 'Login manual'},
  'account.add.email': {'en': 'Email', 'id': 'Email'},
  'account.add.password': {'en': 'Password', 'id': 'Kata sandi'},
  'account.add.label': {
    'en': 'Label (optional, e.g. "Main")',
    'id': 'Label (opsional, mis. "Utama")',
  },
  'account.add.gmailHint': {
    'en': 'Use the gmail.com account you registered manually on '
        'sible.network. The app only logs it in - no auto registration.',
    'id': 'Gunakan akun gmail.com yang kamu daftarkan manual di '
        'sible.network. Aplikasi hanya melakukan login - tanpa registrasi '
        'otomatis.',
  },
  'account.add.cta': {'en': 'Add & verify login', 'id': 'Tambah & uji login'},
  'account.add.required': {
    'en': 'Email & password are required',
    'id': 'Email & kata sandi wajib diisi',
  },
  'account.add.ok': {
    'en': 'Login OK - account ready',
    'id': 'Login OK - akun siap',
  },
  'account.add.failed': {
    'en': 'Login failed - open the account for details',
    'id': 'Login gagal - buka akun untuk detail',
  },
  'account.add.limitReached': {
    'en': 'Account limit of 100 reached.',
    'id': 'Batas 100 akun tercapai.',
  },
  'account.add.savedNoVerify': {
    'en': 'Account saved. Login could not be verified yet.',
    'id': 'Akun disimpan. Login belum dapat diverifikasi.',
  },

  // -- Manual OTP ------------------------------------------------------------
  'account.otp.title': {'en': 'Enter verification code', 'id': 'Masukkan kode verifikasi'},
  'account.otp.subtitle': {
    'en': 'A 6-digit code was sent to this email. Open your Gmail inbox, '
        'copy the code, then paste it here.',
    'id': 'Kode 6 digit dikirim ke email tersebut. Buka kotak masuk Gmail, '
        'salin kodenya, lalu tempel di sini.',
  },
  'account.otp.hint': {'en': '6-digit code', 'id': 'Kode 6 digit'},
  'account.otp.verify': {'en': 'Verify', 'id': 'Verifikasi'},
  'account.otp.resend': {'en': 'Resend code', 'id': 'Kirim ulang kode'},
  'account.otp.sent': {
    'en': 'New code requested - check your inbox',
    'id': 'Kode baru diminta - cek kotak masuk',
  },
  'account.otp.invalid': {
    'en': 'Code rejected - double-check and try again',
    'id': 'Kode ditolak - periksa lagi lalu coba lagi',
  },

  // -- Error advisor ("cara atasi error") ------------------------------------
  'fix.title': {'en': 'How to fix this', 'id': 'Cara mengatasi ini'},
  'fix.needsOtp.title': {
    'en': 'Verification code required',
    'id': 'Perlu kode verifikasi',
  },
  'fix.needsOtp.steps': {
    'en': '1. Open your Gmail inbox\n'
        '2. Find the Sible Network email (check Spam too)\n'
        '3. Copy the 6-digit code\n'
        '4. Paste it in the box and tap Verify',
    'id': '1. Buka kotak masuk Gmail\n'
        '2. Cari email dari Sible Network (cek juga Spam)\n'
        '3. Salin kode 6 digitnya\n'
        '4. Tempel di kolom lalu tekan Verifikasi',
  },
  'fix.needsRelogin.title': {'en': 'Login problem', 'id': 'Masalah login'},
  'fix.needsRelogin.steps': {
    'en': 'The saved session is no longer valid. Usual causes:\n'
        '- Password changed on the website\n'
        '- Logged out from another device\n'
        '- Session expired beyond recovery\n\n'
        'Update the password below, or remove and re-add the account.',
    'id': 'Sesi tersimpan tidak berlaku lagi. Penyebab umum:\n'
        '- Kata sandi diubah di situs web\n'
        '- Keluar dari perangkat lain\n'
        '- Sesi kedaluwarsa dan tak bisa dipulihkan\n\n'
        'Perbarui kata sandi di bawah, atau hapus lalu tambah ulang akun.',
  },
  'fix.proxyError.title': {
    'en': 'Network / proxy problem',
    'id': 'Masalah jaringan / proksi',
  },
  'fix.proxyError.steps': {
    'en': 'The request could not reach the server. Try in order:\n'
        '1. Refresh the proxy pool (get fresh proxies)\n'
        '2. Run a proxy test\n'
        '3. If it still fails, disable proxies or allow direct fallback',
    'id': 'Permintaan tidak sampai ke server. Coba berurutan:\n'
        '1. Segarkan pool proksi (dapatkan proksi baru)\n'
        '2. Jalankan tes proksi\n'
        '3. Jika masih gagal, matikan proksi atau izinkan fallback langsung',
  },
  'fix.banned.title': {'en': 'Account banned', 'id': 'Akun diblokir'},
  'fix.banned.steps': {
    'en': 'The server has banned this account. This app cannot unban it.\n'
        'Options: register a new account, or remove this one from the list.',
    'id': 'Server telah memblokir akun ini. Aplikasi tidak bisa '
        'membukanya.\nOpsi: daftarkan akun baru, atau hapus akun ini dari '
        'daftar.',
  },
  'fix.generic.title': {'en': 'Something went wrong', 'id': 'Terjadi kesalahan'},
  'fix.generic.steps': {
    'en': 'An unexpected error occurred on the last run.\n'
        '1. Retry the account cycle\n'
        '2. Check the Logs tab for the exact error\n'
        '3. If it repeats, remove and re-add the account',
    'id': 'Terjadi galat tak terduga pada eksekusi terakhir.\n'
        '1. Jalankan ulang siklus akun\n'
        '2. Cek tab Log untuk detail errornya\n'
        '3. Jika berulang, hapus lalu tambah ulang akun',
  },
  'fix.retryLogin': {'en': 'Retry login', 'id': 'Coba login ulang'},
  'fix.enterOtp': {'en': 'Enter OTP code', 'id': 'Masukkan kode OTP'},
  'fix.refreshPool': {'en': 'Refresh proxy pool', 'id': 'Segarkan pool proksi'},
  'fix.disableProxies': {'en': 'Disable proxies', 'id': 'Matikan proksi'},
  'fix.allowDirect': {
    'en': 'Allow direct fallback',
    'id': 'Izinkan fallback langsung',
  },
  'fix.updatePassword': {'en': 'Save & retry', 'id': 'Simpan & coba lagi'},
  'fix.newPassword': {'en': 'New password', 'id': 'Kata sandi baru'},
  'fix.runCycle': {'en': 'Run this account now', 'id': 'Jalankan akun ini'},
  'fix.removeAccount': {'en': 'Remove account', 'id': 'Hapus akun'},
  'fix.done': {'en': 'Done', 'id': 'Selesai'},
  'fix.failed': {'en': 'Failed', 'id': 'Gagal'},

  // -- Token keepalive -------------------------------------------------------
  'keepalive.group': {
    'en': 'Session keepalive',
    'id': 'Penjaga sesi (keepalive)',
  },
  'keepalive.enabled': {
    'en': 'Auto keepalive (every 10 minutes)',
    'id': 'Keepalive otomatis (tiap 10 menit)',
  },
  'keepalive.subtitle': {
    'en': 'Refreshes every account\'s JWT / access token before it expires, '
        'so sessions never drop. Runs in the background service and on app '
        'open.',
    'id': 'Menyegarkan JWT / token akses tiap akun sebelum kedaluwarsa agar '
        'sesi tidak pernah mati. Berjalan di layanan latar belakang dan saat '
        'aplikasi dibuka.',
  },
  'keepalive.runNow': {'en': 'Keepalive now', 'id': 'Keepalive sekarang'},
  'keepalive.runNowHint': {
    'en': 'Refresh all sessions immediately',
    'id': 'Segarkan semua sesi sekarang',
  },
  'keepalive.done': {
    'en': 'Keepalive done: %d account(s) checked, %f need attention',
    'id': 'Keepalive selesai: %d akun diperiksa, %f perlu perhatian',
  },
  'keepalive.lastRun': {
    'en': 'Token keepalive',
    'id': 'Keepalive token',
  },
  'keepalive.never': {'en': 'never', 'id': 'belum pernah'},

  // -- Account detail extras -------------------------------------------------
  'account.detail.keepalive': {
    'en': 'Token keepalive',
    'id': 'Keepalive token',
  },
  'account.detail.openGmail': {
    'en': 'Open Gmail',
    'id': 'Buka Gmail',
  },
};
