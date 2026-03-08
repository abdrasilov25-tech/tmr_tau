import 'package:equatable/equatable.dart';

class CategoryEntity extends Equatable {
  const CategoryEntity({
    required this.id,
    required this.name,
    this.parentId,
  });

  final String id;
  final String name;
  final String? parentId;

  bool get isMainCategory => parentId == null;

  @override
  List<Object?> get props => [id, name, parentId];
}
