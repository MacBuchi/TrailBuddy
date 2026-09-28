import 'ride_service.dart';

/// Web: kein Prozess, den man wachhalten könnte, kein Service-Isolate.
/// Die Aufzeichnung gibt es dort nicht (`rideRecordingAvailable`).
class _NoRideService implements RideService {
  const _NoRideService();

  @override
  Future<void> start({required String title, required String text, required Duration every}) async {}

  @override
  Future<void> stop() async {}
}

RideService createRideService() => const _NoRideService();

void initRideCommunicationImpl() {}
