import 'package:hive/hive.dart';

part 'named_item.g.dart';

@HiveType(typeId: 8)
class NamedItem extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  NamedItem({
    required this.id,
    required this.name,
  });

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NamedItem && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
