import 'package:flutter/material.dart';

import '../../../../core/widgets/app_loading.dart';
import '../../../comments/domain/repositories/comments_repository.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import 'product_detail_page.dart';

/// Загружает товар по id (диплинки и уведомления без [ProductEntity] в extra).
class ProductDetailRoutePage extends StatefulWidget {
  const ProductDetailRoutePage({
    super.key,
    required this.productId,
    required this.productRepository,
    required this.commentsRepository,
    this.mentionPrefix,
  });

  final String productId;
  final ProductRepository productRepository;
  final CommentsRepository commentsRepository;
  final String? mentionPrefix;

  @override
  State<ProductDetailRoutePage> createState() => _ProductDetailRoutePageState();
}

class _ProductDetailRoutePageState extends State<ProductDetailRoutePage> {
  late Future<ProductEntity?> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.productRepository.getProductById(widget.productId);
  }

  void _retry() {
    setState(() {
      _loadFuture = widget.productRepository.getProductById(widget.productId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProductEntity?>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: AppLoading()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Не удалось загрузить: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final product = snapshot.data;
        if (product == null) {
          return const Scaffold(
            body: Center(child: Text('Товар не найден')),
          );
        }
        return ProductDetailPage(
          product: product,
          commentsRepository: widget.commentsRepository,
          productRepository: widget.productRepository,
          mentionPrefix: widget.mentionPrefix,
        );
      },
    );
  }
}
