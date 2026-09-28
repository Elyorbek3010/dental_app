/// Represents an authenticated patient user returned by the backend `/api/auth/me` endpoint.
class PatientUser {
  final int id;
  final int? clinicId;
  final String fullName;
  final String phone;
  final String role;
  final bool isActive;

  const PatientUser({
    required this.id,
    this.clinicId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.isActive,
  });

  bool get isPatient => role.toUpperCase() == 'PATIENT';

  factory PatientUser.fromJson(Map<String, dynamic> json) {
    return PatientUser(
      id: json['id'] as int,
      clinicId: json['clinic_id'] as int?,
      fullName: json['full_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'PATIENT',
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clinic_id': clinicId,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatientUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          phone == other.phone;

  @override
  int get hashCode => id.hashCode ^ phone.hashCode;

  @override
  String toString() =>
      'PatientUser(id: $id, fullName: $fullName, phone: $phone, role: $role, isActive: $isActive)';
}
