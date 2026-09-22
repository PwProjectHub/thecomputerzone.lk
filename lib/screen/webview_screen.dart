import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/network_status_banner.dart';
import '../utils/notification_service.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isConnected = true;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  int _loadingProgress = 0;
  bool _isAtTop = true;
  double _pullOffset = 0.0;
  double _horizontalOffset = 0.0;
  bool _isDragging = false;
  bool _isHorizontalDragging = false;
  static const double _refreshThreshold = 80.0;
  static const double _swipeThreshold = 100.0;

  static const String _webPageUrl = 'https://thecomputerzone.lk/';

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
    _initializeWebView();

    Future.delayed(const Duration(seconds: 8), () {
      FlutterNativeSplash.remove();
    });
  }

  Future<void> _initializeConnectivity() async {
    final initialResult = await Connectivity().checkConnectivity();
    _updateConnectionStatus(initialResult);

    if (initialResult == ConnectivityResult.none) {
      FlutterNativeSplash.remove();
    }

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    final wasConnected = _isConnected;
    final isNowConnected = result != ConnectivityResult.none;

    if (mounted && wasConnected != isNowConnected) {
      setState(() {
        _isConnected = isNowConnected;
      });
      if (isNowConnected && !wasConnected) {
        _controller.reload();
      }
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1")
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress;
              });
            }
          },
          onPageStarted: (url) {
            FlutterNativeSplash.remove();
            if (mounted) {
              setState(() {
                _loadingProgress = 0;
                _isAtTop = true;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _loadingProgress = 100;
                _isAtTop = true;
              });
            }

            _controller.runJavaScript("""
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            document.getElementsByTagName('head')[0].appendChild(meta);
            document.body.style.zoom = "100%";
          """);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView Error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..setOnScrollPositionChange((change) {
        if (mounted) {
          final bool atTop = change.y <= 1.0;
          if (_isAtTop != atTop) {
            setState(() {
              _isAtTop = atTop;
            });
          }
        }
      });

    if (_isConnected) {
      _controller.loadRequest(Uri.parse(_webPageUrl));
    }
    _setUserCookies();
  }

  Future<void> _setUserCookies() async {
    final devId = await _getOrCreateDevId();
    final fcmToken = await NotificationService.getToken();
    final deviceModel = await _getDeviceModel();

    debugPrint('DEBUG: Current User Dev ID: $devId');
    debugPrint('DEBUG: Current FCM Token: $fcmToken');
    debugPrint('DEBUG: Device Model: $deviceModel');

    final cookieManager = WebViewCookieManager();


    await cookieManager.setCookie(
      WebViewCookie(
        name: 'pw_app_dev_id',
        value: devId,
        domain: 'thecomputerzone.lk',
        path: '/',
      ),
    );

    if (fcmToken != null) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: 'pw_app_fcm_token',
          value: fcmToken,
          domain: 'thecomputerzone.lk',
          path: '/',
        ),
      );
    }

    await cookieManager.setCookie(
      WebViewCookie(
        name: 'pw_app_device_model',
        value: deviceModel,
        domain: 'thecomputerzone.lk',
        path: '/',
      ),
    );
  }

  Future<String> _getDeviceModel() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model;
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.utsname.machine;
    }
    return 'Unknown Device';
  }

  Future<String> _getOrCreateDevId() async {
    final prefs = await SharedPreferences.getInstance();
    String? devId = prefs.getString('pw_app_dev_id');
    if (devId == null) {
      devId = _generateRandomId();
      await prefs.setString('pw_app_dev_id', devId);
    }
    return devId;
  }

  String _generateRandomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(16, (index) => chars[random.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    _updateConnectionStatus(connectivityResult);
  }

  Future<void> _handleRefresh() async {
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,
      ),
    );

    return PopScope(
      canPop: Platform.isIOS,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (Platform.isAndroid) {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: _isConnected
              ? Column(
            children: [
              if (_loadingProgress < 100)
                LinearProgressIndicator(
                  value: _loadingProgress / 100.0,
                  backgroundColor: Colors.white,
                  color: Colors.blue,
                  minHeight: 2,
                ),
              Expanded(
                child: Stack(
                  children: [
                    Listener(
                      onPointerDown: (event) {
                        _isDragging = true;
                        _isHorizontalDragging = false;
                        _pullOffset = 0;
                        _horizontalOffset = 0;
                      },
                      onPointerMove: (event) {
                        if (!_isDragging) return;


                        if (_isAtTop && event.delta.dy > 0 && !_isHorizontalDragging) {
                          setState(() {
                            _pullOffset = (_pullOffset + event.delta.dy)
                                .clamp(0.0, _refreshThreshold + 20);
                          });
                        }


                        if (event.position.dx > MediaQuery.of(context).size.width * 0.8 || _isHorizontalDragging) {
                          if (event.delta.dx < 0 && _pullOffset == 0) {
                            _isHorizontalDragging = true;
                            setState(() {
                              _horizontalOffset = (_horizontalOffset + event.delta.dx).clamp(-_swipeThreshold - 20, 0.0);
                            });
                          }
                        }
                      },
                      onPointerUp: (event) async {
                        if (_isDragging) {
                          if (_pullOffset >= _refreshThreshold) {
                            await _handleRefresh();
                          }

                          if (_horizontalOffset <= -_swipeThreshold) {
                            if (await _controller.canGoBack()) {
                              await _controller.goBack();
                            }
                          }

                          setState(() {
                            _isDragging = false;
                            _isHorizontalDragging = false;
                            _pullOffset = 0;
                            _horizontalOffset = 0;
                          });
                        }
                      },
                      onPointerCancel: (event) {
                        setState(() {
                          _isDragging = false;
                          _isHorizontalDragging = false;
                          _pullOffset = 0;
                          _horizontalOffset = 0;
                        });
                      },
                      child: WebViewWidget(
                        controller: _controller,
                      ),
                    ),
                    // Floating Refresh Indicator
                    if (_pullOffset > 5)
                      Positioned(
                        top: _pullOffset / 2,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: SizedBox(
                              width: 25,
                              height: 25,
                              child: CircularProgressIndicator(
                                value: (_pullOffset / _refreshThreshold)
                                    .clamp(0.0, 1.0),
                                strokeWidth: 2.5,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (_horizontalOffset < -5)
                      Positioned(
                        right: 10 + (_horizontalOffset.abs() / 4),
                        top: MediaQuery.of(context).size.height / 2 - 30,
                        child: Opacity(
                          opacity: (_horizontalOffset.abs() / _swipeThreshold).clamp(0.0, 1.0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          )
              : Center(
            child: NetworkStatusBanner(
              isConnected: _isConnected,
              onRetry: _retry,
            ),
          ),
        ),
      ),
    );
  }
}