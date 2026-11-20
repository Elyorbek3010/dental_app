export interface AdminClinic {
  id: number;
  name: string;
  smart_call_timeout_seconds: number;
  timezone?: string;
}

export interface AdminSpecialization {
  id: number;
  clinic_id: number;
  name_uz: string;
  name_ru: string | null;
  name_en: string | null;
  is_active: boolean;
}

export interface AdminSpecializationCreatePayload {
  name_uz: string;
  name_ru?: string | null;
  name_en?: string | null;
}

export interface AdminSpecializationUpdatePayload {
  name_uz?: string;
  name_ru?: string | null;
  name_en?: string | null;
  is_active?: boolean;
}

export interface AdminDoctor {
  id: number;
  clinic_id: number;
  specialization_id: number;
  full_name: string;
  room_number: string | null;
  is_active: boolean;
  specialization_name_uz?: string | null;
  specialization_name_ru?: string | null;
  specialization_name_en?: string | null;
}

export interface AdminDoctorCreatePayload {
  full_name: string;
  specialization_id: number;
  room_number?: string | null;
  is_active?: boolean;
}

export interface AdminDoctorUpdatePayload {
  full_name?: string;
  specialization_id?: number;
  room_number?: string | null;
  is_active?: boolean;
}

export interface AdminReceptionist {
  id: number;
  clinic_id: number | null;
  full_name: string;
  phone: string;
  role: string;
  is_active: boolean;
  created_at: string;
}

export interface AdminReceptionistCreatePayload {
  full_name: string;
  phone: string;
  password: string;
}

export interface AdminReceptionistUpdatePayload {
  full_name?: string;
  phone?: string;
  password?: string;
  is_active?: boolean;
}

export interface DoctorQueueSummary {
  doctor_id: number;
  doctor_name: string;
  room_number: string | null;
  specialization_name: string;
  has_queue_today: boolean;
  queue_is_active: boolean;
  total_tickets: number;
  waiting_tickets: number;
  serving_tickets: number;
  completed_tickets: number;
}

export interface AdminAnalyticsOverview {
  active_doctors_count: number;
  total_doctors_count: number;
  active_specializations_count: number;
  active_receptionists_count: number;
  today_opened_queues_count: number;
  today_tickets_total: number;
  today_tickets_waiting: number;
  today_tickets_called: number;
  today_tickets_serving: number;
  today_tickets_completed: number;
  today_tickets_skipped: number;
  today_tickets_cancelled: number;
  doctors_today: DoctorQueueSummary[];
}

export type ReportingPeriod = 'today' | 'week' | 'month' | 'year' | 'custom' | 'all';

export interface DoctorPerformanceSummary {
  completed_today: number;
  completed_this_week: number;
  completed_this_month: number;
  completed_this_year: number;
  completed_all_time: number;
  completed_in_selected_range: number;
  legacy_unattributed_completed_count: number;
  total_shifts: number;
  active_shifts: number;
  finished_shifts: number;
}

export interface DoctorPerformanceItem {
  doctor_id: number;
  doctor_name: string;
  specialization_id?: number | null;
  specialization_name: string;
  room_number: string | null;
  is_active: boolean;
  current_shift_status: string;
  completed_today: number;
  completed_this_week: number;
  completed_this_month: number;
  completed_this_year: number;
  completed_all_time: number;
  completed_in_selected_range: number;
  legacy_unattributed_completed_count: number;
  shifts_count: number;
  avg_shift_duration_minutes: number | null;
}

export interface DoctorShiftHistoryItem {
  queue_id: number;
  doctor_id: number;
  doctor_name: string;
  specialization_id?: number | null;
  specialization_name: string;
  room_number: string | null;
  queue_date: string;
  shift_status: 'OPEN' | 'CLOSING' | 'FINISHED';
  is_paused: boolean;
  smart_call_mode: 'MANUAL' | 'AUTOMATIC';
  started_at: string | null;
  ended_at: string | null;
  duration_seconds: number | null;
  total_tickets: number;
  completed_count: number;
  waiting_count: number;
  called_count: number;
  serving_count: number;
  skipped_count: number;
  cancelled_count: number;
}

export interface AdminDoctorPerformanceResponse {
  clinic_id: number;
  clinic_name: string;
  clinic_timezone: string;
  period: ReportingPeriod;
  date_from: string | null;
  date_to: string | null;
  generated_at: string;
  summary: DoctorPerformanceSummary;
  doctors: DoctorPerformanceItem[];
  shifts: DoctorShiftHistoryItem[];
}
