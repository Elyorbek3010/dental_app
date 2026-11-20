import { apiClient } from './client';
import type {
  CheckInQRResponse,
  CompleteQueueTicketResponse,
  Doctor,
  QueueResponse,
  QueueTicket,
  ReceptionQueueOverview,
  SmartCallMode,
  Specialization,
  WalkInPatientCreate,
} from '../types/reception';

export async function fetchReceptionTodayQueues(): Promise<ReceptionQueueOverview[]> {
  return apiClient<ReceptionQueueOverview[]>('/api/queues/reception/today', {
    method: 'GET',
  });
}

export async function fetchSpecializations(clinicId: number): Promise<Specialization[]> {
  return apiClient<Specialization[]>(`/api/catalog/specializations?clinic_id=${clinicId}`, {
    method: 'GET',
  });
}

export async function fetchDoctors(clinicId: number, specializationId?: number): Promise<Doctor[]> {
  let url = `/api/catalog/doctors?clinic_id=${clinicId}`;
  if (specializationId) {
    url += `&specialization_id=${specializationId}`;
  }
  return apiClient<Doctor[]>(url, {
    method: 'GET',
  });
}

export async function openDoctorQueue(doctorId: number): Promise<QueueResponse> {
  return apiClient<QueueResponse>('/api/queues/open', {
    method: 'POST',
    body: JSON.stringify({ doctor_id: doctorId }),
  });
}

export async function pauseQueue(queueId: number): Promise<QueueResponse> {
  return apiClient<QueueResponse>(`/api/queues/${queueId}/pause`, {
    method: 'PATCH',
  });
}

export async function resumeQueue(queueId: number): Promise<QueueResponse> {
  return apiClient<QueueResponse>(`/api/queues/${queueId}/resume`, {
    method: 'PATCH',
  });
}

export async function fetchQueueTickets(queueId: number): Promise<QueueTicket[]> {
  return apiClient<QueueTicket[]>(`/api/queues/${queueId}/tickets`, {
    method: 'GET',
  });
}

export async function callNextPatient(queueId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/call-next`, {
    method: 'POST',
  });
}

export async function callPatient(queueId: number, ticketId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/tickets/${ticketId}/call`, {
    method: 'PATCH',
  });
}

export async function servePatient(queueId: number, ticketId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/tickets/${ticketId}/serve`, {
    method: 'PATCH',
  });
}

export async function completePatient(
  queueId: number,
  ticketId: number
): Promise<CompleteQueueTicketResponse> {
  return apiClient<CompleteQueueTicketResponse>(
    `/api/queues/${queueId}/tickets/${ticketId}/complete`,
    {
      method: 'PATCH',
    }
  );
}

export async function updateSmartCallMode(
  queueId: number,
  mode: SmartCallMode
): Promise<QueueResponse> {
  return apiClient<QueueResponse>(`/api/queues/${queueId}/smart-call-mode`, {
    method: 'PATCH',
    body: JSON.stringify({ mode }),
  });
}

export async function stopShiftAdmissions(queueId: number): Promise<QueueResponse> {
  return apiClient<QueueResponse>(`/api/queues/${queueId}/stop-admissions`, {
    method: 'PATCH',
  });
}

export async function reopenShiftAdmissions(queueId: number): Promise<QueueResponse> {
  return apiClient<QueueResponse>(`/api/queues/${queueId}/reopen-admissions`, {
    method: 'PATCH',
  });
}

export async function finishShift(queueId: number): Promise<QueueResponse> {
  return apiClient<QueueResponse>(`/api/queues/${queueId}/finish`, {
    method: 'PATCH',
  });
}

export async function skipPatient(queueId: number, ticketId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/tickets/${ticketId}/skip`, {
    method: 'PATCH',
  });
}

export async function restorePatient(queueId: number, ticketId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/tickets/${ticketId}/restore`, {
    method: 'PATCH',
  });
}

export async function cancelPatient(queueId: number, ticketId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/tickets/${ticketId}/cancel`, {
    method: 'PATCH',
  });
}

export async function manualCheckInPatient(queueId: number, ticketId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/tickets/${ticketId}/check-in`, {
    method: 'PATCH',
  });
}

export async function missTurnPatient(queueId: number, ticketId: number): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/tickets/${ticketId}/miss-turn`, {
    method: 'PATCH',
  });
}

export async function addWalkInPatient(
  queueId: number,
  data: WalkInPatientCreate
): Promise<QueueTicket> {
  return apiClient<QueueTicket>(`/api/queues/${queueId}/walk-in`, {
    method: 'POST',
    body: JSON.stringify(data),
  });
}

export async function fetchCheckInQrToken(clinicId?: number): Promise<CheckInQRResponse> {
  const url =
    clinicId !== undefined
      ? `/api/queues/check-in/qr-token?clinic_id=${clinicId}`
      : '/api/queues/check-in/qr-token';
  return apiClient<CheckInQRResponse>(url, {
    method: 'GET',
  });
}
