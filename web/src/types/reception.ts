export type TicketStatus =
  | 'WAITING'
  | 'CALLED'
  | 'SERVING'
  | 'COMPLETED'
  | 'SKIPPED'
  | 'CANCELLED';

export type TicketSource = 'ONLINE' | 'WALK_IN';

export type CheckInMethod = 'QR' | 'RECEPTION' | 'WALK_IN';

export interface Doctor {
  id: number;
  clinic_id: number;
  specialization_id: number;
  full_name: string;
  room_number: string | null;
  is_active: boolean;
}

export interface Specialization {
  id: number;
  clinic_id: number;
  name: string;
}

export interface ReceptionQueueDoctor {
  id: number;
  full_name: string;
  room_number: string | null;
}

export interface ReceptionQueueSpecialization {
  id: number;
  name: string;
}

export interface ReceptionQueueOverview {
  queue_id: number;
  queue_date: string;
  is_paused: boolean;
  is_active: boolean;
  doctor: ReceptionQueueDoctor;
  specialization: ReceptionQueueSpecialization;
  waiting_count: number;
  called_count: number;
  serving_count: number;
  completed_count: number;
}

export interface QueueTicket {
  id: number;
  queue_id: number;
  patient_id: number | null;
  ticket_number: number;
  queue_position: number;
  patient_name: string;
  patient_phone: string | null;
  source: TicketSource;
  status: TicketStatus;
  created_at: string;
  checked_in_at: string | null;
  check_in_method: CheckInMethod | null;
  missed_turns: number;
  called_at?: string | null;
  call_deadline_at?: string | null;
  paused_remaining_seconds?: number | null;
  server_time?: string | null;
}

export interface WalkInPatientCreate {
  patient_name: string;
  patient_phone?: string | null;
}

export interface QueueCreateRequest {
  doctor_id: number;
  queue_date?: string | null;
  idempotent?: boolean;
}

export interface QueueResponse {
  id: number;
  doctor_id: number;
  queue_date: string;
  is_paused: boolean;
  is_active: boolean;
}
