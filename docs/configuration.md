# Configuration and limitations

## Queue and concurrency

Actions share an in-memory FIFO queue within the current isolate. By default,
one queued action runs at a time. Configuration is optional and can be changed
at any time:

```dart
Do.configure(maxConcurrent: 3);
```

Increasing the limit starts waiting actions as slots become available. Reducing
it does not interrupt running actions; waiting actions start only when the
number of running queued actions falls below the new limit. The limit must be
positive. `bypassQueue: true` starts an eligible action without waiting for a
slot and does not count against the limit. It does not force a completed action
to run again.

**Overlapping calls with the same key, scope, and period share one attempt.**
Only the first caller's function runs; all callers await the same success or
error, even if later callers supply different functions. A bypass call promotes
a pending attempt using that original function. An already running attempt is
shared. For calendar actions with the same key and scope but different periods,
the later attempt waits for the earlier one, even with bypass and even if the earlier
attempt fails; it does not occupy a queue slot while waiting.

A queued function must not await another action in the same queue if all slots
may be occupied: it can deadlock. Bypass may avoid waiting for a slot, but does
not resolve recursive calls with the same key and scope or other dependencies.

## Persistence and limitations

The session state, queue, and coordination are **per isolate**, not shared
across isolates or processes. Concurrent calls from different isolates can run
the same action. The queue is not persistent, does not schedule OS background
work, and does not move CPU work to another isolate. Pending work is lost on
process exit. Flutter applications must provide the usual initialized Flutter
binding before a persistent operation uses platform plugins.

An interruption or failed marker write after an external effect may cause that
effect to be repeated. Exactly-once delivery is not guaranteed.
