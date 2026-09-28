import { apiClient } from './client';
import type {
  AdminAnalyticsOverview,
  AdminClinic,
  AdminDoctor,
  AdminDoctorCreatePayload,
  AdminDoctorUpdatePayload,
  AdminReceptionist,
  AdminReceptionistCreatePayload,
  AdminReceptionistUpdatePayload,
  AdminSpecialization,
  AdminSpecializationCreatePayload,
  AdminSpecializationUpdatePayload,
} from '../types/admin';

// --- Clinic ---
export async function getAdminClinicApi(): Promise<AdminClinic> {
  return apiClient<AdminClinic>('/api/admin/clinic');
}

export async function updateAdminClinicApi(name: string): Promise<AdminClinic> {
  return apiClient<AdminClinic>('/api/admin/clinic', {
    method: 'PATCH',
    body: JSON.stringify({ name }),
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
