enum ProductCategory {
  shawarma('الشاورما'),
  snacks('السناكات'),
  italian('ايطالي'),
  drinks('مشروبات'),
  additions('إضافات'),
  familyMeals('وجبات عائلية'),
  staff('طلبات الموظفين');

  const ProductCategory(this.label);

  final String label;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.cost = 0,
    this.desc,
    this.active = true,
    this.updatedAt,
  });

  final String id;
  final String name;
  final double price;
  final double cost;
  final String? desc;
  final ProductCategory category;
  final bool active;
  final DateTime? updatedAt;
}
