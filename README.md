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
  await Execution.instance.initialize();
  runApp(MyApp());
}
```

`Execution.instance` is the singleton and `Execution.instance.isInitialized`
reports whether initialization has succeeded. `dispose()` does not reset this
flag.

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
`FutureOr<dynamic> Function() function`, and return `Future<void>`. A marker
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

`Future<void> dispose()` clears the session cache and calls `clear()` on the
shared preferences instance. **This removes all shared preferences for the
application, not just this package's markers.** It does not reset
`isInitialized`. Coordinate revocation and disposal separately with actions in
progress: an in-flight action may record its marker afterwards.

## Concurrency and persistence

Overlapping calls with the same key and scope in one isolate share one attempt
and its result. Different keys and scopes are independent. A daily call for a
new day waits for an earlier day's attempt for the same key, then starts its own
attempt even if the earlier one failed. This coordination does not extend
across isolates or processes. An interruption or failed marker write after an
external effect may cause that effect to be repeated; exactly-once delivery is
not guaranteed.

A callback must not call and await another execution with the same key and
scope: the nested call waits for the attempt that contains it, causing a
deadlock.

Daily markers use a versioned date key. Older daily markers are neither read
nor migrated because their dates can be ambiguous, so an action may run again
after upgrading.

## Breaking change: foreground API

`doOnceWhenForeground` and `ExecutionMode` have been removed. There is no
replacement foreground API; applications using them must remove those calls
and handle lifecycle events separately.
