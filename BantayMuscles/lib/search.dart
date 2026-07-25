// Food search ranking. Pure Dart, no Flutter imports, so it's unit-testable
// and independent of where the catalog comes from (bundled or remote).
//
// The old search was a plain case-insensitive substring match on the name, in
// catalog order. That missed accented spellings, multi-word queries in any
// order, and typos, and never ranked the closest match first. This replaces it
// with a scored, token-based match.

import 'models/nutrition.dart';

const Map<String, String> _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c',
};

final _alnum = RegExp(r'[a-z0-9]');
final _spaces = RegExp(r'\s+');

/// Fold text to a search-normal form: lowercased, accents stripped, every
/// non-alphanumeric run collapsed to a single space, trimmed. So "Piñakbet",
/// "pinakbet" and "PINAKBET" all normalise to the same token.
String normalizeForSearch(String input) {
  final buffer = StringBuffer();
  for (final ch in input.toLowerCase().split('')) {
    final mapped = _accents[ch] ?? ch;
    buffer.write(_alnum.hasMatch(mapped) ? mapped : ' ');
  }
  return buffer.toString().trim().replaceAll(_spaces, ' ');
}

/// Ranked catalog search. Returns the foods whose name matches *every* query
/// token — order-independent, and typo-tolerant for tokens of 4+ characters —
/// with the strongest matches first. An empty query returns [foods] unchanged.
///
/// Scoring, per food: an exact name match, then a name that starts with the
/// whole query, rank highest; then per token, an exact word beats a word
/// prefix beats a substring beats a near (edit-distance-1) match. Ties fall
/// back to the food's original catalog position, so ordering stays stable.
List<Food> searchFoods(List<Food> foods, String query) {
  final normQuery = normalizeForSearch(query);
  if (normQuery.isEmpty) return foods;
  final tokens = normQuery.split(' ');

  final scored = <_Scored>[];
  for (var i = 0; i < foods.length; i++) {
    final name = normalizeForSearch(foods[i].name);
    final words = name.split(' ');

    var score = 0;
    var matchedAll = true;
    for (final token in tokens) {
      final tokenScore = _scoreToken(token, name, words);
      if (tokenScore == 0) {
        matchedAll = false;
        break;
      }
      score += tokenScore;
    }
    if (!matchedAll) continue;

    // Whole-query bonuses reward a tight overall match, not just token hits.
    if (name == normQuery) {
      score += 1000;
    } else if (name.startsWith(normQuery)) {
      score += 200;
    } else if (name.contains(normQuery)) {
      score += 50;
    }

    scored.add(_Scored(foods[i], i, score));
  }

  scored.sort((a, b) =>
      a.score != b.score ? b.score.compareTo(a.score) : a.index.compareTo(b.index));
  return [for (final s in scored) s.food];
}

int _scoreToken(String token, String name, List<String> words) {
  for (final w in words) {
    if (w == token) return 100; // whole word
  }
  for (final w in words) {
    if (w.startsWith(token)) return 60; // word prefix — "chick" → "chicken"
  }
  if (name.contains(token)) return 25; // substring anywhere
  if (token.length >= 4) {
    for (final w in words) {
      if (_within1(w, token)) return 15; // one typo — "chiken" → "chicken"
    }
  }
  return 0;
}

/// True when [a] and [b] are within Levenshtein distance 1 (one insertion,
/// deletion, or substitution). Bounded and allocation-free.
bool _within1(String a, String b) {
  final la = a.length, lb = b.length;
  if ((la - lb).abs() > 1) return false;

  // Walk both, allowing a single divergence.
  final longer = la >= lb ? a : b;
  final shorter = la >= lb ? b : a;
  var i = 0, j = 0;
  var edited = false;
  while (i < longer.length && j < shorter.length) {
    if (longer[i] == shorter[j]) {
      i++;
      j++;
      continue;
    }
    if (edited) return false;
    edited = true;
    if (longer.length == shorter.length) {
      i++; // substitution
      j++;
    } else {
      i++; // deletion from the longer string
    }
  }
  return true; // any leftover tail is at most one char
}

class _Scored {
  final Food food;
  final int index;
  final int score;
  const _Scored(this.food, this.index, this.score);
}
