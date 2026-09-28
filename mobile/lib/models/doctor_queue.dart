/// Represents active queue information for a doctor returned by `/api/catalog/doctors/{doctor_id}/queue`.
class DoctorQueue {
  final int id;
  final int doctorId;
  final String queueDate;
  final bool isPaused;
  final bool isActive;

  const DoctorQueue({
    required this.id,
    required this.doctorId,
    required this.queueDate,
    required this.isPaused,
    required this.isActive,
  });

  factory DoctorQueue.fromJson(Map<String, dynamic> json) {
    return DoctorQueue(
      id: json['id'] as int,
      doctorId: json['doctor_id'] as int,
      queueDate: json['queue_date'] as String,
      isPaused: json['is_paused'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'doctor_id': doctorId,
      'queue_date': queueDate,
      'is_paused': isPaused,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DoctorQueue &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          doctorId == other.doctorId &&
          queueDate == other.queueDate;

  @override
  int get hashCode => id.hashCode ^ doctorId.hashCode ^ queueDate.hashCode;

  @override
  String toString() =>
      'DoctorQueue(id: $id, doctorId: $doctorId, queueDate: $queueDate, isPaused: $isPaused, isActive: $isActive)';
}
