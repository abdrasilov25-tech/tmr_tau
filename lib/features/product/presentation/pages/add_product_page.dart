import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:postgrest/postgrest.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/categories_repository.dart';
import '../../domain/repositories/product_repository.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cityController = TextEditingController();
  bool _loading = false;
  bool _gettingLocation = false;
  File? _image;
  List<CategoryEntity> _mainCategories = [];
  List<CategoryEntity> _subcategories = [];
  CategoryEntity? _selectedMain;
  CategoryEntity? _selectedSubcategory;
  bool _categoriesLoading = true;
  String _condition = 'any';
  bool _isUrgent = false;
  bool _isTop = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await context
          .read<CategoriesRepository>()
          .getMainCategories();
      if (mounted) {
        setState(() {
          _mainCategories = list;
          _categoriesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _categoriesLoading = false);
    }
  }

  Future<void> _onMainCategorySelected(CategoryEntity? main) async {
    setState(() {
      _selectedMain = main;
      _selectedSubcategory = null;
      _subcategories = [];
    });
    if (main == null) return;
    try {
      final list = await context.read<CategoriesRepository>().getSubcategories(
        main.id,
      );
      if (mounted) setState(() => _subcategories = list);
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _pickCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Включите геолокацию на устройстве')),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к геолокации')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось получить геолокацию')),
      );
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Войдите в аккаунт')));
      return;
    }

    final price = double.tryParse(
      _priceController.text.replaceAll(' ', '').replaceAll(',', '.'),
    );
    if (price == null || price < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите корректную цену')));
      return;
    }

    setState(() => _loading = true);
    final productRepository = context.read<ProductRepository>();
    try {
      String imageUrl = '';
      if (_image != null) {
        const uuid = Uuid();
        final ext = _image!.path.split('.').last;
        final path = '${uuid.v4()}.$ext';
        await Supabase.instance.client.storage
            .from(SupabaseConstants.bucketProducts)
            .upload(
              path,
              _image!,
              fileOptions: const FileOptions(upsert: true),
            );
        imageUrl = Supabase.instance.client.storage
            .from(SupabaseConstants.bucketProducts)
            .getPublicUrl(path);
      }
      await productRepository.addProduct(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: price,
        imageUrl: imageUrl,
        category: _selectedSubcategory?.name ?? 'general',
        categoryId: _selectedSubcategory?.id,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        condition: _condition,
        isUrgent: _isUrgent,
        isTop: _isTop,
        latitude: _latitude,
        longitude: _longitude,
        sellerId: authState.user.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Товар добавлен')));
      context.go('/home/feed');
    } catch (e, st) {
      if (!mounted) return;
      String message = 'Ошибка при публикации';
      if (e is StorageException) {
        message =
            'Storage: создайте бакет «products» в Supabase и добавьте политики загрузки (см. docs/SUPABASE_SETUP.md)';
      } else if (e is PostgrestException) {
        message =
            'База данных: проверьте таблицу products и выполните schema.sql в Supabase';
      } else {
        message = 'Ошибка: $e';
      }
      debugPrint('AddProduct error: $e $st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Добавить товар'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/home/feed'),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final x = await picker.pickImage(source: ImageSource.gallery);
                if (x != null && mounted) setState(() => _image = File(x.path));
              },
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _image != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _image!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Добавить фото',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
            if (_categoriesLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              DropdownButtonFormField<CategoryEntity>(
                initialValue: _selectedMain,
                decoration: const InputDecoration(labelText: 'Категория'),
                items: [
                  const DropdownMenuItem<CategoryEntity>(
                    value: null,
                    child: Text('— Выберите категорию —'),
                  ),
                  ..._mainCategories.map(
                    (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                  ),
                ],
                onChanged: (v) => _onMainCategorySelected(v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CategoryEntity>(
                initialValue: _selectedSubcategory,
                decoration: const InputDecoration(labelText: 'Подкатегория'),
                items: [
                  const DropdownMenuItem<CategoryEntity>(
                    value: null,
                    child: Text('— Выберите подкатегорию —'),
                  ),
                  ..._subcategories.map(
                    (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                  ),
                ],
                onChanged: _selectedMain == null
                    ? null
                    : (v) => setState(() => _selectedSubcategory = v),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Краткое название товара',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Введите название' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Цена (₸)',
                hintText: '0',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Введите цену';
                if (double.tryParse(v.replaceAll(' ', '')) == null) {
                  return 'Некорректная цена';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityController,
              decoration: const InputDecoration(
                labelText: 'Город',
                hintText: 'Например, Алматы',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _condition,
              decoration: const InputDecoration(labelText: 'Состояние'),
              items: const [
                DropdownMenuItem(value: 'any', child: Text('Любое')),
                DropdownMenuItem(value: 'new', child: Text('Новый')),
                DropdownMenuItem(value: 'used', child: Text('Б/у')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _condition = v);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Срочное объявление'),
              value: _isUrgent,
              onChanged: (v) => setState(() => _isUrgent = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Поднять в ТОП'),
              value: _isTop,
              onChanged: (v) => setState(() => _isTop = v),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _gettingLocation ? null : _pickCurrentLocation,
              icon: _gettingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: Text(
                _latitude == null || _longitude == null
                    ? 'Добавить мою геолокацию'
                    : 'Геолокация добавлена',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Описание',
                hintText: 'Необязательно',
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Опубликовать'),
            ),
          ],
        ),
      ),
    );
  }
}
