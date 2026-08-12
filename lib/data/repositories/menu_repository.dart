import 'package:ritaj_pos/data/local/app_database.dart';
import 'package:ritaj_pos/data/local/app_preferences.dart';
import 'package:ritaj_pos/data/models/product.dart';
import 'package:ritaj_pos/data/remote/supabase_service.dart';
import 'package:ritaj_pos/data/repositories/product_sync.dart';

class MenuRepository {
  const MenuRepository();

  List<ProductCategory> get categories => ProductCategory.values;

  Future<List<Product>> allProducts() async {
    await _pullRemoteProducts();
    return AppDatabase.instance.queryProducts();
  }

  Future<List<Product>> productsOf(ProductCategory category) =>
      AppDatabase.instance.queryProducts(category: category);

  Future<void> addProduct({
    required String name,
    required double price,
    required ProductCategory category,
    double cost = 0,
    String? desc,
  }) async {
    final id = 'p${DateTime.now().microsecondsSinceEpoch}';
    await AppDatabase.instance.insertProduct(Product(
      id: id,
      name: name,
      price: price,
      cost: cost,
      category: category,
      desc: desc,
    ));
    await syncMenu();
  }

  Future<void> updateProduct(Product product) async {
    await AppDatabase.instance.updateProduct(product);
    await syncMenu();
  }

  Future<void> deleteProduct(String id) async {
    await AppDatabase.instance.deleteProduct(id);
    await syncMenu();
  }

  /// Upserts categories and products to the current branch.
  /// Best-effort: local data is authoritative, the cloud is a mirror.
  Future<void> syncMenu() async {
    final client = SupabaseService.client;
    final session = client?.auth.currentSession;
    final branchId = await AppPreferences.getBranchId();
    if (client == null || session == null || branchId == null) return;
    await _pullRemoteProducts();
    try {
      final remoteCategories = await client
          .from('categories')
          .select('id,name')
          .eq('branch_id', branchId);
      final map = {
        for (final c in remoteCategories)
          c['name'] as String: c['id'] as String,
      };
      for (final (index, category) in ProductCategory.values.indexed) {
        if (!map.containsKey(category.label)) {
          final created = await client
              .from('categories')
              .insert({
                'branch_id': branchId,
                'name': category.label,
                'sort_order': index,
              })
              .select('id')
              .single();
          map[category.label] = created['id'] as String;
        }
      }
      final products = await AppDatabase.instance.queryProductsAll();
      for (final product in products) {
        await client.from('products').upsert({
          'branch_id': branchId,
          'category_id': map[product.category.label],
          'name': product.name,
          'price': product.price,
          'cost': product.cost,
          'tax_rate': 0,
          'active': product.active,
          'local_key': product.id,
          'updated_at': (product.updatedAt ?? DateTime.now())
              .toUtc()
              .toIso8601String(),
        }, onConflict: 'branch_id,local_key');
      }
    } catch (_) {
      // Menu sync is best-effort; offline edits remain local.
    }
  }

  Future<void> _pullRemoteProducts() async {
    final client = SupabaseService.client;
    final branchId = await AppPreferences.getBranchId();
    if (client == null || branchId == null) return;
    try {
      final rows = await client
          .from('products')
          .select('local_key,name,price,cost,active,updated_at,categories(name)')
          .eq('branch_id', branchId);
      final local = {
        for (final p in await AppDatabase.instance.queryProductsAll()) p.id: p,
      };
      for (final row in rows) {
        final key = row['local_key'] as String?;
        if (key == null) continue;
        final categoryName = row['categories'] is Map
            ? (row['categories'] as Map)['name'] as String?
            : null;
        ProductCategory? category;
        for (final c in ProductCategory.values) {
          if (c.label == categoryName) {
            category = c;
            break;
          }
        }
        if (category == null) continue;
        final remote = Product(
          id: key,
          name: row['name'] as String,
          price: double.tryParse(row['price']?.toString() ?? '') ?? 0,
          cost: double.tryParse(row['cost']?.toString() ?? '') ?? 0,
          category: category,
          active: row['active'] as bool? ?? true,
          updatedAt: row['updated_at'] is DateTime
              ? (row['updated_at'] as DateTime).toUtc()
              : DateTime.tryParse(row['updated_at'] as String? ?? '')
                  ?.toUtc(),
        );
        final winner =
            ProductSync.mergeProduct(local: local[key], remote: remote);
        if (winner != null && !identical(winner, local[key])) {
          await AppDatabase.instance.upsertSyncedProduct(
            id: winner.id,
            name: winner.name,
            price: winner.price,
            cost: winner.cost,
            category: winner.category,
            active: winner.active,
            updatedAt: winner.updatedAt ?? DateTime.now().toUtc(),
          );
        }
      }
    } catch (_) {
      // Best-effort menu pull; offline keeps local.
    }
  }
}
