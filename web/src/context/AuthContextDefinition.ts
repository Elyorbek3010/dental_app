import { createContext } from 'react';
import type { User } from '../types/auth';

export interface AuthContextValue {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (phone: string, password: string) => Promise<void>;
  logout: () => void;
  authError: string | null;
  clearAuthError: () => void;
}

export const AuthContext = createContext<AuthContextValue | null>(null);
