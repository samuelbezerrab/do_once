# Do Once

[![pub package](https://img.shields.io/pub/v/do_once.svg)](https://pub.dev/packages/do_once)
[![pub points](https://img.shields.io/pub/points/do_once)](https://pub.dev/packages/do_once/score)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Easily run tasks that shouldn’t run every time.

```dart
await Do.once(
  key: 'welcome',
  function: () async => welcomeUser(),
);
```

do_once runs actions identified by a key once per session, once per local day, or once until reset. It automatically queues actions to limit concurrent work and supports both synchronous and asynchronous callbacks.

Following the Don’t Repeat Yourself (DRY) principle, it tracks completed actions so you don’t have to write the same checks throughout your app.

## How to use
```dart
import 'package:do_once/do_once.dart';
```


```dart
await Do.oncePerSession(
  key: 'welcome',
  function: () => showWelcome(),
);

await Do.once(
  key: 'setup',
  function: () async => performSetup(),
);

await Do.oncePerDay(
  key: 'refresh',
  function: () => refreshReferenceData(),
);

await Do.oncePerHour(
  key: 'refresh',
  function: () => refreshReferenceData(),
);
```

| Method | Scope |
| --- | --- |
| `Do.once` | Persistent completion marker in `SharedPreferences`. |
| `Do.oncePerSession` | In memory, for the lifetime of the current isolate. |
| `Do.oncePerDay` | Persistent marker for the local calendar day of the call. |
| `Do.oncePerHour` | Persistent marker for the local calendar hour of the call. |
| `Do.oncePerMonth` | Persistent marker for the local calendar month of the call. |
| `Do.oncePerYear` | Persistent marker for the local calendar year of the call. |
| `Do.onceAndDone` | Alias for `Do.once`; shares its marker and any in-flight attempt. |

Each method accepts a required `String key`, a required synchronous or
asynchronous `function`, and an optional `bool bypassQueue` (default `false`).
It returns `Future<void>`. Completion is recorded only after the function
succeeds and, for persistent scopes, the marker is written successfully.
Errors are propagated; a subsequent call may retry.

[!NOTE]
Calendar scopes use the local calendar period **when the call is made**, even if
the action starts later. They do not schedule actions. If a local hour repeats
when clocks move back, both occurrences share the same hourly marker.

## Query and revoke

```dart
final doneToday = await Do.hasExecuted(
  key: 'refresh',
  scope: DoScope.daily,
);

await Do.revoke(key: 'refresh', scope: DoScope.daily);
```

`DoScope.session`, `DoScope.forever`, `DoScope.daily`, `DoScope.hourly`,
`DoScope.monthly`, and `DoScope.yearly` are independent, even for the same key.
A calendar query or revocation uses the current local period; revocation affects
only the requested scope and does not remove markers for other periods.
Calendar markers are retained in storage rather than automatically cleaned up.
`SharedPreferences` is loaded automatically when a persistent scope needs it.

`hasExecuted` returns `false` while an action or marker write is pending and
after a failed action or write, until completion is successfully recorded.
Querying and executing are separate operations and do **not** provide mutual
exclusion. Revocation does not wait for pending or running actions; such an
action may record completion after the revocation. Coordinate these operations
in application code when that matters.

## Extra configuration

Actions share a queue that runs one action at a time by default. This helps limit resource usage when many actions are requested at once, such as during app startup. To allow more actions to run concurrently, configure the limit:

```dart
Do.configure(maxConcurrent: 3);
```

Learn more about [queue and concurrency](docs/configuration.md#queue-and-concurrency).

## Persistence and limitations

[Read about persistence and limitations](docs/configuration.md#persistence-and-limitations).

## License

This project is licensed under the [MIT License](LICENSE).
