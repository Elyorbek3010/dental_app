/// Represents a dental specialization returned by `/api/catalog/specializations`.
class Specialization {
  final int id;
  final int clinicId;
  final String name;

  const Specialization({
    required this.id,
    required this.clinicId,
    required this.name,
  });

  factory Specialization.fromJson(Map<String, dynamic> json) {
    return Specialization(
      id: json['id'] as int,
      clinicId: json['clinic_id'] as int,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clinic_id': clinicId,
      'name': name,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Specialization &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          clinicId == other.clinicId &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ clinicId.hashCode ^ name.hashCode;

  @override
  String toString() => 'Specialization(id: $id, clinicId: $clinicId, name: $name)';
}
