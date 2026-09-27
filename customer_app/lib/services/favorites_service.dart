import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FavoritesService {
  static const String _favoritesKey = 'favorites';

  // Get favorite shop IDs
  Future<List<int>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_favoritesKey);
    if (favoritesJson == null) return [];
    try {
      final List<dynamic> favorites = jsonDecode(favoritesJson);
      return favorites.cast<int>();
    } catch (e) {
      return [];
    }
  }

  // Add favorite
  Future<void> addFavorite(int shopId) async {
    final favorites = await getFavorites();
    if (!favorites.contains(shopId)) {
      favorites.add(shopId);
      await _saveFavorites(favorites);
    }
  }

  // Remove favorite
  Future<void> removeFavorite(int shopId) async {
    final favorites = await getFavorites();
    favorites.remove(shopId);
    await _saveFavorites(favorites);
  }

  // Toggle favorite
  Future<bool> toggleFavorite(int shopId) async {
    final favorites = await getFavorites();
    if (favorites.contains(shopId)) {
      await removeFavorite(shopId);
      return false;
    } else {
      await addFavorite(shopId);
      return true;
    }
  }

  // Check if favorite
  Future<bool> isFavorite(int shopId) async {
    final favorites = await getFavorites();
    return favorites.contains(shopId);
  }

  // Save favorites
  Future<void> _saveFavorites(List<int> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_favoritesKey, jsonEncode(favorites));
  }
}
