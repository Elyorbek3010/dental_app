/// Represents active queue information for a doctor returned by `/api/catalog/doctors/{doctor_id}/queue`.
class DoctorQueue {
  final int id;
  final int queueId;
  final int doctorId;
  final String queueDate;
  final bool isPaused;
  final bool isActive;
  final int waitingCount;
  final int calledCount;
  final int servingCount;
  final int estimatedPositionIfJoined;
  final bool hasPreviewMetrics;

  const DoctorQueue({
    required this.id,
    int? queueId,
    required this.doctorId,
    required this.queueDate,
    required this.isPaused,
    required this.isActive,
    this.waitingCount = 0,
    this.calledCount = 0,
    this.servingCount = 0,
    this.estimatedPositionIfJoined = 1,
    this.hasPreviewMetrics = false,
  }) : queueId = queueId ?? id;

  factory DoctorQueue.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] as int? ?? json['queue_id'] as int;
    final qId = json['queue_id'] as int? ?? rawId;
    final hasMetrics = json.containsKey('waiting_count') ||
        json.containsKey('called_count') ||
        json.containsKey('serving_count') ||
        json.containsKey('estimated_position_if_joined') ||
        json.containsKey('queue_id');
    return DoctorQueue(
      id: rawId,
      queueId: qId,
      doctorId: json['doctor_id'] as int,
      queueDate: json['queue_date'] as String,
      isPaused: json['is_paused'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      waitingCount: json['waiting_count'] as int? ?? 0,
      calledCount: json['called_count'] as int? ?? 0,
      servingCount: json['serving_count'] as int? ?? 0,
      estimatedPositionIfJoined:
          json['estimated_position_if_joined'] as int? ?? 1,
      hasPreviewMetrics: hasMetrics,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'doctor_id': doctorId,
      'queue_date': queueDate,
      'is_paused': isPaused,
      'is_active': isActive,
    };
    if (hasPreviewMetrics) {
      map['queue_id'] = queueId;
      map['waiting_count'] = waitingCount;
      map['called_count'] = calledCount;
      map['serving_count'] = servingCount;
      map['estimated_position_if_joined'] = estimatedPositionIfJoined;
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DoctorQueue &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          doctorId == other.doctorId &&
          queueDate == other.queueDate &&
          waitingCount == other.waitingCount &&
          calledCount == other.calledCount &&
          servingCount == other.servingCount &&
          estimatedPositionIfJoined == other.estimatedPositionIfJoined &&
          isPaused == other.isPaused &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^
      doctorId.hashCode ^
      queueDate.hashCode ^
      waitingCount.hashCode ^
      calledCount.hashCode ^
      servingCount.hashCode ^
      estimatedPositionIfJoined.hashCode ^
      isPaused.hashCode ^
      isActive.hashCode;

  @override
  String toString() =>
      'DoctorQueue(id: $id, queueId: $queueId, doctorId: $doctorId, queueDate: $queueDate, isPaused: $isPaused, isActive: $isActive, waitingCount: $waitingCount, calledCount: $calledCount, servingCount: $servingCount, estimatedPositionIfJoined: $estimatedPositionIfJoined)';
}
