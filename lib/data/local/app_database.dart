import 'package:sqflite/sqflite.dart';

import 'package:ritaj_pos/data/models/cart_item.dart';
import 'package:ritaj_pos/data/models/product.dart';
import 'package:ritaj_pos/data/models/sale.dart';
import 'package:ritaj_pos/data/seed_data.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _version = 8;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final String dir = await getDatabasesPath();
    return openDatabase(
      '$dir/ritaj_pos.db',
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_no INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        tendered REAL NOT NULL DEFAULT 0,
        change REAL NOT NULL DEFAULT 0,
        shift_id INTEGER,
        table_id TEXT,
        customer_name TEXT,
        customer_phone TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        line_total REAL NOT NULL,
        cost REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_orders_created ON orders(created_at)');
    await _createProductsTable(db);
    await _createShiftsTable(db);
    await _createTablesSchema(db);
    await _createPendingSyncTable(db);
    await _createExpensesTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE orders ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'
      ''');
      await db.execute('''
        ALTER TABLE orders ADD COLUMN tendered REAL NOT NULL DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE orders ADD COLUMN change REAL NOT NULL DEFAULT 0
      ''');
    }
    if (oldVersion < 3) {
      await _createProductsTable(db);
    }
    if (oldVersion < 4) {
      await _createShiftsTable(db);
    }
    if (oldVersion < 5) {
      await _createTablesSchema(db);
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE orders ADD COLUMN shift_id INTEGER');
      await db.execute('ALTER TABLE orders ADD COLUMN table_id TEXT');
      await db.execute('ALTER TABLE tables ADD COLUMN remote_status TEXT');
      await _createPendingSyncTable(db);
    }
    if (oldVersion < 7) {
      final pCols = await db.rawQuery('PRAGMA table_info(products)');
      if (!pCols.any((c) => c['name'] == 'cost')) {
        await db.execute(
            'ALTER TABLE products ADD COLUMN cost REAL NOT NULL DEFAULT 0');
      }
      final oiCols = await db.rawQuery('PRAGMA table_info(order_items)');
      if (!oiCols.any((c) => c['name'] == 'cost')) {
        await db.execute(
            'ALTER TABLE order_items ADD COLUMN cost REAL NOT NULL DEFAULT 0');
      }
      await _createExpensesTable(db);
    }
    if (oldVersion < 8) {
      final cols8 = await db.rawQuery('PRAGMA table_info(products)');
      if (!cols8.any((c) => c['name'] == 'updated_at')) {
        await db.execute('ALTER TABLE products ADD COLUMN updated_at TEXT');
        await db.rawUpdate(
          'UPDATE products SET updated_at = ?',
          [DateTime.now().toUtc().toIso8601String()],
        );
      }
    }
  }

  Future<void> _createTablesSchema(Database db) async {
    await db.execute('''
      CREATE TABLE tables (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        area TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        remote_status TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE open_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_id TEXT NOT NULL REFERENCES tables(id) ON DELETE CASCADE,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE open_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        open_order_id INTEGER NOT NULL REFERENCES open_orders(id) ON DELETE CASCADE,
        product_id TEXT,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        line_total REAL NOT NULL
      )
    ''');
    await _seedTablesIfEmpty(db);
  }

  Future<void> _seedTablesIfEmpty(Database db) async {
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM tables')) ??
        0;
    if (count > 0) return;
    final batch = db.batch();
    for (var i = 1; i <= 6; i++) {
      batch.insert('tables', {
        'id': 't$i',
        'name': 'طاولة $i',
        'sort_order': i,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _createShiftsTable(Database db) async {
    await db.execute('''
      CREATE TABLE shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening_amount REAL NOT NULL,
        expected_amount REAL,
        remote_id TEXT
      )
    ''');
  }

  Future<void> _createPendingSyncTable(Database db) async {
    await db.execute('''
      CREATE TABLE pending_sync (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createExpensesTable(Database db) async {
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        amount REAL NOT NULL,
        created_at TEXT NOT NULL,
        remote_id TEXT
      )
    ''');
    await db
        .execute('CREATE INDEX idx_expenses_created ON expenses(created_at)');
  }

  Future<void> _createProductsTable(Database db) async {
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        cost REAL NOT NULL DEFAULT 0,
        desc TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT
      )
    ''');
    await db
        .execute('CREATE INDEX idx_products_category ON products(category)');
    await _seedProductsIfEmpty(db);
  }

  Future<void> _seedProductsIfEmpty(Database db) async {
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM products')) ??
        0;
    if (count > 0) return;
    final batch = db.batch();
    for (final product in seedProducts) {
      batch.insert('products', {
        'id': product.id,
        'category': product.category.name,
        'name': product.name,
        'price': product.price,
        'desc': product.desc,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<int> insertOrder({
    required int ticketNo,
    required DateTime createdAtUtc,
    required double total,
    required List<OrderItem> items,
    required PaymentMethod paymentMethod,
    required double tendered,
    int? shiftId,
    String? tableId,
    String? customerName,
    String? customerPhone,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final orderId = await txn.insert('orders', {
        'ticket_no': ticketNo,
        'created_at': createdAtUtc.toIso8601String(),
        'total': total,
        'payment_method': paymentMethod.name,
        'tendered': tendered,
        'change': tendered > 0 ? tendered - total : 0,
        'shift_id': shiftId,
        'table_id': tableId,
        'customer_name': customerName,
        'customer_phone': customerPhone,
      });
      for (final item in items) {
        await txn.insert('order_items', {
          'order_id': orderId,
          'product_name': item.productName,
          'unit_price': item.unitPrice,
          'quantity': item.quantity,
          'line_total': item.lineTotal,
          'cost': item.cost,
        });
      }
      return orderId;
    });
  }

  Future<List<Map<String, Object?>>> queryOrders(
      {DateTime? startUtc, DateTime? endUtc, int? shiftId}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (startUtc != null) {
      where.add('created_at >= ?');
      args.add(startUtc.toIso8601String());
    }
    if (endUtc != null) {
      where.add('created_at < ?');
      args.add(endUtc.toIso8601String());
    }
    if (shiftId != null) {
      where.add('shift_id = ?');
      args.add(shiftId);
    }
    final clause = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    return db.rawQuery(
      'SELECT * FROM orders$clause ORDER BY created_at ASC',
      args,
    );
  }

  Future<List<Map<String, Object?>>> queryOrderItems(int orderId) async {
    final db = await database;
    return db.query('order_items', where: 'order_id = ?', whereArgs: [orderId]);
  }

  Future<List<Map<String, Object?>>> queryOrdersById(int orderId) async {
    final db = await database;
    return db.query('orders', where: 'id = ?', whereArgs: [orderId]);
  }

  Future<List<Product>> queryProducts({ProductCategory? category}) async {
    final db = await database;
    final rows = category == null
        ? await db.query('products', where: 'active = 1')
        : await db.query(
            'products',
            where: 'active = 1 AND category = ?',
            whereArgs: [category.name],
          );
    return [
      for (final row in rows)
        Product(
          id: row['id'] as String,
          name: row['name'] as String,
          price: (row['price'] as num).toDouble(),
          cost: ((row['cost'] as num?) ?? 0).toDouble(),
          category: ProductCategory.values.byName(row['category'] as String),
          desc: row['desc'] as String?,
          active: (row['active'] as int? ?? 1) == 1,
          updatedAt: _parseUtc(row['updated_at']),
        ),
    ];
  }

  Future<List<Product>> queryProductsAll() async {
    final db = await database;
    final rows = await db.query('products');
    return [
      for (final row in rows)
        Product(
          id: row['id'] as String,
          name: row['name'] as String,
          price: (row['price'] as num).toDouble(),
          cost: ((row['cost'] as num?) ?? 0).toDouble(),
          category: ProductCategory.values.byName(row['category'] as String),
          desc: row['desc'] as String?,
          active: (row['active'] as int? ?? 1) == 1,
          updatedAt: _parseUtc(row['updated_at']),
        ),
    ];
  }

  Future<void> upsertSyncedProduct({
    required String id,
    required String name,
    required double price,
    required double cost,
    required ProductCategory category,
    required bool active,
    required DateTime updatedAt,
  }) async {
    final db = await database;
    final existing =
        await db.query('products', where: 'id = ?', whereArgs: [id]);
    final data = {
      'category': category.name,
      'name': name,
      'price': price,
      'cost': cost,
      'active': active ? 1 : 0,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
    if (existing.isEmpty) {
      await db.insert('products', {'id': id, ...data});
    } else {
      await db.update('products', data, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> insertProduct(Product product) async {
    final db = await database;
    await db.insert('products', {
      'id': product.id,
      'category': product.category.name,
      'name': product.name,
      'price': product.price,
      'cost': product.cost,
      'desc': product.desc,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.update(
      'products',
      {
        'category': product.category.name,
        'name': product.name,
        'price': product.price,
        'cost': product.cost,
        'desc': product.desc,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> deleteProduct(String id) async {
    final db = await database;
    await db.update(
      'products',
      {
        'active': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertShift({
    required DateTime openedAtUtc,
    required double openingAmount,
  }) async {
    final db = await database;
    return db.insert('shifts', {
      'opened_at': openedAtUtc.toIso8601String(),
      'opening_amount': openingAmount,
    });
  }

  Future<void> closeShift(
    int id, {
    required DateTime closedAtUtc,
    required double expectedAmount,
  }) async {
    final db = await database;
    await db.update(
      'shifts',
      {
        'closed_at': closedAtUtc.toIso8601String(),
        'expected_amount': expectedAmount,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>?> queryOpenShift() async {
    final db = await database;
    final rows = await db.query('shifts', where: 'closed_at IS NULL', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setShiftRemoteId(int id, String remoteId) async {
    final db = await database;
    await db.update(
      'shifts',
      {'remote_id': remoteId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String?> queryShiftRemoteId(int shiftId) async {
    final db = await database;
    final rows = await db.query(
      'shifts',
      columns: ['remote_id'],
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['remote_id'] as String?;
  }

  Future<List<Map<String, Object?>>> queryTables() async {
    final db = await database;
    return db.rawQuery('''
      SELECT t.id, t.name, t.area, t.sort_order, t.remote_status,
             CASE WHEN oo.id IS NULL THEN 0 ELSE 1 END AS occupied
      FROM tables t
      LEFT JOIN open_orders oo ON oo.table_id = t.id
      ORDER BY t.sort_order ASC
    ''');
  }

  Future<void> upsertTable({
    required String id,
    required String name,
    String? area,
    required int sortOrder,
  }) async {
    final db = await database;
    final existing = await db.query('tables', where: 'id = ?', whereArgs: [id]);
    if (existing.isEmpty) {
      await db.insert('tables', {
        'id': id,
        'name': name,
        'area': area,
        'sort_order': sortOrder,
      });
    } else {
      await db.update(
        'tables',
        {'name': name, 'area': area, 'sort_order': sortOrder},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteTable(String id) async {
    final db = await database;
    await db.delete('tables', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, Object?>?> getOpenOrderByTable(String tableId) async {
    final db = await database;
    final rows = await db.query('open_orders',
        where: 'table_id = ?', whereArgs: [tableId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> queryOpenOrderItems(
      int openOrderId) async {
    final db = await database;
    return db.query('open_order_items',
        where: 'open_order_id = ?', whereArgs: [openOrderId]);
  }

  Future<void> upsertOpenOrder({
    required String tableId,
    required List<CartItem> items,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn
          .delete('open_orders', where: 'table_id = ?', whereArgs: [tableId]);
      final openOrderId = await txn.insert('open_orders', {
        'table_id': tableId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      for (final item in items) {
        await txn.insert('open_order_items', {
          'open_order_id': openOrderId,
          'product_id': item.product.id,
          'product_name': item.product.name,
          'unit_price': item.product.price,
          'quantity': item.quantity,
          'line_total': item.lineTotal,
        });
      }
    });
  }

  Future<void> deleteOpenOrder(String tableId) async {
    final db = await database;
    await db.delete('open_orders', where: 'table_id = ?', whereArgs: [tableId]);
  }

  Future<void> setTableRemoteStatus(String tableId, String? status) async {
    final db = await database;
    await db.update(
      'tables',
      {'remote_status': status},
      where: 'id = ?',
      whereArgs: [tableId],
    );
  }

  Future<void> enqueuePendingSync(String type, String payload) async {
    final db = await database;
    await db.insert('pending_sync', {
      'type': type,
      'payload': payload,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> queryPendingSync() async {
    final db = await database;
    return db.query('pending_sync', orderBy: 'created_at ASC', limit: 50);
  }

  Future<void> deletePendingSync(int id) async {
    final db = await database;
    await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> incrementPendingSyncAttempt(int id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_sync SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  Future<int> insertExpense({
    required String label,
    required double amount,
    required DateTime createdAtUtc,
  }) async {
    final db = await database;
    return db.insert('expenses', {
      'label': label,
      'amount': amount,
      'created_at': createdAtUtc.toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> queryExpenses({
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (startUtc != null) {
      where.add('created_at >= ?');
      args.add(startUtc.toIso8601String());
    }
    if (endUtc != null) {
      where.add('created_at < ?');
      args.add(endUtc.toIso8601String());
    }
    final clause = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    return db.rawQuery(
      'SELECT * FROM expenses$clause ORDER BY created_at ASC',
      args,
    );
  }

  Future<void> setExpenseRemoteId(int id, String remoteId) async {
    final db = await database;
    await db.update(
      'expenses',
      {'remote_id': remoteId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String?> queryExpenseRemoteId(int expenseId) async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      columns: ['remote_id'],
      where: 'id = ?',
      whereArgs: [expenseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['remote_id'] as String?;
  }

  static DateTime? _parseUtc(Object? value) {
    final raw = value as String?;
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }
}
