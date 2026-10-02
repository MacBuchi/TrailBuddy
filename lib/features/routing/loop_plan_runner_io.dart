// Der Rechen-Isolate des Planers (#188) — Begründung und Regeln in
// `loop_plan_runner.dart`. Ein Isolate je Runner, angelegt bei der ersten
// Rechnung; der Graph geht einmal hinüber, danach nur noch Anfragen.
import 'dart:async';
import 'dart:isolate';

import 'loop_plan_runner.dart';
import 'loop_planner.dart';
import 'road_graph.dart';

LoopPlanRunner createLoopPlanRunner() => IsolateLoopPlanRunner();

class IsolateLoopPlanRunner implements LoopPlanRunner {
  Future<SendPort>? _worker;
  Completer<SendPort>? _ready;
  Isolate? _isolate;
  final _ports = <ReceivePort>[];
  RoadGraph? _sentGraph;
  var _nextId = 0;
  final _pending = <int, Completer<LoopPlan>>{};

  /// Wie oft ein Graph hinüberging — für den Test („nur einmal je Graph").
  int graphSends = 0;

  @override
  Future<LoopPlan> plan(RoadGraph graph, LoopRequest request) async {
    final spawn = _worker ??= _spawn();
    final worker = await spawn;
    // Zwischen Start und hier freigegeben: Der Isolate ist weg, eine
    // Anfrage an ihn bekäme nie eine Antwort.
    if (!identical(spawn, _worker)) throw StateError('Planer geschlossen');
    if (!identical(graph, _sentGraph)) {
      // Kopiert den Graphen — hier im UI-Isolate, deshalb nur einmal.
      worker.send(graph);
      _sentGraph = graph;
      graphSends++;
    }
    final id = _nextId++;
    final done = Completer<LoopPlan>();
    _pending[id] = done;
    worker.send((id, request));
    return done.future;
  }

  Future<SendPort> _spawn() {
    final ready = _ready = Completer<SendPort>();
    final inbox = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
    _ports.addAll([inbox, errors, exits]);
    inbox.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      final (id, plan, error, stack) = msg as (int, LoopPlan?, String?, String?);
      final done = _pending.remove(id);
      if (done == null) return;
      if (plan != null) {
        done.complete(plan);
      } else {
        done.completeError(RemoteError(error ?? 'unbekannt', stack ?? ''));
      }
    });
    // Ein Fehler außerhalb einer Rechnung oder das Ende des Isolates:
    // Was wartet, scheitert, und die nächste Rechnung legt neu an.
    errors.listen((e) {
      final parts = e as List<Object?>;
      _reset(RemoteError('${parts.first}', '${parts.last}'));
    });
    exits.listen((_) => _reset(StateError('Rechen-Isolate beendet')));
    Isolate.spawn(_workerMain, inbox.sendPort, onError: errors.sendPort, onExit: exits.sendPort).then(
      (isolate) {
        // Schon freigegeben, während er startete: gleich wieder weg.
        if (!identical(_ready, ready)) {
          isolate.kill(priority: Isolate.immediate);
          return;
        }
        _isolate = isolate;
      },
      onError: (Object e, StackTrace s) {
        if (identical(_ready, ready)) _reset(e);
      },
    );
    return ready.future;
  }

  void _reset(Object error) {
    // Auch ein Start, der noch läuft, scheitert — sonst wartete die
    // Rechnung, die ihn ausgelöst hat, für immer.
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    for (final p in _ports) {
      p.close();
    }
    _ports.clear();
    _worker = null;
    _sentGraph = null;
    final waiting = [..._pending.values];
    _pending.clear();
    for (final c in waiting) {
      c.completeError(error);
    }
  }

  @override
  void dispose() => _reset(StateError('Planer geschlossen'));
}

void _workerMain(SendPort reply) {
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  RoadGraph? graph;
  inbox.listen((msg) {
    if (msg is RoadGraph) {
      graph = msg;
      return;
    }
    final (id, request) = msg as (int, LoopRequest);
    try {
      reply.send((id, request.planOn(graph!), null, null));
    } catch (e, s) {
      reply.send((id, null, '$e', '$s'));
    }
  });
}
