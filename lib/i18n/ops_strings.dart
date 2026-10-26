/// Strings for logs filter + CSV export (#6), smart notifications (#7)
/// and proxy override / test (#8). Keys use the `logs.`, `notif.`
/// and `proxy.` prefixes.
library;

const Map<String, Map<String, String>> opsStrings = {
  'logs.title': {'en': 'Logs', 'id': 'Log'},
  'logs.filterAccount': {
    'en': 'Filter: account',
    'id': 'Filter: akun',
  },
  'logs.filterLevel': {
    'en': 'Filter: level',
    'id': 'Filter: level',
  },
  'logs.filterText': {
    'en': 'Search in messages…',
    'id': 'Cari di pesan…',
  },
  'logs.levelInfo': {'en': 'Info', 'id': 'Info'},
  'logs.levelWarn': {'en': 'Warning', 'id': 'Peringatan'},
  'logs.levelError': {'en': 'Error', 'id': 'Galat'},
  'logs.exportCsv': {
    'en': 'Export CSV',
    'id': 'Ekspor CSV',
  },
  'logs.exported': {
    'en': 'CSV exported — {n} row(s)',
    'id': 'CSV terekspor — {n} baris',
  },
  'logs.clear': {'en': 'Clear logs', 'id': 'Bersihkan log'},
  'logs.cleared': {'en': 'Logs cleared', 'id': 'Log dibersihkan'},
  'logs.results': {
    'en': '{n} result(s)',
    'id': '{n} hasil',
  },
  'notif.smart': {
    'en': 'Smart notifications',
    'id': 'Notifikasi pintar',
  },
  'notif.smartHint': {
    'en': 'Group per account and notify only on errors/claims instead of every cycle.',
    'id': 'Kelompokkan per akun dan beri notifikasi hanya saat galat/klaim, bukan tiap siklus.',
  },
  'notif.errorOnly': {
    'en': 'Alerts only (errors & claims)',
    'id': 'Hanya peringatan (galat & klaim)',
  },
  'notif.errorOnlyHint': {
    'en': 'Skip per-cycle OK pings; errors, claims and alerts stay on.',
    'id': 'Lewati ping OK tiap siklus; galat, klaim, dan peringatan tetap on.',
  },
  'notif.summary': {
    'en': 'Daily summary',
    'id': 'Ringkasan harian',
  },
  'notif.summaryHint': {
    'en': 'One aggregated notification per day instead of every cycle.',
    'id': 'Satu notifikasi ringkasan per hari, bukan tiap siklus.',
  },
  'notif.grouped': {
    'en': '{n} accounts OK (grouped)',
    'id': '{n} akun OK (dikelompokkan)',
  },
  'notif.cooldown': {
    'en': 'Repeat alert cooldown (minutes)',
    'id': 'Jeda notifikasi berulang (menit)',
  },
  'proxy.override': {
    'en': 'Manual proxy override',
    'id': 'Paksa proksi manual',
  },
  'proxy.overrideHint': {
    'en': 'Force this proxy for the selected account instead of using the pool.',
    'id': 'Paksa proksi ini untuk akun terpilih, menggantikan pool.',
  },
  'proxy.overrideEnabled': {
    'en': 'Use manual proxy for this account',
    'id': 'Pakai proksi manual untuk akun ini',
  },
  'proxy.uri': {
    'en': 'Proxy URI (host:port or user:pass@host:port)',
    'id': 'URI proksi (host:port atau user:pass@host:port)',
  },
  'proxy.test': {
    'en': 'Test proxy',
    'id': 'Tes proksi',
  },
  'proxy.testing': {
    'en': 'Testing…',
    'id': 'Menguji…',
  },
  'proxy.testOk': {
    'en': 'Proxy OK — exit IP: {ip} ({country})',
    'id': 'Proksi OK — IP keluar: {ip} ({country})',
  },
  'proxy.testFail': {
    'en': 'Proxy failed: {e}',
    'id': 'Proksi gagal: {e}',
  },
  'proxy.invalidUri': {
    'en': 'Invalid proxy URI format',
    'id': 'Format URI proksi tidak valid',
  },
  'proxy.saved': {
    'en': 'Proxy override saved',
    'id': 'Paksaan proksi disimpan',
  },
};
