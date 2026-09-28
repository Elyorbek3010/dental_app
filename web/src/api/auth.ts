import { apiClient, clearStoredTokens, setStoredTokens } from './client';
import type { TokenResponse, User } from '../types/auth';

export async function loginApi(phone: string, password: string): Promise<{ tokens: TokenResponse; user: User }> {
  const tokens = await apiClient<TokenResponse>(
    '/api/auth/login',
    {
      method: 'POST',
      body: JSON.stringify({ phone, password }),
    },
    false
  );

  setStoredTokens(tokens.access_token, tokens.refresh_token);

  try {
    const user = await apiClient<User>('/api/auth/me', { method: 'GET' }, false);
    return { tokens, user };
  } catch (error) {
    clearStoredTokens();
    throw error;
  }
}

export async function getCurrentUserApi(): Promise<User> {
  return apiClient<User>('/api/auth/me', { method: 'GET' });
}

export function logoutApi(): void {
  clearStoredTokens();
}
