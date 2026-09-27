import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors.dart';
import '../features/trails/trail_geometry.dart';
import '../models/trail.dart';
import 'session.dart';

/// Die Naht zur Datenbank für Trails (Konzept 3 und 4). Zwei Abfragen
/// und eine RPC; gruppiert wird im Client (`buildTrails`). Abstrakt,
/// damit die Tests ein Fake einhängen, das die RLS-Regeln spiegelt.
abstract class TrailRepository {
  Future<List<TrailRecording>> fetchRecordings();
  Future<List<TrailDetails>> fetchDetails();

  /// Steuert eine Aufzeichnung bei und gibt die Trail-Kennung zurück —
  /// die eines bestehenden Trails, wenn der Abgleich „gleich" sagt, sonst
  /// eine neue. Ob sie neu ist, sagt der Server bewusst nicht (4.6).
  Future<String> contribute({
    required List<double> coords,
    required RecordingSource source,
    DateTime? recordedAt,
    required String clientId,
  });

  Future<void> saveDetails(TrailDetails details);
}

/// Die Spalten der Sicht `recordings_visible` — dieselbe Liste prüft
/// `tool/schema_check.sh` gegen das Schema.
const kRecordingColumns =
    'id, trail_id, user_id, source, recorded_at, reversed, quality, created_at, geojson, length_m';

/// Der Embed heißt nach dem Fremdschlüssel; wird er in einem Patch
/// umbenannt, muss diese Zeile mitziehen (der Schema Check fällt sonst).
const kDetailsColumns =
    'trail_id, user_id, name, description, grade, kind, visibility, status, status_at, updated_at, '
    'contributor:profiles!trail_details_user_id_fkey(username)';

class SupabaseTrailRepository implements TrailRepository {
  SupabaseTrailRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<TrailRecording>> fetchRecordings() async {
    _client.requireUid;
    final rows = await _client.from('recordings_visible').select(kRecordingColumns);
    return [for (final r in rows) TrailRecording.fromJson(r)];
  }

  @override
  Future<List<TrailDetails>> fetchDetails() async {
    _client.requireUid;
    final rows = await _client.from('trail_details').select(kDetailsColumns);
    return [for (final r in rows) TrailDetails.fromJson(r)];
  }

  @override
  Future<String> contribute({
    required List<double> coords,
    required RecordingSource source,
    DateTime? recordedAt,
    required String clientId,
  }) async {
    _client.requireUid;
    try {
      final result = await _client.rpc<dynamic>('contribute_recording', params: {
        'coords': coords,
        'source': source.name,
        'recorded_at': recordedAt?.toUtc().toIso8601String(),
        'client_id': clientId,
      });
      return result as String;
    } on PostgrestException catch (e) {
      if (e.code == '54000') throw const DailyLimitException();
      rethrow;
    }
  }

  @override
  Future<void> saveDetails(TrailDetails details) async {
    final uid = _client.requireUid;
    final row = details.toRow()..['user_id'] = uid;
    await _client.from('trail_details').upsert(row);
  }
}
