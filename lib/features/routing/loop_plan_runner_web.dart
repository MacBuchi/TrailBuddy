// Im Browser gibt es keine Isolate: Der Planer rechnet an Ort und Stelle.
import 'loop_plan_runner.dart';

LoopPlanRunner createLoopPlanRunner() => InlineLoopPlanRunner();
