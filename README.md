# Execution

With this package you can easily execute functions that you need execute one time on session (when app starts) or one time forever.

## Usage
To use this package, add flutter_execution as a dependency in your pubspec.yaml file.

```yaml
dependencies:
    flutter:
        sdk: flutter
    flutter_execution:
        git:
            url: git@github.com:App2Sales/flutter-execution.git
            ref: master
```

Import the Execution package.
```dart
import 'package:flutter_execution/flutter_execution.dart';
```

Initialize Execution instance inside main as a singleton. Don't forget to `await`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Execution.instance.initialize();
  runApp(MyApp());
}
```

Or, wrap Execution initialization in `initState` as soon as the application starts:
```dart
  @override
  void initState() {
    Execution.instance.initialize();
    super.initState();
  }
```

If you initialize in `initState` and want to call some of Execution methods right after this, consider using `then` to wait for asynchronous computation:

```dart
 @override
  void initState() {
    Execution.instance.initialize().then((_) {
      Execution.instance.doOnceForever(
        key: 'printOnce',
        function: () => print('Only once forever'),
      );
    });
    super.initState();
  }
```

After initialize properly, you can call `doOnceForever` to Execute a function, one time, forever:

```dart
 Execution.instance.doOnceForever(
    key: 'printOnceForever',
    function: () => print('Only once forever'),
   );
```

Or, call `doOnceOnSession` to execute a function on session (Just one time on app startup):

```dart
Execution.instance.doOnceOnSession(
      key: 'printOnceOnSession',
      function: () => print('Only once on session'),
    );
```

You can also call `doOnceWhenForeground` to execute a function when app come to the foreground:

```dart
Execution.instance.doOnceWhenForeground(
      key: 'onceInForeground',
      mode: ExecutionMode.onceForever,
      function: () => print('Only once forever when foreground'),
    );
```

`doDaily` executes an action once per local calendar day, using the day at the
start of the call. Daily markers now use an unambiguous, versioned date key;
older daily markers are neither read nor migrated because their dates can be
ambiguous. Consequently, an action may run again after upgrading.

Overlapping calls with the same key and scope in the same isolate share one
attempt and its result. Different keys and scopes are independent. A daily
call for a new day waits for an earlier day's attempt for the same key, then
starts its own attempt even if the earlier one failed. Failed callbacks or
marker writes are reported to all callers; a later call can retry.

This coordination does not extend across isolates or processes. It cannot
guarantee an external effect occurs exactly once: an interruption or failed
marker write after the effect may cause it to be repeated. Coordinate
`revokeKey` and `dispose` separately with any ongoing executions.

After using this package, dispose it. This will delete locally saved functions identifiers.

```dart
 Execution.instance.dispose();
```

## Reference

#### `doOnceForever` and `doOnceOnSession`:

| Parameter | Default                  | Description                      |
|-----------|--------------------------|----------------------------------|
| key       | required String          | An identifier for your function. |
| function  | required void Function() | Your function.                   |

#### `doOnceWhenForeground`:

| Parameter | Default                  | Description                                                                                              |
|-----------|--------------------------|----------------------------------------------------------------------------------------------------------|
| key       | required String          | An identifier for your function.                                                                         |
| mode      | required ExecutionMode   | onceForever: Execute a function one time forever. onceOnSession: Execute a function one time on session. |
| function  | required void Function() | Your function.                                                                                           |

## Getting Started with Flutter

This project is a starting point for a Dart
[package](https://flutter.dev/developing-packages/),
a library module containing code that can be shared easily across
multiple Flutter or Dart projects.

For help getting started with Flutter, view our 
[online documentation](https://flutter.dev/docs), which offers tutorials, 
samples, guidance on mobile development, and a full API reference.
