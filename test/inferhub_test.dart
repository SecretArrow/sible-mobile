/// Pure unit tests for the InferHub AI integration.
///
/// Imports only `lib/models/inferhub_models.dart` (framework- and
/// plugin-free). The HTTP service (`inferhub_service.dart`) is intentionally
/// NOT imported here because it pulls platform plugins
/// (flutter_secure_storage / shared_preferences); its pure client-side search
/// lives in `ModelPage.search` and is exercised below via the same code path
/// (`InferHubService.searchModels` delegates 1:1 to `ModelPage.search`).
import 'package:flutter_test/flutter_test.dart';
import 'package:sible_mobile/models/inferhub_models.dart';

void main() {
  group('InferHubModel.fromJson (defensive parse)', () {
    test('returns empty model for non-map input', () {
      final m = InferHubModel.fromJson('junk');
      expect(m.id, '');
      expect(m.free, isFalse);
      expect(m.contextLength, isNull);
      expect(m.inputPrice, isNull);
      expect(m.outputPrice, isNull);
    });

    test('returns empty id (and defaults) for an empty map', () {
      final m = InferHubModel.fromJson(const {});
      expect(m.id, '');
      expect(m.free, isFalse);
      expect(m.contextLength, isNull);
    });

    test('parses id + nested pricing + context', () {
      final m = InferHubModel.fromJson(const {
        'id': 'z-ai/glm-4.6',
        'pricing': {'input': 0.5, 'output': 1.5},
        'contextLength': 128000,
      });
      expect(m.id, 'z-ai/glm-4.6');
      expect(m.free, isFalse);
      expect(m.inputPrice, 0.5);
      expect(m.outputPrice, 1.5);
      expect(m.contextLength, 128000);
    });

    test('accepts alternative field names (model/name, snake_case)', () {
      final m = InferHubModel.fromJson(const {
        'model': 'vendor/net',
        'input_price': '2',
        'output_price': '4.5',
        'context_window': '8192',
      });
      expect(m.id, 'vendor/net');
      expect(m.inputPrice, 2.0);
      expect(m.outputPrice, 4.5);
      expect(m.contextLength, 8192);
    });

    test('marks free/<slug>/<model> ids as free', () {
      final m = InferHubModel.fromJson(
          const {'id': 'free/meta/llama-3', 'pricing': null});
      expect(m.free, isTrue);
    });

    test('marks explicit free flag as free', () {
      final m = InferHubModel.fromJson(const {'id': 'x/y', 'free': true});
      expect(m.free, isTrue);
    });

    test('marks zero prices as free', () {
      final m = InferHubModel.fromJson(const {
        'id': 'x/y',
        'inputPrice': 0,
        'outputPrice': '0.0',
      });
      expect(m.free, isTrue);
      expect(m.inputPrice, 0.0);
      expect(m.outputPrice, 0.0);
    });

    test('non-zero prices are NOT free', () {
      final m = InferHubModel.fromJson(const {
        'id': 'x/y',
        'inputPrice': 0,
        'outputPrice': 0.01,
      });
      expect(m.free, isFalse);
    });
  });

  group('ModelPage.search (pagination + query clamping)', () {
    List<InferHubModel> catalog(int n) =>
        List.generate(n, (i) => InferHubModel(id: 'vendor/model-$i'));

    test('slices pages and reports totals', () {
      final page = ModelPage.search(catalog(45), page: 1);
      expect(page.total, 45);
      expect(page.totalPages, 3);
      expect(page.page, 1);
      expect(page.models.length, 20);
      expect(page.models.first.id, 'vendor/model-20');
    });

    test('clamps out-of-range pages into the valid range', () {
      final tooFar = ModelPage.search(catalog(45), page: 99);
      expect(tooFar.page, 2);
      expect(tooFar.models.length, 5);

      final tooLow = ModelPage.search(catalog(45), page: -3);
      expect(tooLow.page, 0);
    });

    test('last page is partial, not empty', () {
      final page = ModelPage.search(catalog(45), page: 2);
      expect(page.models.length, 5);
      expect(page.models.last.id, 'vendor/model-44');
    });

    test('filters by case-insensitive substring on the id', () {
      final all = [
        const InferHubModel(id: 'z-ai/glm-4.6'),
        const InferHubModel(id: 'openai/gpt-4o'),
        const InferHubModel(id: 'free/meta/llama-3'),
      ];
      final page = ModelPage.search(all, query: '  GLM ');
      expect(page.total, 1);
      expect(page.models.single.id, 'z-ai/glm-4.6');
    });

    test('query with no match still reports one empty page', () {
      final page = ModelPage.search(catalog(10), query: 'nope');
      expect(page.total, 0);
      expect(page.totalPages, 1);
      expect(page.page, 0);
      expect(page.models, isEmpty);
    });

    test('empty catalog reports one empty page', () {
      final page = ModelPage.search(const []);
      expect(page.total, 0);
      expect(page.totalPages, 1);
      expect(page.models, isEmpty);
    });

    test('pageSize <= 0 falls back to 20', () {
      final page = ModelPage.search(catalog(25), pageSize: 0);
      expect(page.totalPages, 2);
      expect(page.models.length, 20);
    });
  });

  group('AiAccelerationPlan.fromLlmText (plan JSON parsing)', () {
    test('parses clean JSON', () {
      final plan = AiAccelerationPlan.fromLlmText(
          '{"targetPercent": 40, "extendSession": true, "rationale": "ok"}');
      expect(plan.targetPercent, 40);
      expect(plan.extendSession, isTrue);
      expect(plan.rationale, 'ok');
    });

    test('parses JSON wrapped in prose', () {
      final plan = AiAccelerationPlan.fromLlmText(
          'Sure! Here you go: {"target_percent": 60} — done.');
      expect(plan.targetPercent, 60);
      expect(plan.extendSession, isFalse);
      expect(plan.rationale, '');
    });

    test('accepts the generic "percent" key', () {
      final plan = AiAccelerationPlan.fromLlmText('{"percent": 20}');
      expect(plan.targetPercent, 20);
    });

    test('snaps out-of-range values to the nearest allowed slot', () {
      expect(
          AiAccelerationPlan.fromLlmText('{"targetPercent": 5}').targetPercent,
          20);
      expect(
          AiAccelerationPlan.fromLlmText('{"targetPercent": 100}')
              .targetPercent,
          60);
      expect(
          AiAccelerationPlan.fromLlmText('{"targetPercent": 50}').targetPercent,
          40);
    });

    test('missing percent falls back to 60', () {
      final plan = AiAccelerationPlan.fromLlmText('{"rationale": "go big"}');
      expect(plan.targetPercent, 60);
    });

    test('non-numeric percent falls back to 60', () {
      final plan = AiAccelerationPlan.fromLlmText('{"targetPercent": "fast"}');
      expect(plan.targetPercent, 60);
    });

    test('garbage input throws FormatException', () {
      expect(
        () => AiAccelerationPlan.fromLlmText('no json here at all'),
        throwsFormatException,
      );
    });
  });

  group('AiTaskAnswer.fromLlmText (task answer parsing)', () {
    test('parses clean JSON with a submission map', () {
      final a = AiTaskAnswer.fromLlmText(
          '{"shouldSubmit": true, "submission": {"answer": "42"}, '
          '"rationale": "r"}');
      expect(a.shouldSubmit, isTrue);
      expect(a.submission, {'answer': '42'});
      expect(a.rationale, 'r');
    });

    test('parses JSON wrapped in prose', () {
      final a = AiTaskAnswer.fromLlmText(
          'Answer: {"should_submit": true, "submission": {"code": 7}} thanks');
      expect(a.shouldSubmit, isTrue);
      expect(a.submission, {'code': 7});
    });

    test('missing/non-map submission falls back to empty', () {
      final a = AiTaskAnswer.fromLlmText('{"shouldSubmit": true}');
      expect(a.shouldSubmit, isTrue);
      expect(a.submission, isEmpty);
    });

    test('garbage input throws FormatException', () {
      expect(
        () => AiTaskAnswer.fromLlmText(']]] nothing'),
        throwsFormatException,
      );
    });
  });

  group('parseExtensionIdsFromLlm', () {
    test('parses a clean array with dedupe', () {
      final ids = parseExtensionIdsFromLlm('["a", "b", "a", "c", "d"]');
      expect(ids, ['a', 'b', 'c']);
    });

    test('parses an array wrapped in prose', () {
      final ids = parseExtensionIdsFromLlm('Picks: ["x","y"] - done');
      expect(ids, ['x', 'y']);
    });

    test('caps the result at max', () {
      final ids = parseExtensionIdsFromLlm('["1","2","3","4"]', max: 2);
      expect(ids, ['1', '2']);
    });

    test('skips non-string / blank entries', () {
      final ids = parseExtensionIdsFromLlm('[1, "", "ok", null]');
      expect(ids, ['1', 'ok']);
    });

    test('garbage input throws FormatException', () {
      expect(() => parseExtensionIdsFromLlm('no array'), throwsFormatException);
    });

    test('non-array JSON throws FormatException', () {
      expect(() => parseExtensionIdsFromLlm('{"not": "array"}'),
          throwsFormatException);
    });
  });

  group('InferHubConfig map roundtrip', () {
    const cfg = InferHubConfig(
      enabled: true,
      model: 'z-ai/glm-4.6',
      freeOnly: true,
      taskSolver: false,
      planner: true,
      extensionPicker: false,
      temperature: 1.5,
      maxTokens: 256,
      maxInputPrice: 2.0,
      maxOutputPrice: 3.5,
      timeoutSeconds: 90,
    );

    test('toMap -> fromMap preserves all persisted fields', () {
      final restored = InferHubConfig.fromMap(cfg.toMap());
      expect(restored.enabled, cfg.enabled);
      expect(restored.model, cfg.model);
      expect(restored.freeOnly, cfg.freeOnly);
      expect(restored.taskSolver, cfg.taskSolver);
      expect(restored.planner, cfg.planner);
      expect(restored.extensionPicker, cfg.extensionPicker);
      expect(restored.temperature, cfg.temperature);
      expect(restored.maxTokens, cfg.maxTokens);
      expect(restored.maxInputPrice, cfg.maxInputPrice);
      expect(restored.maxOutputPrice, cfg.maxOutputPrice);
      expect(restored.timeoutSeconds, cfg.timeoutSeconds);
    });

    test('apiKey is never persisted', () {
      final map = cfg.copyWith(apiKey: 'sk-airo-secret').toMap();
      expect(map.containsKey('apiKey'), isFalse);
      expect(InferHubConfig.fromMap(map).apiKey, '');
    });

    test('non-map input falls back to defaults', () {
      final restored = InferHubConfig.fromMap('junk');
      expect(restored.enabled, isFalse);
      expect(restored.model, '');
      expect(restored.temperature, 0.2);
      expect(restored.timeoutSeconds, 60);
    });

    test('clamps temperature / timeout / maxTokens on deserialize', () {
      final restored = InferHubConfig.fromMap(const {
        'temperature': '9',
        'timeoutSeconds': 1,
        'maxTokens': -5,
      });
      expect(restored.temperature, 2);
      expect(restored.timeoutSeconds, 5);
      expect(restored.maxTokens, 1);
    });

    test('accepts string booleans / numbers from prefs', () {
      final restored = InferHubConfig.fromMap(const {
        'enabled': 'true',
        'model': 'free/meta/llama-3',
        'taskSolver': 'false',
        'maxTokens': '1024',
        'maxInputPrice': '1.25',
      });
      expect(restored.enabled, isTrue);
      expect(restored.model, 'free/meta/llama-3');
      expect(restored.taskSolver, isFalse);
      expect(restored.maxTokens, 1024);
      expect(restored.maxInputPrice, 1.25);
    });
  });
}
