export type UserRole = 'PATIENT' | 'RECEPTIONIST' | 'ADMIN';

export interface User {
  id: number;
  clinic_id: number | null;
  full_name: string;
  phone: string;
  role: UserRole;
  is_active: boolean;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
}

export interface AccessTokenResponse {
  access_token: string;
  token_type: string;
}
