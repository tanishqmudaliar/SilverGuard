/// Guardian contact model - trusted contacts who can be alerted about scams
class Guardian {
  final int? id;
  final String name;
  final String phone;
  final int createdAt;

  Guardian({
    this.id,
    required this.name,
    required this.phone,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'phone': phone, 'created_at': createdAt};
  }

  factory Guardian.fromMap(Map<String, dynamic> map) {
    return Guardian(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String,
      createdAt: map['created_at'] as int,
    );
  }

  @override
  String toString() => 'Guardian(id: $id, name: $name, phone: $phone)';
}
