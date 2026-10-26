/// Strings for the InferHub AI integration (owned by the InferHub feature).
///
/// Owners of this file: the InferHub feature (service + settings section +
/// model picker). Keys use the `inferhub.` prefix.
library;

const Map<String, Map<String, String>> inferhubStrings = {
  'inferhub.title': {
    'en': 'InferHub AI',
    'id': 'InferHub AI',
  },
  'inferhub.enable': {
    'en': 'Enable InferHub AI',
    'id': 'Aktifkan InferHub AI',
  },
  'inferhub.enableHint': {
    'en': 'Use InferHub LLM to solve reward tasks, plan accelerations and pick extensions automatically.',
    'id': 'Gunakan LLM InferHub untuk menyelesaikan reward task, merencanakan akselerasi, dan memilih extension secara otomatis.',
  },
  'inferhub.apiKey': {'en': 'API key', 'id': 'Kunci API'},
  'inferhub.apiKeyHint': {
    'en': 'sk-airo-…',
    'id': 'sk-airo-…',
  },
  'inferhub.apiKeyMissing': {
    'en': 'Set your InferHub API key first',
    'id': 'Atur kunci API InferHub terlebih dahulu',
  },
  'inferhub.model': {'en': 'Model', 'id': 'Model'},
  'inferhub.modelPick': {'en': 'Pick a model', 'id': 'Pilih model'},
  'inferhub.modelSearchHint': {
    'en': 'Search models (e.g. glm, gpt, free/…)',
    'id': 'Cari model (mis. glm, gpt, free/…)',
  },
  'inferhub.modelEmpty': {
    'en': 'No models matched',
    'id': 'Tidak ada model yang cocok',
  },
  'inferhub.modelLoadFailed': {
    'en': 'Failed to load models',
    'id': 'Gagal memuat model',
  },
  'inferhub.advanced': {'en': 'Advanced options', 'id': 'Opsi lanjutan'},
  'inferhub.temperature': {'en': 'Temperature', 'id': 'Temperature'},
  'inferhub.maxTokens': {'en': 'Max output tokens', 'id': 'Maks token keluaran'},
  'inferhub.maxInputPrice': {
    'en': 'Max input price ($/Mtok, 0 = no cap)',
    'id': 'Harga input maks ($/Mtok, 0 = tanpa batas)',
  },
  'inferhub.maxOutputPrice': {
    'en': 'Max output price ($/Mtok, 0 = no cap)',
    'id': 'Harga output maks ($/Mtok, 0 = tanpa batas)',
  },
  'inferhub.timeout': {
    'en': 'Request timeout (seconds)',
    'id': 'Timeout permintaan (detik)',
  },
  'inferhub.mode': {'en': 'AI features', 'id': 'Fitur AI'},
  'inferhub.modeTaskSolver': {
    'en': 'Reward task solver',
    'id': 'Pengerja reward task',
  },
  'inferhub.modeTaskSolverHint': {
    'en': 'Let the AI answer and submit reward tasks.',
    'id': 'Biar AI menjawab dan mengirim reward task.',
  },
  'inferhub.modePlanner': {
    'en': 'Acceleration planner (20/40/60%)',
    'id': 'Perencana akselerasi (20/40/60%)',
  },
  'inferhub.modePlannerHint': {
    'en': 'Let the AI decide the accelerate target per session.',
    'id': 'Biar AI menentukan target akselerasi tiap sesi.',
  },
  'inferhub.modeExtensionPicker': {
    'en': 'Extension picker',
    'id': 'Pemilih extension',
  },
  'inferhub.modeExtensionPickerHint': {
    'en': 'Let the AI choose which explorer apps extend sessions.',
    'id': 'Biar AI memilih app explorer perpanjangan sesi.',
  },
  'inferhub.testConnection': {
    'en': 'Test connection',
    'id': 'Tes koneksi',
  },
  'inferhub.testOk': {
    'en': 'InferHub reachable — balance OK',
    'id': 'InferHub terhubung — saldo OK',
  },
  'inferhub.balance': {'en': 'Balance', 'id': 'Saldo'},
  'inferhub.freeOnly': {
    'en': 'Only offer free models',
    'id': 'Hanya tawarkan model gratis',
  },
  'inferhub.freeOnlyHint': {
    'en': 'Filter the picker to free/<slug>/<model> entries.',
    'id': 'Filter daftar hanya model free/<slug>/<model>.',
  },
  'inferhub.aiDecision': {
    'en': 'AI decision',
    'id': 'Keputusan AI',
  },
  'inferhub.aiFallback': {
    'en': 'AI unavailable — falling back to static policy',
    'id': 'AI tidak tersedia — kembali ke policy statis',
  },
  'inferhub.pickTitle': {
    'en': 'InferHub models',
    'id': 'Model InferHub',
  },
  'inferhub.freeBadge': {
    'en': 'FREE',
    'id': 'GRATIS',
  },
  'inferhub.modelContext': {
    'en': 'context',
    'id': 'konteks',
  },
  'inferhub.apiKeySaved': {
    'en': 'API key saved',
    'id': 'Kunci API tersimpan',
  },
  'inferhub.testFailed': {
    'en': 'Test failed',
    'id': 'Tes gagal',
  },
  'inferhub.docs': {
    'en': 'Open InferHub docs',
    'id': 'Buka dokumentasi InferHub',
  },
};
