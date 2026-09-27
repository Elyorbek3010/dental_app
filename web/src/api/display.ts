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

export function getPublicDisplayWsUrl(clinicId: string | number): string {
  const rawBase = (import.meta.env.VITE_API_BASE_URL as string | undefined) || 'http://127.0.0.1:8000';
  let wsProtocol = 'ws:';
  let host = '127.0.0.1:8000';
  let pathname = '';

  try {
    const defaultOrigin = typeof window !== 'undefined' && window.location?.origin
      ? window.location.origin
      : 'http://127.0.0.1:8000';
    const parsed = new URL(rawBase, defaultOrigin);
    wsProtocol = parsed.protocol === 'https:' ? 'wss:' : 'ws:';
    host = parsed.host;
    pathname = parsed.pathname.replace(/\/+$/, '');
  } catch {
    const isHttps = rawBase.startsWith('https:');
    wsProtocol = isHttps ? 'wss:' : 'ws:';
    host = rawBase.replace(/^https?:\/\//, '').replace(/\/+$/, '');
  }

  return `${wsProtocol}//${host}${pathname}/api/public/ws/clinics/${clinicId}/display`;
}
