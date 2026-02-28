class EvaluacionEntrega {
  final String estado; // OK | WARNING | BLOQUEO
  final Map<String, dynamic> detalle;

  EvaluacionEntrega({
    required this.estado,
    required this.detalle,
  });

  factory EvaluacionEntrega.fromJson(Map<String, dynamic> json) {
    return EvaluacionEntrega(
      estado: json['estado'],
      detalle: json['detalle'] ?? {},
    );
  }
}
