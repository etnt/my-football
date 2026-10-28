import 'package:flutter_test/flutter_test.dart';
import 'package:my_football/features/ai/ai_log.dart';

void main() {
  setUp(AiLog.clear);

  test('keeps the newest lines and stamps each one', () {
    for (var i = 0; i < 45; i++) {
      AiLog.add('event $i');
    }
    final lines = AiLog.lines.value;
    expect(lines.length, 40);
    expect(lines.last, endsWith('event 44'));
    expect(lines.first, endsWith('event 5'));
    expect(lines.first, matches(RegExp(r'^\d\d:\d\d:\d\d event 5$')));
  });

  test('clear empties the log', () {
    AiLog.add('something');
    AiLog.clear();
    expect(AiLog.lines.value, isEmpty);
  });
}
