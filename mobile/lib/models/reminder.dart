/// Represents a patient's personal reminder.
///
/// This is strictly a local client-side model with no backend or clinic affiliation.
class Reminder {
  final int id;
  final DateTime scheduledAt;
  final String? note;

  const Reminder({
    required this.id,
    required this.scheduledAt,
    this.note,
  });

  /// Creates a copy of this reminder with the given fields replaced by the new values.
  Reminder copyWith({
    int? id,
    DateTime? scheduledAt,
    String? note,
  }) {
    return Reminder(
      id: id ?? this.id,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      note: note ?? this.note,
    );
  }

  /// Whether the scheduled time is already in the past.
  bool get isPast => scheduledAt.isBefore(DateTime.now());

  /// Serializes this reminder to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scheduledAt': scheduledAt.toIso8601String(),
      'note': note,
    };
  }

  /// Deserializes a reminder from a JSON map.
  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as int,
      scheduledAt: DateTime.parse(json['scheduledAt'] as String),
      note: json['note'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Reminder &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          scheduledAt.isAtSameMomentAs(other.scheduledAt) &&
          note == other.note;

  @override
  int get hashCode => id.hashCode ^ scheduledAt.hashCode ^ (note?.hashCode ?? 0);

  @override
  String toString() =>
      'Reminder(id: $id, scheduledAt: $scheduledAt, note: $note)';
}
