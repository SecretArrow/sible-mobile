/// Lightweight dependency-free i18n (English / Bahasa Indonesia).
///
/// Design:
/// * Every UI string is referenced by a stable key: `t(context, 'key')`.
/// * Strings live in per-feature namespace files under `lib/i18n/`
///   (each map: `key -> {en: ..., id: ...}`). Feature files are owned by
///   exactly one feature to keep merges conflict-free.
/// * `LocaleController` (ChangeNotifier) holds the active language and is
///   persisted by the app shell; `I18nScope` publishes it down the tree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../i18n/inferhub_strings.dart';
import '../i18n/maintenance_strings.dart';
import '../i18n/ops_strings.dart';
import '../i18n/security_strings.dart';
import '../i18n/stats_strings.dart';

enum AppLang { en, id }

extension AppLangX on AppLang {
  String get code => this == AppLang.en ? 'en' : 'id';
  String get label =>
      this == AppLang.en ? 'English' : 'Bahasa Indonesia';

  static AppLang fromCode(String? code) =>
      code == 'id' ? AppLang.id : AppLang.en;
}

/// Core app-wide strings (nav, common actions, settings basics).
const Map<String, Map<String, String>> coreStrings = {
  'app.name': {'en': 'Sible Miner', 'id': 'Sible Miner'},
  'nav.dashboard': {'en': 'Dashboard', 'id': 'Dasbor'},
  'nav.accounts': {'en': 'Accounts', 'id': 'Akun'},
  'nav.proxies': {'en': 'Proxies', 'id': 'Proksi'},
  'nav.logs': {'en': 'Logs', 'id': 'Log'},
  'nav.settings': {'en': 'Settings', 'id': 'Pengaturan'},
  'nav.stats': {'en': 'Stats', 'id': 'Statistik'},
  'common.save': {'en': 'Save', 'id': 'Simpan'},
  'common.cancel': {'en': 'Cancel', 'id': 'Batal'},
  'common.close': {'en': 'Close', 'id': 'Tutup'},
  'common.delete': {'en': 'Delete', 'id': 'Hapus'},
  'common.confirm': {'en': 'Confirm', 'id': 'Konfirmasi'},
  'common.ok': {'en': 'OK', 'id': 'OK'},
  'common.retry': {'en': 'Retry', 'id': 'Coba lagi'},
  'common.search': {'en': 'Search', 'id': 'Cari'},
  'common.loading': {'en': 'Loading…', 'id': 'Memuat…'},
  'common.enabled': {'en': 'Enabled', 'id': 'Aktif'},
  'common.disabled': {'en': 'Disabled', 'id': 'Nonaktif'},
  'common.error': {'en': 'Error', 'id': 'Galat'},
  'common.success': {'en': 'Success', 'id': 'Berhasil'},
  'common.none': {'en': 'None', 'id': 'Tidak ada'},
  'common.all': {'en': 'All', 'id': 'Semua'},
  'common.export': {'en': 'Export', 'id': 'Ekspor'},
  'common.import': {'en': 'Import', 'id': 'Impor'},
  'common.version': {'en': 'Version', 'id': 'Versi'},
  'common.language': {'en': 'Language', 'id': 'Bahasa'},
  'common.copy': {'en': 'Copy', 'id': 'Salin'},
  'common.copied': {'en': 'Copied to clipboard', 'id': 'Tersalin ke papan klip'},
  'common.empty': {'en': 'Nothing here yet', 'id': 'Belum ada data'},
  'common.test': {'en': 'Test', 'id': 'Tes'},
  'common.apply': {'en': 'Apply', 'id': 'Terapkan'},
  'common.back': {'en': 'Back', 'id': 'Kembali'},
  'common.next': {'en': 'Next', 'id': 'Lanjut'},
  'common.previous': {'en': 'Previous', 'id': 'Sebelumnya'},
  'settings.title': {'en': 'Settings', 'id': 'Pengaturan'},
  'settings.serviceEnabled': {
    'en': 'Background service',
    'id': 'Layanan latar belakang',
  },
  'settings.intervalMinutes': {
    'en': 'Check interval (minutes)',
    'id': 'Interval pengecekan (menit)',
  },
  'settings.notifications': {'en': 'Notifications', 'id': 'Notifikasi'},
  'settings.proxy': {'en': 'Proxy engine', 'id': 'Mesin proksi'},
  'settings.language': {
    'en': 'App language',
    'id': 'Bahasa aplikasi',
  },
  'settings.languageChanged': {
    'en': 'Language updated',
    'id': 'Bahasa diperbarui',
  },
};

/// Aggregated translation table: key -> {lang code -> text}.
/// Lookup order: active lang, then English, then the raw key.
const Map<String, Map<String, String>> kAppStrings = {
  ...coreStrings,
  ...inferhubStrings,
  ...statsStrings,
  ...maintenanceStrings,
  ...securityStrings,
  ...opsStrings,
};

/// Holds the active language; survives via SharedPreferences in app shell.
class LocaleController extends ChangeNotifier {
  LocaleController(AppLang initial) : _lang = initial;

  static final LocaleController instance =
      LocaleController(AppLang.en);

  AppLang _lang = AppLang.en;
  AppLang get lang => _lang;

  Future<void> loadFrom(String? code) async {
    _lang = AppLangX.fromCode(code);
    notifyListeners();
  }

  void set(AppLang lang) {
    if (lang == _lang) return;
    _lang = lang;
    notifyListeners();
  }
}

/// Publishes the active [AppLang] down the widget tree.
class I18nScope extends InheritedWidget {
  final AppLang lang;

  const I18nScope({
    super.key,
    required this.lang,
    required super.child,
  });

  static AppLang langOf(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<I18nScope>();
    return scope?.lang ?? LocaleController.instance.lang;
  }

  @override
  bool updateShouldNotify(I18nScope oldWidget) =>
      oldWidget.lang != lang;
}

/// Translate [key] in the active locale (falls back to English, then key).
String t(BuildContext context, String key) {
  final lang = I18nScope.langOf(context);
  final entry = kAppStrings[key];
  if (entry == null) return key;
  return entry[lang.code] ?? entry['en'] ?? key;
}
