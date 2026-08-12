import 'package:flutter_test/flutter_test.dart';

import 'package:ritaj_pos/data/models/product.dart';
import 'package:ritaj_pos/data/repositories/product_sync.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 12);
  final older = now.subtract(const Duration(hours: 1));

  Product product(String id, {double price = 1, bool active = true, DateTime? updatedAt, String? desc}) =>
      Product(
        id: id,
        name: 'Name $id',
        price: price,
        category: ProductCategory.shawarma,
        active: active,
        updatedAt: updatedAt,
        desc: desc,
      );

  test('local absent + remote present -> remote adopted', () {
    final remote = product('p1', updatedAt: now);
    expect(ProductSync.mergeProduct(local: null, remote: remote), remote);
  });

  test('local newer -> local kept', () {
    final local = product('p1', price: 5, updatedAt: now);
    final remote = product('p1', price: 2, updatedAt: older);
    expect(ProductSync.mergeProduct(local: local, remote: remote), local);
  });

  test('remote newer -> remote adopted, local desc preserved', () {
    final local = product('p1', price: 2, updatedAt: older, desc: 'maison');
    final remote = product('p1', price: 8, updatedAt: now);
    final winner = ProductSync.mergeProduct(local: local, remote: remote)!;
    expect(winner.price, 8);
    expect(winner.desc, 'maison');
    expect(winner.updatedAt, now);
  });

  test('remote newer tombstone (active=false) -> adopted inactive', () {
    final local = product('p1', updatedAt: older);
    final remote = product('p1', active: false, updatedAt: now);
    final winner = ProductSync.mergeProduct(local: local, remote: remote)!;
    expect(winner.active, isFalse);
  });

  test('equal timestamps -> local kept (stable)', () {
    final local = product('p1', price: 5, updatedAt: now);
    final remote = product('p1', price: 2, updatedAt: now);
    expect(ProductSync.mergeProduct(local: local, remote: remote), local);
  });
}
