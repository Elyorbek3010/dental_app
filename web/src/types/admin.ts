export interface AdminClinic {
  id: number;
  name: string;
  smart_call_timeout_seconds: number;
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
