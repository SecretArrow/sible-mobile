/// Strings for backup/restore (#2) and the update checker (#3).
/// Keys use the `backup.` and `update.` prefixes.
library;

const Map<String, Map<String, String>> maintenanceStrings = {
  'backup.title': {
    'en': 'Backup & restore',
    'id': 'Cadangkan & pulihkan',
  },
  'backup.hint': {
    'en':
        'Export all accounts (encrypted) into a single .siblebak file, or restore from one.',
    'id':
        'Ekspor semua akun (terenkripsi) ke satu file .siblebak, atau pulihkan darinya.',
  },
  'backup.export': {
    'en': 'Export encrypted backup',
    'id': 'Ekspor cadangan terenkripsi',
  },
  'backup.import': {
    'en': 'Restore from backup',
    'id': 'Pulihkan dari cadangan',
  },
  'backup.passwordPrompt': {
    'en': 'Backup password',
    'id': 'Kata sandi cadangan',
  },
  'backup.passwordHint': {
    'en': 'Min. 8 characters — used to encrypt the file (AES-256-GCM).',
    'id': 'Min. 8 karakter — dipakai mengenkripsi file (AES-256-GCM).',
  },
  'backup.passwordTooShort': {
    'en': 'Password must be at least 8 characters',
    'id': 'Kata sandi minimal 8 karakter',
  },
  'backup.wrongPassword': {
    'en': 'Wrong password or corrupted backup file',
    'id': 'Kata sandi salah atau file cadangan rusak',
  },
  'backup.exportDone': {
    'en': 'Backup saved — {n} account(s)',
    'id': 'Cadangan tersimpan — {n} akun',
  },
  'backup.importDone': {
    'en': 'Restored — {n} account(s) imported',
    'id': 'Pulih — {n} akun diimpor',
  },
  'backup.importConflict': {
    'en': '{n} duplicate account(s) skipped',
    'id': '{n} akun duplikat dilewati',
  },
  'backup.failed': {
    'en': 'Backup failed: {e}',
    'id': 'Cadangan gagal: {e}',
  },
  'backup.confirmPassword': {
    'en': 'Confirm password',
    'id': 'Konfirmasi kata sandi',
  },
  'backup.passwordMismatch': {
    'en': 'Passwords do not match',
    'id': 'Kata sandi tidak sama',
  },
  'backup.passwordRequired': {
    'en': 'Enter the backup password',
    'id': 'Masukkan kata sandi cadangan',
  },
  'backup.exporting': {
    'en': 'Encrypting & saving…',
    'id': 'Mengenkripsi & menyimpan…',
  },
  'backup.restoring': {
    'en': 'Restoring accounts…',
    'id': 'Memulihkan akun…',
  },
  'backup.restoreConfirmTitle': {
    'en': 'Restore this backup?',
    'id': 'Pulihkan cadangan ini?',
  },
  'backup.restoreConfirmBody': {
    'en': 'Accounts from the backup file will be added to this device. '
        'Existing accounts with the same ID are skipped (duplicates are '
        'never overwritten).',
    'id': 'Akun dari file cadangan akan ditambahkan ke perangkat ini. '
        'Akun yang sudah ada dengan ID sama akan dilewati (duplikat tidak '
        'ditimpa).',
  },
  'update.title': {
    'en': 'App updates',
    'id': 'Pembaruan aplikasi',
  },
  'update.checkNow': {
    'en': 'Check for updates',
    'id': 'Cek pembaruan',
  },
  'update.autoCheck': {
    'en': 'Check automatically at startup',
    'id': 'Cek otomatis saat aplikasi dibuka',
  },
  'update.available': {
    'en': 'New version available: v{v} (build {b})',
    'id': 'Versi baru tersedia: v{v} (build {b})',
  },
  'update.upToDate': {
    'en': 'You are on the latest version',
    'id': 'Kamu sudah memakai versi terbaru',
  },
  'update.download': {
    'en': 'Open release page',
    'id': 'Buka halaman rilis',
  },
  'update.checkFailed': {
    'en': 'Could not check for updates: {e}',
    'id': 'Gagal cek pembaruan: {e}',
  },
  'update.notes': {
    'en': 'Release notes',
    'id': 'Catatan rilis',
  },
};
