import 'dart:async';

import 'package:do_once/do_once.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const DoOnceExample());
}

class DoOnceExample extends StatelessWidget {
  const DoOnceExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Do Once example',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B52B6),
        scaffoldBackgroundColor: const Color(0xFFF7F7FB),
        useMaterial3: true,
      ),
      home: const ExamplePage(),
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  static const _actionKey = 'showConfetti';
  static const _confettiAsset = 'assets/confetti.gif';
  static const _confettiDuration = Duration(milliseconds: 3750);

  DoScope _scope = DoScope.forever;
  bool? _completed;
  bool _busy = true;
  bool _showingConfetti = false;
  int _celebration = 0;
  Timer? _confettiTimer;
  final List<String> _log = ['Choose a scope and celebrate.'];

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _confettiTimer?.cancel();
    super.dispose();
  }

  void _addLog(String message) {
    _log.insert(0, message);
    if (_log.length > 2) _log.removeLast();
  }

  void _hideConfetti() {
    _confettiTimer?.cancel();
    _showingConfetti = false;
  }

  void _showConfetti() {
    if (!mounted) return;
    _confettiTimer?.cancel();
    // Start the animation from the beginning even if the image was cached.
    PaintingBinding.instance.imageCache.evict(const AssetImage(_confettiAsset));
    setState(() {
      _showingConfetti = true;
      _celebration++;
    });
    _confettiTimer = Timer(_confettiDuration, () {
      if (mounted) setState(() => _showingConfetti = false);
    });
  }

  Future<void> _refreshStatus() async {
    setState(() => _busy = true);
    try {
      final completed = await Do.hasExecuted(key: _actionKey, scope: _scope);
      if (!mounted) return;
      setState(() => _completed = completed);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _completed = null;
        _addLog('Could not check completion: $error');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAction() async {
    setState(() => _busy = true);
    var ran = false;
    void action() {
      ran = true;
      _showConfetti();
    }

    try {
      switch (_scope) {
        case DoScope.session:
          await Do.oncePerSession(key: _actionKey, function: action);
        case DoScope.forever:
          await Do.once(key: _actionKey, function: action);
        case DoScope.hourly:
          await Do.oncePerHour(key: _actionKey, function: action);
        case DoScope.daily:
          await Do.oncePerDay(key: _actionKey, function: action);
        case DoScope.monthly:
          await Do.oncePerMonth(key: _actionKey, function: action);
        case DoScope.yearly:
          await Do.oncePerYear(key: _actionKey, function: action);
      }
      final completed = await Do.hasExecuted(key: _actionKey, scope: _scope);
      if (!mounted) return;
      setState(() {
        _completed = completed;
        _addLog(ran
            ? '${_scopeLabel(_scope)}: action ran!'
            : '${_scopeLabel(_scope)}: already completed; action skipped.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _completed = null;
        _addLog('Could not complete the action: $error');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetAction() async {
    setState(() => _busy = true);
    try {
      await Do.revoke(key: _actionKey, scope: _scope);
      final completed = await Do.hasExecuted(key: _actionKey, scope: _scope);
      if (!mounted) return;
      setState(() {
        _hideConfetti();
        _completed = completed;
        _addLog('${_scopeLabel(_scope)}: completion reset.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _completed = null;
        _addLog('Could not reset completion: $error');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (_completed) {
      true => 'Completed',
      false => 'Not completed',
      null => 'Unknown',
    };
    final theme = Theme.of(context);
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Celebrate once', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('The confetti only plays when the action runs.'),
        const SizedBox(height: 16),
        const Text('Execution scope'),
        DropdownButton<DoScope>(
          value: _scope,
          isExpanded: true,
          items: DoScope.values
              .map((scope) => DropdownMenuItem(
                    value: scope,
                    child: Text(_scopeLabel(scope)),
                  ))
              .toList(),
          onChanged: _busy
              ? null
              : (scope) {
                  if (scope == null) return;
                  setState(() {
                    _hideConfetti();
                    _scope = scope;
                    _completed = null;
                    _addLog('Selected ${_scopeLabel(scope)}.');
                  });
                  _refreshStatus();
                },
        ),
        const SizedBox(height: 8),
        Text('Status: $status', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _runAction,
          child: const Text('Celebrate'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : _resetAction,
          child: const Text('Reset completion'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Session lasts for the current isolate. Other scopes persist; '
          'calendar scopes use the current local period.',
        ),
      ],
    );

    final activityLog = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Activity log', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final entry in _log)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $entry'),
          ),
      ],
    );

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8F7FF), Color(0xFFECEBFA)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 650;
              final display = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide) ...[
                    SizedBox(
                      height: 200,
                      child: _showingConfetti
                          ? Center(
                              child: Image.asset(
                                _confettiAsset,
                                key: ValueKey(_celebration),
                                width: 200,
                                height: 200,
                                semanticLabel: 'Confetti celebration',
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  activityLog,
                ],
              );
              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: wide ? 32 : 40,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: controls),
                                  const SizedBox(width: 40),
                                  Expanded(child: display),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  controls,
                                  const SizedBox(height: 32),
                                  display,
                                ],
                              ),
                      ),
                    ),
                  ),
                  if (!wide && _showingConfetti)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: Image.asset(
                            _confettiAsset,
                            key: ValueKey(_celebration),
                            width: 200,
                            height: 200,
                            semanticLabel: 'Confetti celebration',
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _scopeLabel(DoScope scope) => switch (scope) {
      DoScope.session => 'Session',
      DoScope.forever => 'Until reset',
      DoScope.hourly => 'Hourly',
      DoScope.daily => 'Daily',
      DoScope.monthly => 'Monthly',
      DoScope.yearly => 'Yearly',
    };
