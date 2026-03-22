import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
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
import '../constants/product_photos.dart';
import '../widgets/draft_photos_viewer.dart';

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
  late final TextEditingController _phoneController;
  bool _loading = false;
  bool _gettingLocation = false;
  final List<String> _remoteImageUrls = [];
  final List<File> _newImageFiles = [];
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
    _phoneController = TextEditingController(text: p.contactPhone ?? '');
    _remoteImageUrls.addAll(p.imageUrls);
    if (_remoteImageUrls.isEmpty && p.imageUrl.isNotEmpty) {
      _remoteImageUrls.add(p.imageUrl);
    }
    _condition = p.condition == 'any' ? 'used' : p.condition;
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
    _phoneController.dispose();
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

  int get _totalPhotoCount => _remoteImageUrls.length + _newImageFiles.length;

  List<ImageProvider> _draftImageProviders() => [
        ..._remoteImageUrls.map((u) => CachedNetworkImageProvider(u)),
        ..._newImageFiles.map((f) => FileImage(f)),
      ];

  Future<void> _pickMorePhotos() async {
    final space = kMaxProductPhotos - _totalPhotoCount;
    if (space <= 0) return;
    final picker = ImagePicker();
    final list = await picker.pickMultiImage(imageQuality: 85);
    if (!mounted || list.isEmpty) return;
    setState(() {
      for (final x in list) {
        if (_totalPhotoCount >= kMaxProductPhotos) break;
        _newImageFiles.add(File(x.path));
      }
    });
  }

  Future<String> _uploadToStorage(File file) async {
    const uuid = Uuid();
    final ext = file.path.split('.').last;
    final path = '${uuid.v4()}.$ext';
    await Supabase.instance.client.storage
        .from(SupabaseConstants.bucketProducts)
        .upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );
    return Supabase.instance.client.storage
        .from(SupabaseConstants.bucketProducts)
        .getPublicUrl(path);
  }

  /// Данные с формы, если после UPDATE не удалось снова прочитать строку из БД.
  ProductEntity _buildLocalProductFromForm(double price, List<String> imageUrls) {
    final categoryLabel = _categoriesLoading
        ? widget.product.category
        : (_selectedSubcategory?.name ??
            _selectedMain?.name ??
            widget.product.category);
    final categoryIdForDb = _categoriesLoading
        ? widget.product.categoryId
        : _selectedSubcategory?.id;
    return ProductEntity(
      id: widget.productId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      price: price,
      imageUrls: imageUrls,
      sellerId: widget.product.sellerId,
      category: categoryLabel,
      categoryId: categoryIdForDb,
      likesCount: widget.product.likesCount,
      commentsCount: widget.product.commentsCount,
      repostsCount: widget.product.repostsCount,
      sellerName: widget.product.sellerName,
      sellerAvatarUrl: widget.product.sellerAvatarUrl,
      createdAt: widget.product.createdAt,
      isLikedByMe: widget.product.isLikedByMe,
      isFollowingSeller: widget.product.isFollowingSeller,
      sellerIsVerified: widget.product.sellerIsVerified,
      isRepostedByMe: widget.product.isRepostedByMe,
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      condition: _condition,
      isUrgent: _isUrgent,
      isTop: _isTop,
      latitude: _latitude,
      longitude: _longitude,
      contactPhone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
    );
  }

  Future<void> _submit() async {
    if (_categoriesLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подождите загрузки категорий')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите категорию')),
      );
      return;
    }
    if (_subcategories.isNotEmpty && _selectedSubcategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите подкатегорию')),
      );
      return;
    }

    final price = double.tryParse(
      _priceController.text.replaceAll(' ', '').replaceAll(',', '.'),
    );
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Укажите цену больше нуля')));
      return;
    }

    if (_totalPhotoCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одно фото')),
      );
      return;
    }

    setState(() => _loading = true);
    final productRepository = context.read<ProductRepository>();
    try {
      final imageUrls = <String>[..._remoteImageUrls];
      for (final f in _newImageFiles) {
        imageUrls.add(await _uploadToStorage(f));
      }
      final categoryLabel = _categoriesLoading
          ? widget.product.category
          : (_selectedSubcategory?.name ??
              _selectedMain?.name ??
              widget.product.category);
      final categoryIdForDb = _categoriesLoading
          ? widget.product.categoryId
          : _selectedSubcategory?.id;

      final phoneTrim = _phoneController.text.trim();
      await productRepository.updateProduct(
        productId: widget.productId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: price,
        imageUrls: imageUrls,
        category: categoryLabel,
        categoryId: categoryIdForDb,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        condition: _condition,
        isUrgent: _isUrgent,
        isTop: _isTop,
        latitude: _latitude,
        longitude: _longitude,
        contactPhone: phoneTrim.isEmpty ? null : phoneTrim,
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
      // Если повторный SELECT недоступен (RLS/сеть), всё равно отдаём экрану актуальные поля.
      final out = updated ?? _buildLocalProductFromForm(price, imageUrls);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Товар обновлён')));
      context.pop(out);
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
            Text(
              'Фотографии *',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'До $kMaxProductPhotos шт. Первое фото — обложка. Нажмите на фото — просмотр и зум.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 112,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _remoteImageUrls.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                DraftPhotosViewer.show(
                                  context,
                                  imageProviders: _draftImageProviders(),
                                  initialIndex: i,
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedProductImage(
                                  imageUrl: _remoteImageUrls[i],
                                  width: 112,
                                  height: 112,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                onPressed: () =>
                                    setState(() => _remoteImageUrls.removeAt(i)),
                              ),
                            ),
                          ),
                          if (i == 0)
                            Positioned(
                              bottom: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Обложка',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  for (var j = 0; j < _newImageFiles.length; j++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                DraftPhotosViewer.show(
                                  context,
                                  imageProviders: _draftImageProviders(),
                                  initialIndex: _remoteImageUrls.length + j,
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _newImageFiles[j],
                                  width: 112,
                                  height: 112,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                onPressed: () =>
                                    setState(() => _newImageFiles.removeAt(j)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_totalPhotoCount < kMaxProductPhotos)
                    Material(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _pickMorePhotos,
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 112,
                          height: 112,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 36,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Добавить',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
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
                key: ValueKey<Object?>(_selectedMain?.id),
                initialValue: _selectedMain,
                decoration: const InputDecoration(labelText: 'Категория *'),
                items: _mainCategories
                    .map(
                      (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                    )
                    .toList(),
                validator: (v) =>
                    v == null ? 'Выберите категорию' : null,
                onChanged: (v) => _onMainCategorySelected(v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CategoryEntity>(
                key: ValueKey<String>(
                  '${_selectedMain?.id}_${_subcategories.length}_${_selectedSubcategory?.id}',
                ),
                initialValue: _selectedSubcategory,
                decoration: InputDecoration(
                  labelText: _subcategories.isEmpty
                      ? 'Подкатегория'
                      : 'Подкатегория *',
                ),
                items: [
                  const DropdownMenuItem<CategoryEntity>(
                    value: null,
                    child: Text('— Выберите подкатегорию —'),
                  ),
                  ..._subcategories.map(
                    (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                  ),
                ],
                validator: (v) {
                  if (_subcategories.isEmpty) return null;
                  return v == null ? 'Выберите подкатегорию' : null;
                },
                onChanged: _selectedMain == null
                    ? null
                    : (v) => setState(() => _selectedSubcategory = v),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Название *',
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
                labelText: 'Цена (₸) *',
                hintText: '0',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Введите цену';
                final p = double.tryParse(
                  v.replaceAll(' ', '').replaceAll(',', '.'),
                );
                if (p == null) return 'Некорректная цена';
                if (p <= 0) return 'Цена должна быть больше нуля';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Город *',
                hintText: 'Например, Алматы',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Укажите город' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Телефон для звонков *',
                hintText: '+7 707 123 45 67',
                helperText:
                    'Покупатели увидят номер после «Позвонить»',
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Укажите номер телефона';
                final digits = t.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 9) {
                  return 'Введите номер полностью';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(_condition == 'any' ? 'used' : _condition),
              initialValue: _condition == 'any' ? 'used' : _condition,
              decoration: const InputDecoration(labelText: 'Состояние *'),
              items: const [
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
            Text(
              'Платное продвижение на 24 ч и статистика — кнопка «Продвижение» в объявлении.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
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
                labelText: 'Описание *',
                hintText:
                    'Опишите товар: состояние, комплектация, причина продажи…',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              minLines: 3,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Введите описание';
                if (t.length < 20) {
                  return 'Минимум 20 символов в описании';
                }
                return null;
              },
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
