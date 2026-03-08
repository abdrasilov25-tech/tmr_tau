import '../entities/category_entity.dart';

abstract class CategoriesRepository {
  /// Основные категории (parent_id is null).
  Future<List<CategoryEntity>> getMainCategories();
  /// Подкатегории по id основной категории.
  Future<List<CategoryEntity>> getSubcategories(String parentCategoryId);
  /// Категория по id (для подстановки при редактировании).
  Future<CategoryEntity?> getCategoryById(String id);
}
