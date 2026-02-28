import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/evaluacion_entrega.dart';

class EntregaService {
  final supabase = Supabase.instance.client;

  Future<EvaluacionEntrega> evaluarEntrega({
    required String trabajadorId,
    required String obraId,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await supabase.rpc(
      'evaluar_entrega_v2',
      params: {
        'p_trabajador_id': trabajadorId,
        'p_obra_id': obraId,
        'p_items': items,
      },
    );

    return EvaluacionEntrega.fromJson(response);
  }
}
