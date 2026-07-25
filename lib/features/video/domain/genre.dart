/// Genre musical, miroir de la table `genres` (données de référence).
class Genre {
  const Genre({required this.id, required this.name, required this.slug});

  final int id;
  final String name;
  final String slug;

  /// Construit un [Genre] depuis une ligne JSON de Supabase.
  ///
  /// Lève [FormatException] si `id`, `name` ou `slug` sont absents ou d'un
  /// type invalide.
  factory Genre.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final slug = json['slug'];
    if (id is! int) {
      throw const FormatException('Genre.fromJson : champ "id" invalide.');
    }
    if (name is! String || name.isEmpty) {
      throw const FormatException('Genre.fromJson : champ "name" invalide.');
    }
    if (slug is! String || slug.isEmpty) {
      throw const FormatException('Genre.fromJson : champ "slug" invalide.');
    }
    return Genre(id: id, name: name, slug: slug);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'slug': slug};

  @override
  bool operator ==(Object other) =>
      other is Genre &&
      other.id == id &&
      other.name == name &&
      other.slug == slug;

  @override
  int get hashCode => Object.hash(id, name, slug);
}
