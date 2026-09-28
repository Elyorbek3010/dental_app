/// Represents a doctor returned by `/api/catalog/doctors`.
class Doctor {
  final int id;
  final int clinicId;
  final int specializationId;
  final String fullName;
  final String? roomNumber;
  final bool isActive;

  const Doctor({
    required this.id,
    required this.clinicId,
    required this.specializationId,
    required this.fullName,
    this.roomNumber,
    required this.isActive,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: json['id'] as int,
      clinicId: json['clinic_id'] as int,
      specializationId: json['specialization_id'] as int,
      fullName: json['full_name'] as String,
      roomNumber: json['room_number'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clinic_id': clinicId,
      'specialization_id': specializationId,
      'full_name': fullName,
      'room_number': roomNumber,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Doctor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          specializationId == other.specializationId &&
          fullName == other.fullName;

  @override
  int get hashCode => id.hashCode ^ specializationId.hashCode ^ fullName.hashCode;

  @override
  String toString() =>
      'Doctor(id: $id, fullName: $fullName, roomNumber: $roomNumber, isActive: $isActive)';
}
