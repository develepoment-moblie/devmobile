import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Clears the exit confirmation whenever a page, dialog or sheet changes.
class AppNavigationObserver extends NavigatorObserver {
  VoidCallback? onNavigation;

  void _changed() => onNavigation?.call();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed();
}

/// System Back: current modal/page, then tab history, then double-back exit.
/// Only the application boundary may request Android to close the activity.
class AppBackNavigation extends StatefulWidget {
  final AppNavigationObserver observer;
  final Widget child;
  const AppBackNavigation({
    super.key,
    required this.observer,
    required this.child,
  });

  static const exitMessage =
      'Appuyez encore sur Retour pour quitter l’application.';
  static const exitWindow = Duration(seconds: 2);

  static void reset(BuildContext context) => context
      .getInheritedWidgetOfExactType<_BackScope>()
      ?.state
      .resetExitPrompt();

  static bool available(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BackScope>() != null;

  static VoidCallback? registerTabs(
    BuildContext context,
    bool Function() goBack,
  ) {
    final state = context
        .dependOnInheritedWidgetOfExactType<_BackScope>()
        ?.state;
    if (state == null) return null;
    state._tabBack = goBack;
    return () {
      if (state._tabBack == goBack) state._tabBack = null;
    };
  }

  @override
  State<AppBackNavigation> createState() => _AppBackNavigationState();
}

class _AppBackNavigationState extends State<AppBackNavigation>
    with WidgetsBindingObserver {
  _SessionNavigatorState? _session;
  bool Function()? _tabBack;
  Timer? _exitTimer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _prompt;
  bool _handlingBack = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.observer.onNavigation = resetExitPrompt;
  }

  @override
  void didUpdateWidget(AppBackNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.observer != widget.observer) {
      oldWidget.observer.onNavigation = null;
      widget.observer.onNavigation = resetExitPrompt;
    }
  }

  void resetExitPrompt() {
    _exitTimer?.cancel();
    _exitTimer = null;
    final prompt = _prompt;
    if (prompt != null) {
      // Navigator observers may run during a build; defer messenger updates.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // A resume or another Back event may already have replaced this hint.
        if (mounted && _prompt == prompt) {
          _prompt = null;
          prompt.close();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) resetExitPrompt();
  }

  Future<void> _back() async {
    if (_handlingBack) return;
    _handlingBack = true;
    try {
      if (MediaQuery.viewInsetsOf(context).bottom > 0) {
        FocusManager.instance.primaryFocus?.unfocus();
        resetExitPrompt();
        return;
      }
      final session = _session;
      if (session == null || session.widget.enabled) {
        // maybePop also respects a form's PopScope and a sheet's local history.
        if (session != null && await session.maybePop()) return;
        if (!mounted || session != _session) return;
        if (_tabBack?.call() ?? false) {
          resetExitPrompt();
          return;
        }
      }
      if (!mounted ||
          kIsWeb ||
          defaultTargetPlatform != TargetPlatform.android) {
        return;
      }
      if (_exitTimer?.isActive ?? false) {
        resetExitPrompt();
        await SystemNavigator.pop();
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      // An old success message must not delay the exit instruction.
      messenger.clearSnackBars();
      messenger.removeCurrentSnackBar();
      final prompt = messenger.showSnackBar(
        const SnackBar(
          content: Text(AppBackNavigation.exitMessage),
          duration: AppBackNavigation.exitWindow,
        ),
      );
      _prompt = prompt;
      prompt.closed.then((_) {
        if (_prompt == prompt) _prompt = null;
      });
      _exitTimer = Timer(AppBackNavigation.exitWindow, () {
        _exitTimer = null;
      });
    } finally {
      _handlingBack = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.observer.onNavigation = null;
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BackScope(
    state: this,
    child: Listener(
      onPointerDown: (_) => resetExitPrompt(),
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_back());
        },
        child: widget.child,
      ),
    ),
  );
}

class _BackScope extends InheritedWidget {
  final _AppBackNavigationState state;
  const _BackScope({required this.state, required super.child});
  @override
  bool updateShouldNotify(_BackScope oldWidget) => state != oldWidget.state;
}

/// A fresh keyed instance owns each authenticated session's navigation stack.
class SessionNavigator extends StatefulWidget {
  final bool enabled;
  final WidgetBuilder homeBuilder;
  const SessionNavigator({
    super.key,
    required this.enabled,
    required this.homeBuilder,
  });
  @override
  State<SessionNavigator> createState() => _SessionNavigatorState();
}

class _SessionNavigatorState extends State<SessionNavigator> {
  final _navigator = GlobalKey<NavigatorState>();
  final _observer = AppNavigationObserver();
  _AppBackNavigationState? _coordinator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .dependOnInheritedWidgetOfExactType<_BackScope>()
        ?.state;
    if (next == _coordinator) return;
    _detach();
    _coordinator = next;
    next?._session = this;
    next?.resetExitPrompt();
    _observer.onNavigation = () => _coordinator?.resetExitPrompt();
  }

  Future<bool> maybePop() async =>
      await _navigator.currentState?.maybePop() ?? false;

  void _detach() {
    if (_coordinator?._session == this) {
      _coordinator?._session = null;
      _coordinator?.resetExitPrompt();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigator,
    observers: [_observer],
    onGenerateRoute: (_) =>
        MaterialPageRoute<void>(builder: widget.homeBuilder),
  );
}
