import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movement_capture/src/presentation/serial_queue.dart';

void main() {
  test('runs operations one at a time, in order', () async {
    final queue = SerialQueue();
    final log = <String>[];
    var running = 0;
    var maxRunning = 0;

    Future<void> op(String name, int ms) async {
      running++;
      if (running > maxRunning) maxRunning = running;
      log.add('start $name');
      await Future<void>.delayed(Duration(milliseconds: ms));
      log.add('end $name');
      running--;
    }

    await Future.wait([
      queue.run(() => op('a', 30)),
      queue.run(() => op('b', 5)),
      queue.run(() => op('c', 10)),
    ]);

    expect(maxRunning, 1);
    expect(log, ['start a', 'end a', 'start b', 'end b', 'start c', 'end c']);
  });

  test('a failing operation does not block the next one', () async {
    final queue = SerialQueue();
    final failed = queue.run<void>(() async => throw StateError('boom'));
    final next = queue.run(() async => 42);
    await expectLater(failed, throwsStateError);
    expect(await next, 42);
  });

  test('isBusy is true while work is pending', () async {
    final queue = SerialQueue();
    final gate = Completer<void>();
    final done = queue.run(() => gate.future);
    expect(queue.isBusy, isTrue);
    gate.complete();
    await done;
    await Future<void>.delayed(Duration.zero);
    expect(queue.isBusy, isFalse);
  });
}
