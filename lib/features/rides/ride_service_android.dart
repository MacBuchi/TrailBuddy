import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../core/errors.dart';
import 'ride_service.dart';
import 'ride_task_handler.dart';

/// Der Einstiegspunkt des Service-Isolates.
@pragma('vm:entry-point')
void startRideService() => FlutterForegroundTask.setTaskHandler(RideTaskHandler());

void initRideCommunicationImpl() => FlutterForegroundTask.initCommunicationPort();

/// Der Manifest-Eintrag, unter dem das Symbol der Meldung steht. Das
/// Plugin sucht das Drawable NUR über diesen Namen; ein Tippfehler auf
/// einer Seite liefert stumm die Ressourcen-id 0 — und damit das
/// Launcher-Icon als weißen Klotz (PilzBuddy #331). Ein Test hält den
/// Namen hier und im Manifest zusammen.
const rideNotificationIconMetaData = 'de.mcbuchi.trailbuddy.RIDE_NOTIFICATION_ICON';

class _ForegroundRideService implements RideService {
  static const _serviceId = 2801;
  bool _initialized = false;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// `allowWakeLock`: Ohne ihn schläft die CPU zwischen den Takten, und
  /// die Fahrt bekäme ihre Messungen gebündelt beim nächsten Aufwachen.
  static ForegroundTaskOptions _options(Duration every) => ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(every.inMilliseconds),
        allowWakeLock: true,
        allowWifiLock: false,
      );

  void _initOnce(Duration every) {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ride_recording',
        channelName: 'Fahrt aufzeichnen',
        channelDescription: 'Läuft, solange eine Fahrt aufgezeichnet wird.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: _options(every),
    );
    _initialized = true;
  }

  @override
  Future<void> start({required String title, required String text, required Duration every}) async {
    if (!_supported) return;
    try {
      _initOnce(every);
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: title,
            notificationText: text,
            foregroundTaskOptions: _options(every));
        return;
      }
      // Ohne die Berechtigung läuft der Service trotzdem, nur ohne
      // sichtbare Meldung — ein abgelehnter Dialog ist kein Grund
      // abzubrechen.
      await FlutterForegroundTask.requestNotificationPermission();
      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        // `location`, nicht `dataSync`: Android 14 prüft je Typ, und ohne
        // ihn liefert der Dienst im Hintergrund keine Standorte mehr —
        // also genau dann nicht, wenn das Telefon in der Tasche steckt.
        serviceTypes: const [ForegroundServiceTypes.location],
        notificationIcon: const NotificationIcon(metaDataName: rideNotificationIconMetaData),
        notificationTitle: title,
        notificationText: text,
        callback: startRideService,
      );
    } catch (e, stackTrace) {
      logError('Fahrt: Foreground-Service starten', e, stackTrace);
    }
  }

  @override
  Future<void> stop() async {
    if (!_supported) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.stopService();
    } catch (e, stackTrace) {
      logError('Fahrt: Foreground-Service beenden', e, stackTrace);
    }
  }
}

RideService createRideService() => _ForegroundRideService();
