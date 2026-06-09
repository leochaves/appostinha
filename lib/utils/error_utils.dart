/// Converte erros técnicos do Supabase/rede em mensagens amigáveis.
String friendlyError(Object e) {
  final raw = e.toString().toLowerCase();

  if (raw.contains('querying schema') || raw.contains('database error')) {
    return 'Erro de servidor. Tente novamente em instantes.';
  }
  if (raw.contains('network') || raw.contains('connection') || raw.contains('socketexception')) {
    return 'Sem conexão. Verifique sua internet.';
  }
  if (raw.contains('permission denied') || raw.contains('rls')) {
    return 'Você não tem permissão para esta ação.';
  }
  if (raw.contains('jwt expired') || raw.contains('session')) {
    return 'Sessão expirada. Faça login novamente.';
  }
  if (raw.contains('duplicate') || raw.contains('unique')) {
    return 'Registro duplicado.';
  }
  // tira o prefixo "exception:" e mostra o resto
  final cleaned = e.toString()
      .replaceAll(RegExp(r'^\w*[Ee]xception:\s*'), '')
      .replaceAll(RegExp(r'\{.*\}'), '') // remove JSON cru
      .trim();
  return cleaned.isEmpty ? 'Erro desconhecido.' : cleaned;
}
