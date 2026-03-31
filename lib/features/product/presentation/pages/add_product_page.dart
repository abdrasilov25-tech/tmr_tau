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
import '../../../../core/utils/kazakhstan_phone.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/seller_listing_policy.dart';
import '../../domain/repositories/categories_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../constants/product_photos.dart';
import '../widgets/draft_photos_viewer.dart';
import '../widgets/product_form_city_autocomplete_field.dart';
import '../widgets/product_form_kz_phone_field.dart';
import '../widgets/product_form_price_field.dart';
import '../widgets/product_form_promo_switches.dart';
import '../widgets/product_listing_promo_flags_controller.dart';

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
  final _cityFocusNode = FocusNode();
  final _phoneNationalController = TextEditingController();
  bool _loading = false;
  bool _gettingLocation = false;
  final List<File> _images = [];
  List<CategoryEntity> _mainCategories = [];
  List<CategoryEntity> _subcategories = [];
  CategoryEntity? _selectedMain;
  CategoryEntity? _selectedSubcategory;
  bool _categoriesLoading = true;
  SellerListingPolicy? _sellerPolicy;
  bool _sellerPolicyLoading = true;
  /// Как в OLX: только «новый» / «б/у», без «любое».
  String _condition = 'used';
  late final ProductListingPromoFlagsController _promoFlags;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _promoFlags = ProductListingPromoFlagsController(
      onGiveawayEnabled: () {
        _priceController.text = '0';
      },
    );
    _loadCategories();
    Future<void>.microtask(_loadSellerPolicy);
  }

  Future<void> _loadSellerPolicy() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      if (mounted) {
        setState(() => _sellerPolicyLoading = false);
      }
      return;
    }
    try {
      final policy = await context
          .read<ProductRepository>()
          .getSellerListingPolicy(authState.user.id);
      if (!mounted) return;
      setState(() {
        _sellerPolicy = policy;
        _sellerPolicyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sellerPolicyLoading = false);
    }
  }

  Future<void> _pickMorePhotos() async {
    final remaining = kMaxProductPhotos - _images.length;
    if (remaining <= 0) return;
    final picker = ImagePicker();
    final list = await picker.pickMultiImage(imageQuality: 85);
    if (!mounted || list.isEmpty) return;
    setState(() {
      for (final x in list) {
        if (_images.length >= kMaxProductPhotos) break;
        _images.add(File(x.path));
      }
    });
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
    _cityFocusNode.dispose();
    _phoneNationalController.dispose();
    _promoFlags.dispose();
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
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 18),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });
      await _fillCityFromCoordinates(pos.latitude, pos.longitude, overwrite: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Геолокация: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
          ),
        ),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted) return;
      if (last != null) {
        setState(() {
          _latitude = last.latitude;
          _longitude = last.longitude;
        });
        await _fillCityFromCoordinates(
          last.latitude,
          last.longitude,
          overwrite: true,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Координаты (последние): ${last.latitude.toStringAsFixed(5)}, ${last.longitude.toStringAsFixed(5)}',
            ),
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

  Future<void> _fillCityFromCoordinates(
    double lat,
    double lng, {
    bool overwrite = false,
  }) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      if (!mounted || places.isEmpty) return;
      final p = places.first;
      final city =
          (p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? '')
              .trim();
      if (city.isEmpty) return;
      if (overwrite || _cityController.text.trim().isEmpty) {
        setState(() => _cityController.text = city);
      }
    } catch (_) {
      // Ignore reverse geocoding errors, coordinates are still saved.
    }
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

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Войдите в аккаунт')));
      return;
    }

    final national = KazakhstanPhone.stripToTenDigits(_phoneNationalController.text);
    if (!KazakhstanPhone.isValidNationalTen(national)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите 10 цифр казахстанского номера после +7'),
        ),
      );
      return;
    }
    final phoneFull = KazakhstanPhone.fullInternational(national);

    late final double resolvedPrice;
    if (_promoFlags.isGiveaway) {
      resolvedPrice = 0;
    } else {
      final parsed = double.tryParse(
        _priceController.text.replaceAll(' ', '').replaceAll(',', '.'),
      );
      if (parsed == null || parsed <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите цену больше нуля')),
        );
        return;
      }
      resolvedPrice = parsed;
    }

    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одно фото')),
      );
      return;
    }

    setState(() => _loading = true);
    final productRepository = context.read<ProductRepository>();
    try {
      final policy = await productRepository.getSellerListingPolicy(
        authState.user.id,
      );
      if (!policy.canCreateProduct) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Лимит объявлений: ${policy.activeProducts}/${policy.maxActiveProducts}. '
              'Подключите Стандарт или Про.',
            ),
          ),
        );
        context.push('/qarmet-wallet');
        return;
      }

      final urls = <String>[];
      for (final file in _images) {
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
        urls.add(
          Supabase.instance.client.storage
              .from(SupabaseConstants.bucketProducts)
              .getPublicUrl(path),
        );
      }
      await productRepository.addProduct(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        price: resolvedPrice,
        imageUrls: urls,
        category: _selectedSubcategory?.name ?? 'general',
        categoryId: _selectedSubcategory?.id,
        city: _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        condition: _condition,
        isUrgent: _promoFlags.isUrgent,
        isTop: _promoFlags.isTop,
        isNegotiable: _promoFlags.isNegotiable,
        isGiveaway: _promoFlags.isGiveaway,
        latitude: _latitude,
        longitude: _longitude,
        contactPhone: phoneFull,
        sellerId: authState.user.id,
      );
      if (mounted) {
        setState(() => _sellerPolicy = policy);
      }
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
            Text(
              'Фотографии *',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (_sellerPolicyLoading)
              const LinearProgressIndicator(minHeight: 3)
            else if (_sellerPolicy != null)
              _SellerPlanInfoCard(policy: _sellerPolicy!),
            const SizedBox(height: 4),
            Text(
              'До $kMaxProductPhotos шт. Первое фото — обложка в ленте. Нажмите на фото — просмотр и зум.',
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
                  for (var i = 0; i < _images.length; i++)
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
                                  imageProviders: _images
                                      .map((f) => FileImage(f))
                                      .toList(growable: false),
                                  initialIndex: i,
                                );
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _images[i],
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
                                    setState(() => _images.removeAt(i)),
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
                  if (_images.length < kMaxProductPhotos)
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
            ProductFormPriceField(
              flags: _promoFlags,
              priceController: _priceController,
            ),
            const SizedBox(height: 16),
            ProductFormCityAutocompleteField(
              controller: _cityController,
              focusNode: _cityFocusNode,
            ),
            const SizedBox(height: 16),
            ProductFormKzPhoneField(
              controller: _phoneNationalController,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey<String>(_condition),
              initialValue: _condition,
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
            ProductFormPromoSwitches(flags: _promoFlags),
            const SizedBox(height: 8),
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
            if (_latitude != null && _longitude != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Широта ${_latitude!.toStringAsFixed(5)}, долгота ${_longitude!.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
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
                  : const Text('Опубликовать'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerPlanInfoCard extends StatelessWidget {
  const _SellerPlanInfoCard({required this.policy});

  final SellerListingPolicy policy;

  @override
  Widget build(BuildContext context) {
    final canCreate = policy.canCreateProduct;
    final subtitle = policy.isUnlimited
        ? 'Активных товаров: ${policy.activeProducts}. Лимит: без ограничений.'
        : 'Активных товаров: ${policy.activeProducts}/${policy.maxActiveProducts}. '
              'Осталось: ${policy.remainingSlots}.';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: canCreate ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canCreate ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            canCreate ? Icons.storefront_rounded : Icons.lock_outline_rounded,
            size: 18,
            color: canCreate ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'План продавца: ${policy.planLabel}. $subtitle',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
