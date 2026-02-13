import 'dart:async';
import 'package:flutter/material.dart';


class TimeoutDurations {
  static const short = Duration(seconds: 25);
  static const medium = Duration(seconds: 45);
  static const long = Duration(seconds: 60);
}

class InactivityWatcher {
  final Duration timeout;
  final VoidCallback onTimeout;
  Timer? _timer;

  InactivityWatcher({required this.timeout, required this.onTimeout});

  void start() {
    _cancel();
    _timer = Timer(timeout, onTimeout);
  }

  void reset() {
    _cancel();
    _timer = Timer(timeout, onTimeout);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => _cancel();
}

/// Global route observer — hangi sayfa aktif onu izler
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

/// Kullanımı kolaylaştırmak için hazır widget sarmalayıcı
class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;
  final VoidCallback onTimeout;
  final bool autoPauseOnNavigate; // 👈 eklendi

  const InactivityWrapper({
    super.key,
    required this.child,
    required this.timeout,
    required this.onTimeout,
    this.autoPauseOnNavigate = true,
  });

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> with RouteAware {
  late InactivityWatcher _watcher;

  @override
  void initState() {
    super.initState();
    _watcher = InactivityWatcher(
      timeout: widget.timeout,
      onTimeout: widget.onTimeout,
    );
    _watcher.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && widget.autoPauseOnNavigate) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    if (widget.autoPauseOnNavigate) {
      routeObserver.unsubscribe(this);
    }
    _watcher.dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    // başka sayfa açıldığında zamanlayıcıyı durdur
    if (widget.autoPauseOnNavigate) {
      _watcher.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _watcher.reset,
      onPanDown: (_) => _watcher.reset(),
      child: widget.child,
    );
  }
}