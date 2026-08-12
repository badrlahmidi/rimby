import 'package:ritaj_pos/data/models/product.dart';

class ProductSync {
  static Product? mergeProduct({
    required Product? local,
    required Product? remote,
  }) {
    if (local == null) return remote;
    if (remote == null) return local;
    final localTs = local.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final remoteTs = remote.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    if (remoteTs.isAfter(localTs)) {
      return Product(
        id: remote.id,
        name: remote.name,
        price: remote.price,
        cost: remote.cost,
        category: remote.category,
        active: remote.active,
        updatedAt: remote.updatedAt,
        desc: remote.desc ?? local.desc,
      );
    }
    return local;
  }
}
