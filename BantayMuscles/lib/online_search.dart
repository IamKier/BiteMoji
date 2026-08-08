// Online food search via Open Food Facts.
//
// Free, no API key, no server — the app calls it directly. Covers packaged
// grocery products (including Philippine brands); it does NOT carry restaurant
// menu items, so Jollibee/KFC-style foods still need the bundled catalog.
//
// Data is licensed ODbL. Values are per 100 g, which is why every result is
// returned with a "100 g" serving — the serving stepper scales from there.
//
// Direct port of the Expo app's online-search.ts.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/nutrition.dart';

const _endpoint = 'https://search.openfoodfacts.org/search';

// Open Food Facts requires a descriptive User-Agent and blocks generic ones.
const _userAgent = 'BiteMoji/1.0 (https://github.com/IamKier/BiteMoji)';

const _timeout = Duration(seconds: 12);

/// Result of an online search — either the foods, or a user-facing error.
class OnlineSearchResult {
  final bool ok;
  final List<Food> foods;
  final String? error;
  const OnlineSearchResult.success(this.foods)
      : ok = true,
        error = null;
  const OnlineSearchResult.failure(this.error)
      : ok = false,
        foods = const [];
}

int _round(num? v) => (v == null || v.isNaN || v.isInfinite) ? 0 : v.round();

String _brandOf(dynamic brands) {
  if (brands is List) return brands.isEmpty ? '' : (brands.first?.toString() ?? '');
  return brands?.toString() ?? '';
}

/// True when a food came from Open Food Facts (id prefixed `off:`), so the UI
/// can badge it.
bool isOnlineFood(Food food) => food.id.startsWith('off:');

Future<dynamic> _fetchJson(Uri url) async {
  final res = await http
      .get(url, headers: {'User-Agent': _userAgent, 'Accept': 'application/json'})
      .timeout(_timeout);
  if (res.statusCode != 200) throw Exception('${res.statusCode}');
  return jsonDecode(res.body);
}

Future<OnlineSearchResult> searchOnline(String query) async {
  final q = query.trim();
  if (q.length < 2) return const OnlineSearchResult.success([]);

  final url = Uri.parse(
    '$_endpoint?q=${Uri.encodeQueryComponent(q)}&page_size=25'
    '&fields=code,product_name,brands,nutriments',
  );

  dynamic payload;
  try {
    payload = await _fetchJson(url);
  } catch (_) {
    return const OnlineSearchResult.failure(
        'Couldn’t reach the food database. Check your connection and try again.');
  }

  final hits = (payload is Map ? payload['hits'] : null);
  if (hits is! List) return const OnlineSearchResult.success([]);

  final seen = <String>{};
  final foods = <Food>[];

  for (final hit in hits) {
    if (hit is! Map) continue;
    final name = (hit['product_name'] as String?)?.trim();
    final nutriments = hit['nutriments'];
    final calories = nutriments is Map ? nutriments['energy-kcal_100g'] as num? : null;

    // Plenty of entries have no nutrition data — skipping them beats logging a
    // food as 0 kcal.
    if (name == null || name.isEmpty || calories == null) continue;

    final brand = _brandOf(hit['brands']).trim();
    final label = brand.isNotEmpty && !name.toLowerCase().contains(brand.toLowerCase())
        ? '$name ($brand)'
        : name;

    final key = label.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);

    foods.add(Food(
      id: 'off:${hit['code'] ?? key}',
      name: label,
      serving: '100 g',
      calories: _round(calories),
      protein: _round(nutriments is Map ? nutriments['proteins_100g'] as num? : null),
      carbs: _round(nutriments is Map ? nutriments['carbohydrates_100g'] as num? : null),
      fat: _round(nutriments is Map ? nutriments['fat_100g'] as num? : null),
    ));
  }

  return OnlineSearchResult.success(foods);
}

/// Result of a barcode lookup — the resolved food, or a user-facing error.
class BarcodeResult {
  final bool ok;
  final Food? food;
  final String? error;
  const BarcodeResult.success(this.food)
      : ok = true,
        error = null;
  const BarcodeResult.failure(this.error)
      : ok = false,
        food = null;
}

/// Looks up a single product by its barcode (EAN/UPC) via Open Food Facts.
Future<BarcodeResult> lookupBarcode(String code) async {
  final url = Uri.parse(
    'https://world.openfoodfacts.org/api/v2/product/${Uri.encodeComponent(code)}'
    '?fields=product_name,brands,nutriments',
  );

  dynamic payload;
  try {
    payload = await _fetchJson(url);
  } catch (_) {
    return const BarcodeResult.failure(
        'Couldn’t reach the food database. Check your connection.');
  }

  final product = payload is Map ? payload['product'] : null;
  final nutriments = product is Map ? product['nutriments'] : null;
  final calories = nutriments is Map ? nutriments['energy-kcal_100g'] as num? : null;
  final name = product is Map ? (product['product_name'] as String?)?.trim() : null;

  if ((payload is Map ? payload['status'] : null) != 1 ||
      name == null ||
      name.isEmpty ||
      calories == null) {
    return const BarcodeResult.failure(
        'That barcode isn’t in the database, or has no nutrition data. Try Quick add.');
  }

  final brand = _brandOf(product['brands']).trim();
  final label = brand.isNotEmpty && !name.toLowerCase().contains(brand.toLowerCase())
      ? '$name ($brand)'
      : name;

  return BarcodeResult.success(Food(
    id: 'off:$code',
    name: label,
    serving: '100 g',
    calories: _round(calories),
    protein: _round(nutriments is Map ? nutriments['proteins_100g'] as num? : null),
    carbs: _round(nutriments is Map ? nutriments['carbohydrates_100g'] as num? : null),
    fat: _round(nutriments is Map ? nutriments['fat_100g'] as num? : null),
  ));
}
