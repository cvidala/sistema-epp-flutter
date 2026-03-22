class AsistenciaPendiente {
  final String id;
  final String rut;
  final String tipo;
  final String fotoLocalPath;
  final String fotoHash;
  final double? gpsLat;
  final double? gpsLng;
  final double? gpsAccuracy;
  final String? deviceModel;
  final String capturedAt; // ISO 8601 UTC
  String status; // 'pendiente' | 'subiendo' | 'enviada' | 'fallida'
  int intentos;
  String? ultimoError;

  AsistenciaPendiente({
    required this.id,
    required this.rut,
    required this.tipo,
    required this.fotoLocalPath,
    required this.fotoHash,
    this.gpsLat,
    this.gpsLng,
    this.gpsAccuracy,
    this.deviceModel,
    required this.capturedAt,
    this.status = 'pendiente',
    this.intentos = 0,
    this.ultimoError,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'rut': rut,
        'tipo': tipo,
        'fotoLocalPath': fotoLocalPath,
        'fotoHash': fotoHash,
        'gpsLat': gpsLat,
        'gpsLng': gpsLng,
        'gpsAccuracy': gpsAccuracy,
        'deviceModel': deviceModel,
        'capturedAt': capturedAt,
        'status': status,
        'intentos': intentos,
        'ultimoError': ultimoError,
      };

  factory AsistenciaPendiente.fromMap(Map<dynamic, dynamic> map) =>
      AsistenciaPendiente(
        id: map['id'] as String,
        rut: map['rut'] as String,
        tipo: map['tipo'] as String? ?? 'Entrada',
        fotoLocalPath: map['fotoLocalPath'] as String,
        fotoHash: map['fotoHash'] as String,
        gpsLat: (map['gpsLat'] as num?)?.toDouble(),
        gpsLng: (map['gpsLng'] as num?)?.toDouble(),
        gpsAccuracy: (map['gpsAccuracy'] as num?)?.toDouble(),
        deviceModel: map['deviceModel'] as String?,
        capturedAt: map['capturedAt'] as String,
        status: map['status'] as String? ?? 'pendiente',
        intentos: map['intentos'] as int? ?? 0,
        ultimoError: map['ultimoError'] as String?,
      );
}
