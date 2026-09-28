import type { AccessTokenResponse } from '../types/auth';

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:8000';

const ACCESS_TOKEN_KEY = 'dental_reception_access_token';
const REFRESH_TOKEN_KEY = 'dental_reception_refresh_token';
const LANGUAGE_KEY = 'dental_reception_lang';

export function getStoredAccessToken(): string | null {
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}

export function getStoredRefreshToken(): string | null {
  return localStorage.getItem(REFRESH_TOKEN_KEY);
}

export function setStoredTokens(accessToken: string, refreshToken?: string): void {
  localStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
  if (refreshToken) {
    localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
  }
}

export function clearStoredTokens(): void {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

let isRefreshing = false;
let refreshSubscribers: ((token: string | null) => void)[] = [];

function onTokenRefreshed(newToken: string | null) {
  refreshSubscribers.forEach((callback) => callback(newToken));
  refreshSubscribers = [];
}

function addRefreshSubscriber(callback: (token: string | null) => void) {
  refreshSubscribers.push(callback);
}

export class ApiError extends Error {
  statusCode: number;
  detail: string;

  constructor(statusCode: number, detail: string) {
    super(detail);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.detail = detail;
  }
}

export async function apiClient<T>(
  endpoint: string,
  options: RequestInit = {},
  retryOn401 = true
): Promise<T> {
  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE_URL}${endpoint}`;
  const accessToken = getStoredAccessToken();
  const currentLang = localStorage.getItem(LANGUAGE_KEY) || 'uz';

  const headers = new Headers(options.headers || {});
  headers.set('Accept', 'application/json');
  if (!headers.has('Content-Type') && !(options.body instanceof FormData)) {
    headers.set('Content-Type', 'application/json');
  }
  if (!headers.has('Accept-Language')) {
    headers.set('Accept-Language', currentLang);
  }
  if (accessToken && !headers.has('Authorization')) {
    headers.set('Authorization', `Bearer ${accessToken}`);
  }

  const response = await fetch(url, {
    ...options,
    headers,
  });

  if (response.status === 401 && retryOn401) {
    const refreshToken = getStoredRefreshToken();
    if (!refreshToken) {
      clearStoredTokens();
      window.dispatchEvent(new CustomEvent('auth:expired'));
      throw new ApiError(401, 'Unauthorized');
    }

    if (!isRefreshing) {
      isRefreshing = true;
      try {
        const refreshResponse = await fetch(`${API_BASE_URL}/api/auth/refresh`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: JSON.stringify({ refresh_token: refreshToken }),
        });

        if (!refreshResponse.ok) {
          clearStoredTokens();
          isRefreshing = false;
          onTokenRefreshed(null);
          window.dispatchEvent(new CustomEvent('auth:expired'));
          throw new ApiError(401, 'Session expired');
        }

        const tokenData: AccessTokenResponse = await refreshResponse.json();
        setStoredTokens(tokenData.access_token);
        isRefreshing = false;
        onTokenRefreshed(tokenData.access_token);
      } catch (err) {
        clearStoredTokens();
        isRefreshing = false;
        onTokenRefreshed(null);
        window.dispatchEvent(new CustomEvent('auth:expired'));
        throw err;
      }
    }

    return new Promise<T>((resolve, reject) => {
      addRefreshSubscriber((newToken) => {
        if (!newToken) {
          reject(new ApiError(401, 'Session expired'));
          return;
        }
        apiClient<T>(endpoint, options, false)
          .then(resolve)
          .catch(reject);
      });
    });
  }

  if (!response.ok) {
    let errorDetail = 'Unknown error';
    try {
      const errorJson = await response.json();
      if (typeof errorJson.detail === 'string') {
        errorDetail = errorJson.detail;
      } else if (Array.isArray(errorJson.detail) && errorJson.detail.length > 0) {
        errorDetail = errorJson.detail[0]?.msg || JSON.stringify(errorJson.detail);
      } else if (errorJson.message) {
        errorDetail = errorJson.message;
      }
    } catch {
      errorDetail = response.statusText || `Request failed with status ${response.status}`;
    }

    throw new ApiError(response.status, errorDetail);
  }

  if (response.status === 204) {
    return {} as T;
  }

  const data: T = await response.json();
  return data;
}
