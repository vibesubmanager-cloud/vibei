/// Per-command end-to-end trace (Settings → Developer → Last attempt).
class TraceStep {
  TraceStep({
    required this.name,
    required this.ok,
    required this.detail,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String name;
  final bool ok;
  final String detail;
  final DateTime at;
}

class AttemptTrace {
  AttemptTrace();

  final List<TraceStep> steps = [];
  String rawPartial = '';
  String rawFinal = '';
  String normalized = '';
  String intent = '';
  String target = '';
  String phaseAtReceive = '';
  String flowTransition = '';
  bool navCalled = false;
  bool navVisible = false;
  String cameraPermission = '';
  bool cameraBound = false;
  int framesIn3s = 0;
  bool detectorStarted = false;

  void clear() {
    steps.clear();
    rawPartial = '';
    rawFinal = '';
    normalized = '';
    intent = '';
    target = '';
    phaseAtReceive = '';
    flowTransition = '';
    navCalled = false;
    navVisible = false;
    cameraPermission = '';
    cameraBound = false;
    framesIn3s = 0;
    detectorStarted = false;
  }

  void add(String name, bool ok, String detail) {
    steps.add(TraceStep(name: name, ok: ok, detail: detail));
  }
}
