# Do Once example

An interactive demo of the execution scopes in [`do_once`](../README.md).

From this directory, run:

```sh
flutter pub get
flutter run
```

Choose a scope and select **Celebrate**. The first call shows confetti and
records its completion; subsequent calls with the same key and scope skip it.
The activity log shows what happened. Select **Reset completion** to revoke
that scope's marker and celebrate again. The default, **Until reset**, uses
`Do.once`.

Session completion lasts for the current isolate. The other scopes use persistent
storage: **Until reset** has no calendar expiration, while hourly, daily,
monthly, and yearly completion applies to the current local calendar period.
Scopes are independent, even when they use the same key. Resetting a calendar
scope affects only its current period.

For API details, queue configuration, and limitations, see the
[package README](../README.md) and [configuration guide](../docs/configuration.md).
