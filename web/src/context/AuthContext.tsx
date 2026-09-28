import React, { useEffect, useState } from 'react';
import { getCurrentUserApi, loginApi, logoutApi } from '../api/auth';
import { clearStoredTokens, getStoredAccessToken } from '../api/client';
import type { User } from '../types/auth';
import { AuthContext, type AuthContextValue } from './AuthContextDefinition';

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(() => !!getStoredAccessToken());
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    const token = getStoredAccessToken();
    if (!token) return;

    let isCancelled = false;

    getCurrentUserApi()
      .then((currentUser) => {
        if (isCancelled) return;
        if (currentUser.role === 'PATIENT') {
          clearStoredTokens();
          setUser(null);
          setAuthError('PATIENT_DENIED');
        } else {
          setUser(currentUser);
        }
      })
      .catch(() => {
        if (isCancelled) return;
        clearStoredTokens();
        setUser(null);
      })
      .finally(() => {
        if (!isCancelled) {
          setIsLoading(false);
        }
      });

    const handleExpired = () => {
      setUser(null);
      setAuthError('SESSION_EXPIRED');
    };

    window.addEventListener('auth:expired', handleExpired);
    return () => {
      isCancelled = true;
      window.removeEventListener('auth:expired', handleExpired);
    };
  }, []);

  const login = async (phone: string, password: string) => {
    setAuthError(null);
    setIsLoading(true);
    try {
      const { user: loggedInUser } = await loginApi(phone, password);
      if (loggedInUser.role === 'PATIENT') {
        clearStoredTokens();
        setUser(null);
        setAuthError('PATIENT_DENIED');
        throw new Error('PATIENT_DENIED');
      }
      setUser(loggedInUser);
      return loggedInUser;
    } catch (err: unknown) {
      if (err instanceof Error && err.message === 'PATIENT_DENIED') {
        throw err;
      }
      clearStoredTokens();
      setUser(null);
      throw err;
    } finally {
      setIsLoading(false);
    }
  };

  const logout = () => {
    logoutApi();
    setUser(null);
    setAuthError(null);
  };

  const clearAuthError = () => {
    setAuthError(null);
  };

  const value: AuthContextValue = {
    user,
    isAuthenticated: !!user && (user.role === 'RECEPTIONIST' || user.role === 'ADMIN'),
    isLoading,
    login,
    logout,
    authError,
    clearAuthError,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};
