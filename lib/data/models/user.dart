class User {
  final int id;
  final String email;
  final String? username;
  final String? avatar;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.email,
    this.username,
    this.avatar,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String?,
      avatar: json['avatar'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'avatar': avatar,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  String get displayName => username ?? email.split('@').first;
}
