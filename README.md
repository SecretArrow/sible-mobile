# Sible Miner

Aplikasi Android (Flutter) untuk otomasi akun **Sible Network** (mine.sible.network):
multi-akun hingga **100 akun**, **proxy unik per akun**, **background service** dengan
jadwal cek tiap 5 menit, **notifikasi**, auto **accelerate 20/40/60%**, auto
**extension** (explorer apps), dan auto claim mining/reward tasks.

> ⚠️ Gunakan secara bijak dan tanggung jawab sendiri — otomasi dapat melanggar
> Terms of Service Sible Network. Akun email sementara (mail.tm) hanya untuk testing.

## Fitur

| Fitur | Detail |
|---|---|
| Multi-akun | Maks. 100 akun, tiap akun punya direktori + secure storage sendiri (data tidak saling terikat) |
| Proxy engine | Auto-fetch dari 4 sumber gratis (proxyscrape, TheSpeedX, monosans, geonode) → validasi paralel → 1 proxy eksklusif per akun, rotasi otomatis saat mati |
| Background service | Foreground service (dataSync) + auto-start on boot, loop cron tanpa overlap |
| Jadwal | Cek tiap 5/10/15 menit (default 5) |
| Auto accelerate | Slot iklan otomatis 20/40/60% per sesi mining, tahan cooldown `nextAdAt` |
| Auto extension | Buka explorer/extension apps tiap siklus (maks 10/siklus) |
| Auto claim | Polling `/mining/claim` (500ms→4s) + reward task yang eligible |
| Notifikasi | Channel: service (ongoing), cycle summary (agregat), alerts (ban/login gagal/proxy habis) |
| mail.tm factory | Buat akun disposable otomatis: mailbox → register → auto-OTP → login |
| Isolasi | Client HTTP per-akun (connection pool sendiri), proxy sendiri, file sendiri, secrets di secure storage |

## Arsitektur

```
lib/
├── core/            # constants, tema Material 3 modern, utils
├── models/          # Account, ProxyEntry, AppSettings, LogEvent
├── services/
│   ├── sible_api.dart        # HTTP client + envelope + refresh + proxy (dart:io)
│   ├── mining_policy.dart    # logika keputusan siklus (pure, unit-testable)
│   ├── proxy_engine.dart     # fetch/validate/assign unique proxy
│   ├── account_store.dart    # storage terisolasi per akun
│   ├── account_manager.dart  # orchestrator siklus (concurrency pool)
│   ├── mailtm_service.dart   # disposable mailbox + OTP
│   ├── background_service.dart # foreground service + loop cron
│   └── notification_service.dart
├── state/           # wiring dependency + settings store
└── ui/              # dashboard, accounts, proxies, activity, settings
```

## CI/CD (GitHub Actions)

| Workflow | Trigger | Isi |
|---|---|---|
| `CI` | push/PR → main | analyze + format gate, unit tests, build APK release (cache pub+gradle), **auto-fix** (`dart fix` + format + commit) saat analyze/test gagal |
| `E2E` | manual + harian | integration test di Android emulator (API 30) |
| `Release` | tag `v*` | build split-per-ABI + GitHub Release otomatis |

Build cepat: cache Flutter pub, cache Gradle keyed by `gradle*` files, concurrency cancel-in-progress.

## Build

```bash
flutter pub get
flutter test           # unit tests
flutter analyze        # lint
flutter build apk --release
```

Atau biarkan GitHub Actions yang membangun: push → tab **Actions** → artefak `sible-miner-release-apk`.

## Penggunaan

1. Buka tab **Accounts** → tambah akun manual (email+password Sible) atau batch via **mail.tm auto**.
2. Tab **Proxy** → *Refresh pool* (sekali di awal; worker akan refill otomatis).
3. Dashboard → **AUTO ON**. Selesai — service berjalan di background, cek tiap 5 menit.
4. Setelan akun per-akun: target accelerate 20/40/60%, auto extension, auto task, enable/disable.
