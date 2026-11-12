# Execution

`flutter_execution` runs keyed actions once per in-memory session, once per
persistent marker, or once per local calendar day. Actions may be synchronous
or asynchronous.

## Installation

```yaml
dependencies:
  flutter_execution:
    git:
      url: git@github.com:App2Sales/flutter-execution.git
      ref: master
```

```dart
import 'package:flutter_execution/flutter_execution.dart';
```

## Initialization

Initialize before calling the execution, query, revocation or disposal APIs:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Execution.instance.initialize(maxConcurrent: 1); // default: 1
  runApp(MyApp());
}
```

`Execution.instance` is the singleton and `Execution.instance.isInitialized`
reports whether it is initialized. `maxConcurrent` must be positive and is
fixed until disposal; initialize again after disposing before executing actions.

## Execute and query

```dart
final execution = Execution.instance;

await execution.doOnceOnSession(key: 'welcome', function: () {
  print('Once for this in-memory session');
});
await execution.doOnceForever(key: 'setup', function: () async {
  await performSetup();
});
await execution.doDaily(key: 'refresh', function: () {
  print('Once today');
});

final doneToday = execution.hasExecuted(
  key: 'refresh',
  scope: ExecutionScope.daily,
);
```

All execution methods accept a required `String key` and a required
`FutureOr<dynamic> Function() function`, optional `bool bypassQueue` (default
`false`), and return `Future<void>`. A marker
is recorded only after the callback completes successfully. A callback or
marker-write failure is propagated and a later call can retry.

| Method | Scope |
| --- | --- |
| `doOnceOnSession` | In-memory session; independent of persistent markers. |
| `doOnceForever` | Persistent marker stored using `SharedPreferences`. Persistence depends on the underlying storage and is not a literal forever guarantee. |
| `doDaily` | Persistent marker for the local calendar day when the call starts; it does not schedule execution. |

`bool hasExecuted({required String key, required ExecutionScope scope})`
returns the current completion state without running a callback or changing a
marker. `ExecutionScope.session`, `ExecutionScope.forever`, and
`ExecutionScope.daily` are independent, even for the same key. The daily query
uses the current local calendar day. Before initialization, the query throws a
`StateError`.

The query returns `false` while an action or its marker write is in progress,
and after a failed callback or marker write, until a successful completion is
recorded. Querying and then executing are separate operations and do **not**
provide mutual exclusion.

## Revocation and disposal

```dart
await execution.revokeKey('setup');
await execution.dispose();
```

`Future<void> revokeKey(String key)` resets the session and permanent markers
for that key, but does not revoke daily markers.

`Future<void> dispose()` rejects new actions immediately and waits for all
accepted actions, including bypassed actions and failures. An action that never
finishes prevents disposal from completing. It then clears the in-memory
session cache and resets `isInitialized`, without removing any shared
preferences. Permanent and daily markers, including those written by actions
drained during disposal, remain in storage. `revokeKey` is not queued:
coordinate revocations with pending and running actions yourself.

## Concurrency and persistence

Actions automatically enter an in-memory FIFO queue, shared by this singleton
in its isolate. Eligible jobs start as soon as slots are available; by default
only one runs at a time. With `maxConcurrent > 1`, completion order can differ
from entry order. `bypassQueue: true` starts without waiting for a slot and does
not count against the limit, so total concurrency can exceed it. Completed
actions are not forced to run again by bypass.

Overlapping calls with the same key, scope, and period share one attempt and its
result. Bypassing a pending attempt promotes it: the **first caller's callback**
runs, not the bypass caller's, and the original queue item cannot run it again.
An already running attempt is shared. A daily call uses the local day at call
time, even if its callback runs later. A different day's attempt for the same
key waits for the earlier one, even with bypass and even if the earlier one
fails; it does not occupy a queue slot while waiting. Errors reach all callers,
do not stop the queue, and are not automatically retried; a subsequent call
may retry.

This queue is independent of UI, lifecycle, and first-frame events. It is not
persistent, loses pending work on process exit, and does not schedule OS
background work. It does not move CPU work to another isolate. Coordination does
not extend across isolates or processes. An interruption or failed marker write after an
external effect may cause that effect to be repeated; exactly-once delivery is
not guaranteed.

The implementation uses `queue` for FIFO and bounded concurrency, with keyed
deduplication and promotion managed by this package. `pool` limits resource
use but does not provide this queue and keyed contract; `async` memoization is
not a job scheduler. For durable or OS-scheduled work, use a separate solution
such as Workmanager, subject to its platform restrictions; it is not equivalent
to this in-memory queue.

A callback must not await another action in the same queue: if all slots are
occupied, it can deadlock. Bypass may avoid waiting for a slot, but does not
resolve recursive calls with the same key and scope or other dependencies
between actions.

Daily markers use a versioned date key. Older daily markers are neither read
nor migrated because their dates can be ambiguous, so an action may run again
after upgrading.

## Startup experiment

Run `flutter test benchmark/startup_queue_test.dart --reporter expanded`. This
synthetic test starts 50 light CPU-plus-1ms-timer actions and measures the
time until the next zero-delay event and until all actions finish, comparing
direct concurrent calls against the default queue. It uses mock preferences,
suppresses execution logging for the queued run, runs the baseline first, and
does not render a Flutter frame. Results vary with scheduling and warm-up.

One run on 2026-11-12, Apple M2, macOS 27.0, Flutter 3.47.8 / Dart 3.13.7:
baseline 6.482 ms to the next event and 9.018 ms total; queued 1.910 ms and
124.965 ms respectively. This is not evidence of improved app startup or frame
performance; measure a representative app and device before drawing conclusions.
The `queue` 3.4.0 dependency resolved and ran on this SDK. Its Dart constraint
also intersects the declared legacy SDK range, but Flutter 2.2.0 / Dart 2.x
was not available for runtime verification.

## Breaking change: foreground API

`doOnceWhenForeground` and `ExecutionMode` have been removed. There is no
replacement foreground API; applications using them must remove those calls
and handle lifecycle events separately.
