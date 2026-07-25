/// Formatages partagés par le lecteur, les cartes de clip et le Studio.
library;

/// Formate un entier en notation compacte française (« 128 k », « 18,2 k »,
/// « 2,4 M »). En dessous de 1000, la valeur exacte est renvoyée.
String formatCompactCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) return '${_roundedUnit(value / 1000)} k';
  return '${_roundedUnit(value / 1000000)} M';
}

String _roundedUnit(double value) {
  if (value < 10) return value.toStringAsFixed(1).replaceAll('.', ',');
  return value.round().toString();
}

/// Formate un nombre en séparant les milliers par une espace insécable
/// (« 2 419 588 »), comme le veut la typographie française.
String formatGroupedCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Date relative en français, avec les paliers usuels d'une plateforme vidéo.
String relativeDate(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  if (diff.inDays < 30) return 'il y a ${(diff.inDays / 7).floor()} sem.';
  if (diff.inDays < 365) return 'il y a ${(diff.inDays / 30).floor()} mois';
  final years = (diff.inDays / 365).floor();
  return 'il y a $years an${years > 1 ? 's' : ''}';
}
