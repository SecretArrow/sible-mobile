/// Pure unit tests for tag parsing, version comparison and the release
/// picker's JSON envelope shape guards.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/services/update_service.dart';

void main() {
  group('parseTag', () {
    test('v2.1.0+build.6', () {
      final t = UpdateService.parseTag('v2.1.0+build.6');
      expect(t, isNotNull);
      expect(t!.version, '2.1.0');
      expect(t.build, 6);
    });

    test('v2.1.0+6 (compact build)', () {
      final t = UpdateService.parseTag('v2.1.0+6');
      expect(t, isNotNull);
      expect(t!.version, '2.1.0');
      expect(t.build, 6);
    });

    test('v2.1.0 (no build) -> build 0', () {
      final t = UpdateService.parseTag('v2.1.0');
      expect(t, isNotNull);
      expect(t!.version, '2.1.0');
      expect(t.build, 0);
    });

    test('missing v prefix is tolerated', () {
      final t = UpdateService.parseTag('2.1.0+build.6');
      expect(t, isNotNull);
      expect(t!.version, '2.1.0');
      expect(t.build, 6);
    });

    test('whitespace is tolerated', () {
      final t = UpdateService.parseTag('  v2.1.0+build.12\n');
      expect(t, isNotNull);
      expect(t!.build, 12);
    });

    test('unparseable tags -> null', () {
      expect(UpdateService.parseTag(''), isNull);
      expect(UpdateService.parseTag('release-2.1'), isNull);
      expect(UpdateService.parseTag('v2'), isNull);
      expect(UpdateService.parseTag('v2.1'), isNull);
      expect(UpdateService.parseTag('vx.y.z'), isNull);
      expect(UpdateService.parseTag('v2.1.x'), isNull);
      expect(UpdateService.parseTag('v2.1.0+build.beta'), isNull);
    });
  });

  group('compareVersions', () {
    test('identical versions -> 0', () {
      expect(UpdateService.compareVersions('2.1.0', '2.1.0'), 0);
      expect(UpdateService.compareVersions('v2.1.0', '2.1.0'), 0);
    });

    test('build number decides when semver is equal', () {
      expect(UpdateService.compareVersions('2.1.0+5', '2.1.0+6'), -1);
      expect(UpdateService.compareVersions('2.1.0+6', '2.1.0+5'), 1);
      expect(
        UpdateService.compareVersions(
            '2.1.0+21', 'v2.1.0+build.21'), // cross-format
        0,
      );
    });

    test('2.1.0 vs 2.2.0', () {
      expect(UpdateService.compareVersions('2.1.0', '2.2.0'), -1);
      expect(UpdateService.compareVersions('2.2.0', '2.1.0'), 1);
    });

    test('2.10.0 vs 2.9.0 (numeric, not lexicographic)', () {
      expect(UpdateService.compareVersions('2.10.0', '2.9.0'), 1);
      expect(UpdateService.compareVersions('2.9.0', '2.10.0'), -1);
    });

    test('throws ArgumentError on unparseable input', () {
      expect(
        () => UpdateService.compareVersions('garbage', '2.1.0'),
        throwsArgumentError,
      );
      expect(
        () => UpdateService.compareVersions('2.1.0', 'v9.9'),
        throwsArgumentError,
      );
    });
  });

  group('firstNewerRelease (GitHub release envelope guards)', () {
    const repoUrl = 'https://github.com/SecretArrow/sible-mobile/releases';

    test('returns UpdateInfo for the first stable newer release', () {
      final releases = <dynamic>[
        {'draft': true, 'tag_name': 'v3.0.0+build.99'},
        {'prerelease': true, 'tag_name': 'v2.9.0+build.50'},
        {'tag_name': 'not-a-tag'},
        42, // malformed entry: skipped
        {
          'tag_name': 'v2.2.0+build.22',
          'name': 'Sible Miner 2.2.0',
          'body': '- fix A\n- feat B',
          'html_url':
              'https://github.com/SecretArrow/sible-mobile/releases/tag/v2.2.0%2Bbuild.22',
          'published_at': '2025-06-01T10:00:00Z',
        },
      ];
      final info = UpdateService.firstNewerRelease(releases, '2.1.0', 21);
      expect(info, isNotNull);
      expect(info!.tag, 'v2.2.0+build.22');
      expect(info.version, '2.2.0');
      expect(info.build, 22);
      expect(info.name, 'Sible Miner 2.2.0');
      expect(info.body, '- fix A\n- feat B');
      expect(info.htmlUrl,
          'https://github.com/SecretArrow/sible-mobile/releases/tag/v2.2.0%2Bbuild.22');
      expect(info.publishedAt, DateTime.utc(2025, 6, 1, 10));
    });

    test('falls back to tag/empty/url defaults for sparse entries', () {
      final info = UpdateService.firstNewerRelease(<dynamic>[
        {'tag_name': 'v2.5.0'},
      ], '2.1.0', 21);
      expect(info, isNotNull);
      expect(info!.name, 'v2.5.0');
      expect(info.body, '');
      expect(info.htmlUrl, repoUrl);
      expect(info.publishedAt, isNull);
    });

    test('returns null when newest stable equals current', () {
      final releases = <dynamic>[
        {'tag_name': 'v2.1.0+build.21'},
      ];
      expect(UpdateService.firstNewerRelease(releases, '2.1.0', 21), isNull);
    });

    test('returns null when newest stable is older than current', () {
      final releases = <dynamic>[
        {'tag_name': 'v2.0.0+build.5'},
      ];
      expect(UpdateService.firstNewerRelease(releases, '2.1.0', 21), isNull);
    });

    test('returns null for an empty or shapeless list', () {
      expect(UpdateService.firstNewerRelease(<dynamic>[], '2.1.0', 21), isNull);
      expect(
          UpdateService.firstNewerRelease(<dynamic>[null, 'x', 1], '2.1.0', 21),
          isNull);
      expect(
        UpdateService.firstNewerRelease(<dynamic>[
          {'draft': false}, // no tag_name
        ], '2.1.0', 21),
        isNull,
      );
    });
  });
}
