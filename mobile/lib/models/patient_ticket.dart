/// Models representing queue tickets and status matching FastAPI backend schemas.
library;

import '../l10n/app_localizations.dart';

class MyTicketDoctor {
  final int id;
  final String fullName;
  final String? roomNumber;
  final int? clinicId;

  const MyTicketDoctor({
    required this.id,
    required this.fullName,
    this.roomNumber,
    this.clinicId,
  });

  factory MyTicketDoctor.fromJson(Map<String, dynamic> json) {
    return MyTicketDoctor(
      id: json['id'] as int,
      fullName: json['full_name'] as String? ?? '',
      roomNumber: json['room_number'] as String?,
      clinicId: json['clinic_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        if (roomNumber != null) 'room_number': roomNumber,
        if (clinicId != null) 'clinic_id': clinicId,
      };
}

class MyTicketSpecialization {
  final int id;
  final String name;

  const MyTicketSpecialization({
    required this.id,
    required this.name,
  });

  factory MyTicketSpecialization.fromJson(Map<String, dynamic> json) {
    return MyTicketSpecialization(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };
}

/// Represents the patient's active ticket returned by `GET /api/queues/my-ticket`.
class MyQueueTicket {
  final int id;
  final int queueId;
  final int ticketNumber;
  final String status;
  final DateTime createdAt;
  final int peopleAhead;
  final MyTicketDoctor doctor;
  final MyTicketSpecialization specialization;

  // Optional fields for forward-compatibility
  final int? queuePosition;
  final DateTime? checkedInAt;
  final String? checkInMethod;
  final int? clinicId;

  const MyQueueTicket({
    required this.id,
    required this.queueId,
    required this.ticketNumber,
    required this.status,
    required this.createdAt,
    required this.peopleAhead,
    required this.doctor,
    required this.specialization,
    this.queuePosition,
    this.checkedInAt,
    this.checkInMethod,
    this.clinicId,
  });

  factory MyQueueTicket.fromJson(Map<String, dynamic> json) {
    final doctorJson = json['doctor'] as Map<String, dynamic>? ?? {};
    final docClinicId = doctorJson['clinic_id'] as int?;
    final rootClinicId = json['clinic_id'] as int?;

    return MyQueueTicket(
      id: json['id'] as int,
      queueId: json['queue_id'] as int,
      ticketNumber: json['ticket_number'] as int,
      status: json['status'] as String? ?? 'WAITING',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      peopleAhead: json['people_ahead'] as int? ?? 0,
      doctor: MyTicketDoctor.fromJson(doctorJson),
      specialization: MyTicketSpecialization.fromJson(
        json['specialization'] as Map<String, dynamic>? ?? {},
      ),
      queuePosition: json['queue_position'] as int?,
      checkedInAt: json['checked_in_at'] != null
          ? DateTime.tryParse(json['checked_in_at'].toString())
          : null,
      checkInMethod: json['check_in_method'] as String?,
      clinicId: rootClinicId ?? docClinicId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'queue_id': queueId,
        'ticket_number': ticketNumber,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        'people_ahead': peopleAhead,
        'doctor': doctor.toJson(),
        'specialization': specialization.toJson(),
        if (queuePosition != null) 'queue_position': queuePosition,
        if (checkedInAt != null)
          'checked_in_at': checkedInAt!.toIso8601String(),
        if (checkInMethod != null) 'check_in_method': checkInMethod,
        if (clinicId != null) 'clinic_id': clinicId,
      };

  /// Uzbek presentation label for ticket status (fallback).
  String get statusLabel {
    switch (status.toUpperCase()) {
      case 'WAITING':
        return 'Kutilmoqda';
      case 'CALLED':
        return 'Navbatingiz keldi';
      case 'SERVING':
        return 'Qabul davom etmoqda';
      case 'COMPLETED':
        return 'Yakunlandi';
      case 'SKIPPED':
        return 'O‘tkazib yuborildi';
      case 'CANCELLED':
        return 'Bekor qilingan';
      default:
        return status;
    }
  }

  /// Localized presentation label for ticket status.
  String localizedStatus(AppLocalizations l10n) {
    switch (status.toUpperCase()) {
      case 'WAITING':
        return l10n.statusWaiting;
      case 'CALLED':
        return l10n.statusCalled;
      case 'SERVING':
        return l10n.statusServing;
      case 'COMPLETED':
        return l10n.statusCompleted;
      case 'SKIPPED':
        return l10n.statusSkipped;
      case 'CANCELLED':
        return l10n.statusCancelled;
      default:
        return status;
    }
  }

  bool get isWaiting => status.toUpperCase() == 'WAITING';
  bool get isCalled => status.toUpperCase() == 'CALLED';
  bool get isServing => status.toUpperCase() == 'SERVING';
  bool get isCheckedIn => checkedInAt != null;
}

/// Represents the ticket created upon joining (`POST /api/queues/{queue_id}/join`).
class QueueTicket {
  final int id;
  final int queueId;
  final int? patientId;
  final int ticketNumber;
  final int queuePosition;
  final String patientName;
  final String? patientPhone;
  final String source;
  final String status;
  final DateTime createdAt;
  final DateTime? checkedInAt;
  final String? checkInMethod;
  final int missedTurns;

  const QueueTicket({
    required this.id,
    required this.queueId,
    this.patientId,
    required this.ticketNumber,
    required this.queuePosition,
    required this.patientName,
    this.patientPhone,
    required this.source,
    required this.status,
    required this.createdAt,
    this.checkedInAt,
    this.checkInMethod,
    this.missedTurns = 0,
  });

  factory QueueTicket.fromJson(Map<String, dynamic> json) {
    return QueueTicket(
      id: json['id'] as int,
      queueId: json['queue_id'] as int,
      patientId: json['patient_id'] as int?,
      ticketNumber: json['ticket_number'] as int,
      queuePosition: json['queue_position'] as int? ?? 1,
      patientName: json['patient_name'] as String? ?? '',
      patientPhone: json['patient_phone'] as String?,
      source: json['source'] as String? ?? 'ONLINE',
      status: json['status'] as String? ?? 'WAITING',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      checkedInAt: json['checked_in_at'] != null
          ? DateTime.tryParse(json['checked_in_at'].toString())
          : null,
      checkInMethod: json['check_in_method'] as String?,
      missedTurns: json['missed_turns'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'queue_id': queueId,
        if (patientId != null) 'patient_id': patientId,
        'ticket_number': ticketNumber,
        'queue_position': queuePosition,
        'patient_name': patientName,
        if (patientPhone != null) 'patient_phone': patientPhone,
        'source': source,
        'status': status,
        'created_at': createdAt.toIso8601String(),
        if (checkedInAt != null)
          'checked_in_at': checkedInAt!.toIso8601String(),
        if (checkInMethod != null) 'check_in_method': checkInMethod,
        'missed_turns': missedTurns,
      };

  /// Uzbek presentation label for ticket status (fallback).
  String get statusLabel {
    switch (status.toUpperCase()) {
      case 'WAITING':
        return 'Kutilmoqda';
      case 'CALLED':
        return 'Navbatingiz keldi';
      case 'SERVING':
        return 'Qabul davom etmoqda';
      case 'COMPLETED':
        return 'Yakunlandi';
      case 'SKIPPED':
        return 'O‘tkazib yuborildi';
      case 'CANCELLED':
        return 'Bekor qilingan';
      default:
        return status;
    }
  }

  /// Localized presentation label for ticket status.
  String localizedStatus(AppLocalizations l10n) {
    switch (status.toUpperCase()) {
      case 'WAITING':
        return l10n.statusWaiting;
      case 'CALLED':
        return l10n.statusCalled;
      case 'SERVING':
        return l10n.statusServing;
      case 'COMPLETED':
        return l10n.statusCompleted;
      case 'SKIPPED':
        return l10n.statusSkipped;
      case 'CANCELLED':
        return l10n.statusCancelled;
      default:
        return status;
    }
  }

  bool get isWaiting => status.toUpperCase() == 'WAITING';
  bool get isCalled => status.toUpperCase() == 'CALLED';
  bool get isServing => status.toUpperCase() == 'SERVING';
  bool get isCheckedIn => checkedInAt != null;
}

/// Represents the status summary of a queue (`GET /api/queues/{queue_id}/status`).
class QueueStatus {
  final int queueId;
  final int doctorId;
  final bool isPaused;
  final int waitingCount;

  const QueueStatus({
    required this.queueId,
    required this.doctorId,
    required this.isPaused,
    required this.waitingCount,
  });

  factory QueueStatus.fromJson(Map<String, dynamic> json) {
    return QueueStatus(
      queueId: json['queue_id'] as int,
      doctorId: json['doctor_id'] as int,
      isPaused: json['is_paused'] as bool? ?? false,
      waitingCount: json['waiting_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'queue_id': queueId,
        'doctor_id': doctorId,
        'is_paused': isPaused,
        'waiting_count': waitingCount,
      };
}
