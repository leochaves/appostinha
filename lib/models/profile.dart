class Profile {
  final String id;
  final String username;

  Profile({required this.id, required this.username});

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String? ?? 'Usuário',
      );
}
