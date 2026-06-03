/// Guarda em memória quais torneios o usuário já validou o código de votação.
/// Reseta ao fechar o app (comportamento intencional — o código é por sessão).
class VoteSession {
  VoteSession._();
  static final VoteSession instance = VoteSession._();

  final Set<String> _validatedTournaments = {};

  bool isValidated(String tournamentId) =>
      _validatedTournaments.contains(tournamentId);

  void validate(String tournamentId) =>
      _validatedTournaments.add(tournamentId);
}
