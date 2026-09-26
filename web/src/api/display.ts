import type { PublicDisplayResponse } from '../types/display';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:8000';

export async function fetchPublicDisplay(clinicId: string | number): Promise<PublicDisplayResponse> {
  const url = `${API_BASE_URL}/api/public/clinics/${clinicId}/display`;
  
  const response = await fetch(url, {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
    },
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error('Clinic not found');
    }
    throw new Error('Unable to load queue information');
  }

  const data: PublicDisplayResponse = await response.json();
  return data;
}
