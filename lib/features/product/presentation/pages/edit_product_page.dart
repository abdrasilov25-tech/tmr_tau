import 'dart:async';
import 'dart:io';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/categories_repository.dart';
import '../../domain/repositories/product_repository.dart';

class EditProductPage extends StatefulWidget {
  const EditProductPage({
    super.key,
    required this.productId,
    required this.product,
  });

  final String productId;
  final ProductEntity product;

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _cityController;
  bool _loading = false;
  bool _gettingLocation = false;
  File? _image;
  List<CategoryEntity> _mainCategories = [];
  List<CategoryEntity> _subcategories = [];
  CategoryEntity? _selectedMain;
  CategoryEntity? _selectedSubcategory;
  bool _categoriesLoading = true;
  late String _condition;
  late bool _isUrgent;
  late bool _isTop;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _titleController = TextEditingController(text: p.title);
    _priceController = TextEditingController(text: p.price.toStringAsFixed(0));
    _descriptionController = TextEditingController(text: p.description);
    _cityController = TextEditingController(text: p.city ?? '');
    _condition = p.condition;
    _isUrgent = p.isUrgent;
    _isTop = p.isTop;
    _latitude = p.latitude;
    _longitude = p.longitude;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
  }

  Future<void> _loadCategories() async {
    try {
      final repo = context.read<CategoriesRepository>();
      final mainList = await repo.getMainCategories();
      CategoryEntity? main;
      List<CategoryEntity> subs = [];
      CategoryEntity? sub;
      if (widget.product.categoryId != null) {
        final cat = await repo.getCategoryById(widget.product.categoryId!);
        if (cat != null && cat.parentId != null) {
          for (final m in mainList) {
            if (m.id == cat.parentId) {
              main = m;
              break;
            }
          }
          if (main != null) {
            subs = await repo.getSubcategories(main.id);
            for (final s in subs) {
              if (s.id == widget.product.categoryId) {
                sub = s;
                break;
              }
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _mainCategories = mainList;
          _selectedMain = main;
          _subcategories = subs;
          _selectedSubcategory = sub;
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
          SnackBar(
            content: const Text(
              'Геолокация выключена. Включите службы геолокации',
            ),
            action: SnackBarAction(
              label: 'Настройки',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
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
          SnackBar(
            content: const Text('Нет доступа к геолокации для приложения'),
            action: SnackBarAction(
              label: 'Открыть',
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });
      await _fillCityFromCoordinates(pos.latitude, pos.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Геолокация добавлена')));
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted) return;
      if (last != null) {
        setState(() {
          _latitude = last.latitude;
          _longitude = last.longitude;
        });
        await _fillCityFromCoordinates(last.latitude, last.longitude);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Использованы последние известные координаты'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось получить координаты вовремя'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось получить геолокацию: $e')),
      );
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _fillCityFromCoordinates(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      if (!mounted || places.isEmpty) return;
      final p = places.first;
      final city =
          (p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? '')
              .trim();
      if (city.isEmpty) return;
      if (_cityController.text.trim().isEmpty) {
        _cityController.text = city;
      }
    } catch (_) {
      // Ignore reverse geocoding errors, coordinates are still saved.
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

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
      String imageUrl = widget.product.imageUrl;
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
      await productRepository.updateProduct(
        productId: widget.productId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: price,
        imageUrl: imageUrl,
        category: _selectedSubcategory?.name ?? widget.product.category,
        categoryId: _selectedSubcategory?.id ?? widget.product.categoryId,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        condition: _condition,
        isUrgent: _isUrgent,
        isTop: _isTop,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      final authState = context.read<AuthBloc>().state;
      final currentUserId = authState is AuthAuthenticated
          ? authState.user.id
          : null;
      final updated = await productRepository.getProductById(
        widget.productId,
        currentUserId: currentUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Товар обновлён')));
      context.pop(updated);
    } catch (e, st) {
      if (!mounted) return;
      String message = 'Ошибка при сохранении';
      if (e is StorageException) {
        message =
            'Storage: проверьте бакет «products» (см. docs/SUPABASE_SETUP.md)';
      } else if (e is PostgrestException) {
        message = 'База данных: проверьте политики RLS для products';
      } else {
        message = 'Ошибка: $e';
      }
      debugPrint('EditProduct error: $e $st');
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
        title: const Text('Редактировать товар'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
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
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: widget.product.imageUrl.isNotEmpty
                            ? CachedProductImage(
                                imageUrl: widget.product.imageUrl,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 48,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Изменить фото',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
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
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
