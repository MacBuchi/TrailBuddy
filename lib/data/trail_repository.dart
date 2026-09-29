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
  /// [eles] trägt eine Höhe je Punkt oder ist null (Patch 002).
  Future<String> contribute({
    required List<double> coords,
    List<double>? eles,
    required RecordingSource source,
    DateTime? recordedAt,
    required String clientId,
  });

  /// Trägt die Höhen einer EIGENEN Aufzeichnung ohne Höhen nach
  /// (`attach_elevation`, Patch 003). [coords] ist die gespeicherte Linie,
  /// wie der Client sie in der Originaldatei wiedergefunden hat; der
  /// Server prüft, dass sie es ist. false: Sie hatte schon Höhen.
  Future<bool> attachElevation({
    required String recordingId,
    required List<double> coords,
    required List<double> eles,
  });

  Future<void> saveDetails(TrailDetails details);

  /// Die Hinweise, die ich sehen darf (Patch 004): eigene und die von
  /// Buddys, deren Beitrag nicht privat ist.
  Future<List<TrailNote>> fetchNotes();

  /// Ein Hinweis zu einem Trail, den ich selbst belegt habe — sonst lehnt
  /// die RLS ab.
  Future<void> addNote({required String trailId, required String body});

  Future<void> deleteNote(String id);

  /// Zieht den EIGENEN Beitrag zu [trailId] zurück (Patch 010,
  /// `withdraw_contribution`): Aufzeichnungen, Hinweise und Beitrag in
  /// einer Transaktion. Der Trail bleibt, solange ein anderer ihn belegt.
  /// Gibt die Zahl der gelöschten Aufzeichnungen zurück.
  Future<int> withdraw(String trailId);
}

/// Die Spalten der Sicht `recordings_visible` — dieselbe Liste prüft
/// `tool/schema_check.sh` gegen das Schema.
const kRecordingColumns =
    'id, trail_id, user_id, source, recorded_at, reversed, quality, created_at, geojson, length_m, ele';

/// Der Embed heißt nach dem Fremdschlüssel; wird er in einem Patch
/// umbenannt, muss diese Zeile mitziehen (der Schema Check fällt sonst).
const kDetailsColumns =
    'trail_id, user_id, name, description, grade, traits, visibility, status, status_at, updated_at, '
    'contributor:profiles!trail_details_user_id_fkey(username)';

/// Wie [kDetailsColumns]: Der Embed heißt nach dem Fremdschlüssel, und
/// `tool/schema_check.sh` fragt genau diese Liste ab.
const kNoteColumns =
    'id, trail_id, user_id, body, created_at, '
    'author:profiles!trail_notes_user_id_fkey(username)';

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
    List<double>? eles,
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
        'eles': eles,
      });
      return result as String;
    } on PostgrestException catch (e) {
      if (e.code == '54000') throw const DailyLimitException();
      rethrow;
    }
  }

  @override
  Future<bool> attachElevation({
    required String recordingId,
    required List<double> coords,
    required List<double> eles,
  }) async {
    _client.requireUid;
    final result = await _client.rpc<dynamic>('attach_elevation', params: {
      'recording_id': recordingId,
      'coords': coords,
      'eles': eles,
    });
    return result as bool;
  }

  @override
  Future<void> saveDetails(TrailDetails details) async {
    final uid = _client.requireUid;
    final row = details.toRow()..['user_id'] = uid;
    await _client.from('trail_details').upsert(row);
  }

  @override
  Future<List<TrailNote>> fetchNotes() async {
    _client.requireUid;
    final rows = await _client.from('trail_notes').select(kNoteColumns);
    return [for (final r in rows) TrailNote.fromJson(r)];
  }

  @override
  Future<void> addNote({required String trailId, required String body}) async {
    final uid = _client.requireUid;
    await _client
        .from('trail_notes')
        .insert({'trail_id': trailId, 'user_id': uid, 'body': body});
  }

  @override
  Future<void> deleteNote(String id) async {
    _client.requireUid;
    await _client.from('trail_notes').delete().eq('id', id);
  }

  @override
  Future<int> withdraw(String trailId) async {
    _client.requireUid;
    final result = await _client
        .rpc<dynamic>('withdraw_contribution', params: {'trail_id': trailId});
    return (result as num).toInt();
  }
}
