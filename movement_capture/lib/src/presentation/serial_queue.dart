import 'dart:async';

/// Runs async operations one at a time, in the order they were added.
///
/// Never `await` a [run] call from inside another operation of the same queue:
/// the inner one waits for the outer one to finish, so neither ever completes.
class SerialQueue {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// True while any operation is waiting or running.
  bool get isBusy => _pending > 0;

  Future<T> run<T>(Future<T> Function() operation) {
    _pending++;
    final result = _tail.then((_) => operation());
    _tail = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending--);
    return result;
  }
}
