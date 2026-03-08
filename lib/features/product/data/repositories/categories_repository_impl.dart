import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/categories_repository.dart';

class CategoriesRepositoryImpl implements CategoriesRepository {
  CategoriesRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<CategoryEntity>> getMainCategories() async {
    final res = await _client
        .from(SupabaseConstants.categoriesTable)
        .select('id, name, parent_id')
        .isFilter('parent_id', null)
        .order('name');
    return (res as List).map(_map).toList();
  }

  @override
  Future<List<CategoryEntity>> getSubcategories(String parentCategoryId) async {
    final res = await _client
        .from(SupabaseConstants.categoriesTable)
        .select('id, name, parent_id')
        .eq('parent_id', parentCategoryId)
        .order('name');
    return (res as List).map(_map).toList();
  }

  @override
  Future<CategoryEntity?> getCategoryById(String id) async {
    final res = await _client
        .from(SupabaseConstants.categoriesTable)
        .select('id, name, parent_id')
        .eq('id', id)
        .maybeSingle();
    if (res == null) return null;
    return _map(res);
  }

  CategoryEntity _map(dynamic e) {
    final m = Map<String, dynamic>.from(e as Map);
    return CategoryEntity(
      id: m['id'] as String,
      name: m['name'] as String,
      parentId: m['parent_id'] as String?,
    );
  }
}
