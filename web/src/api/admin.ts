import { apiClient, API_BASE_URL, getStoredAccessToken } from './client';
import type {
  AdminAnalyticsOverview,
  AdminClinic,
  AdminDoctor,
  AdminDoctorCreatePayload,
  AdminDoctorPerformanceResponse,
  AdminDoctorUpdatePayload,
  AdminReceptionist,
  AdminReceptionistCreatePayload,
  AdminReceptionistUpdatePayload,
  AdminSpecialization,
  AdminSpecializationCreatePayload,
  AdminSpecializationUpdatePayload,
  ReportingPeriod,
} from '../types/admin';

// --- Clinic ---
export async function getAdminClinicApi(): Promise<AdminClinic> {
  return apiClient<AdminClinic>('/api/admin/clinic');
}

export async function updateAdminClinicApi(
  name: string,
  smartCallTimeoutSeconds?: number
): Promise<AdminClinic> {
  const payload: { name: string; smart_call_timeout_seconds?: number } = { name };
  if (smartCallTimeoutSeconds !== undefined) {
    payload.smart_call_timeout_seconds = smartCallTimeoutSeconds;
  }
  return apiClient<AdminClinic>('/api/admin/clinic', {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

// --- Specializations ---
export async function listAdminSpecializationsApi(): Promise<AdminSpecialization[]> {
  return apiClient<AdminSpecialization[]>('/api/admin/specializations');
}

export async function createAdminSpecializationApi(
  payload: AdminSpecializationCreatePayload
): Promise<AdminSpecialization> {
  return apiClient<AdminSpecialization>('/api/admin/specializations', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateAdminSpecializationApi(
  id: number,
  payload: AdminSpecializationUpdatePayload
): Promise<AdminSpecialization> {
  return apiClient<AdminSpecialization>(`/api/admin/specializations/${id}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

// --- Doctors ---
export async function listAdminDoctorsApi(): Promise<AdminDoctor[]> {
  return apiClient<AdminDoctor[]>('/api/admin/doctors');
}

export async function createAdminDoctorApi(
  payload: AdminDoctorCreatePayload
): Promise<AdminDoctor> {
  return apiClient<AdminDoctor>('/api/admin/doctors', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateAdminDoctorApi(
  id: number,
  payload: AdminDoctorUpdatePayload
): Promise<AdminDoctor> {
  return apiClient<AdminDoctor>(`/api/admin/doctors/${id}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

// --- Receptionists ---
export async function listAdminReceptionistsApi(): Promise<AdminReceptionist[]> {
  return apiClient<AdminReceptionist[]>('/api/admin/receptionists');
}

export async function createAdminReceptionistApi(
  payload: AdminReceptionistCreatePayload
): Promise<AdminReceptionist> {
  return apiClient<AdminReceptionist>('/api/admin/receptionists', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function updateAdminReceptionistApi(
  id: number,
  payload: AdminReceptionistUpdatePayload
): Promise<AdminReceptionist> {
  return apiClient<AdminReceptionist>(`/api/admin/receptionists/${id}`, {
    method: 'PATCH',
    body: JSON.stringify(payload),
  });
}

// --- Analytics ---
export async function getAdminAnalyticsApi(): Promise<AdminAnalyticsOverview> {
  return apiClient<AdminAnalyticsOverview>('/api/admin/analytics/overview');
}

export interface DoctorPerformanceFilters {
  doctor_id?: number;
  specialization_id?: number;
  period?: ReportingPeriod;
  date_from?: string;
  date_to?: string;
}

function buildPerformanceQueryString(filters: DoctorPerformanceFilters): string {
  const params = new URLSearchParams();
  if (filters.doctor_id !== undefined) params.set('doctor_id', String(filters.doctor_id));
  if (filters.specialization_id !== undefined) {
    params.set('specialization_id', String(filters.specialization_id));
  }
  if (filters.period) params.set('period', filters.period);
  if (filters.date_from) params.set('date_from', filters.date_from);
  if (filters.date_to) params.set('date_to', filters.date_to);
  const qs = params.toString();
  return qs ? `?${qs}` : '';
}

export async function getAdminDoctorPerformanceApi(
  filters: DoctorPerformanceFilters
): Promise<AdminDoctorPerformanceResponse> {
  const qs = buildPerformanceQueryString(filters);
  return apiClient<AdminDoctorPerformanceResponse>(`/api/admin/doctors/performance${qs}`);
}

export async function exportAdminDoctorPerformanceCsvApi(
  filters: DoctorPerformanceFilters
): Promise<void> {
  const qs = buildPerformanceQueryString(filters);
  const token = getStoredAccessToken();
  const headers: Record<string, string> = {};
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  const response = await fetch(`${API_BASE_URL}/api/admin/doctors/performance/export${qs}`, {
    method: 'GET',
    headers,
  });
  if (!response.ok) {
    throw new Error(`Export failed (${response.status})`);
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = 'doctor-performance-history.csv';
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
  URL.revokeObjectURL(url);
}
