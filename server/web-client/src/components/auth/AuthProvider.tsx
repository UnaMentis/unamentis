'use client';

/**
 * Auth Context Provider
 *
 * Provides authentication state and methods to the component tree.
 * Handles token management, user state, and auth persistence.
 */

import {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  useMemo,
  type ReactNode,
} from 'react';
import type { AuthContextValue, AuthState, User, TokenPair } from '@/types';
import {
  login as apiLogin,
  logout as apiLogout,
  register as apiRegister,
  getCurrentUser,
  tokenManager,
} from '@/lib/api';

// Initial auth state
const initialState: AuthState = {
  isAuthenticated: false,
  isLoading: true,
  user: null,
  error: null,
};

// Create context
const AuthContext = createContext<AuthContextValue | null>(null);

interface AuthProviderProps {
  children: ReactNode;
}

/**
 * Auth Provider component that wraps the application.
 */
export function AuthProvider({ children }: AuthProviderProps) {
  const [state, setState] = useState<AuthState>(initialState);

  /**
   * Update auth state helper.
   */
  const updateState = useCallback((updates: Partial<AuthState>) => {
    setState((prev) => ({ ...prev, ...updates }));
  }, []);

  /**
   * Set user and authenticated state.
   */
  const setUser = useCallback(
    (user: User | null) => {
      updateState({
        user,
        isAuthenticated: user !== null,
        isLoading: false,
        error: null,
      });
    },
    [updateState]
  );

  /**
   * Handle token changes from TokenManager.
   */
  const handleTokenChange = useCallback(
    (tokens: TokenPair | null) => {
      if (!tokens) {
        // Tokens cleared - user logged out
        setUser(null);
      }
      // If tokens set, we'll fetch user separately
    },
    [setUser]
  );

  /**
   * Initialize auth state on mount.
   */
  useEffect(() => {
    // Set up token change listener
    tokenManager.setOnTokenChange(handleTokenChange);

    // Check if we have tokens and try to restore session
    async function initializeAuth() {
      if (!tokenManager.hasTokens()) {
        updateState({ isLoading: false });
        return;
      }

      try {
        // Validate tokens by fetching current user
        const { user } = await getCurrentUser();
        setUser(user);
      } catch {
        // Token invalid - clear and show logged out state
        tokenManager.clear();
        updateState({ isLoading: false });
      }
    }

    initializeAuth();
  }, [handleTokenChange, setUser, updateState]);

  /**
   * Login with email and password.
   */
  const login = useCallback(
    async (email: string, password: string): Promise<void> => {
      updateState({ isLoading: true, error: null });

      try {
        const response = await apiLogin(email, password);
        setUser(response.user);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Login failed';
        updateState({ isLoading: false, error: message });
        throw error;
      }
    },
    [setUser, updateState]
  );

  /**
   * Register a new account.
   */
  const register = useCallback(
    async (
      email: string,
      password: string,
      displayName: string,
      ageAttestation: boolean,
      acceptedPoliciesVersion: string
    ): Promise<void> => {
      updateState({ isLoading: true, error: null });

      try {
        const response = await apiRegister(
          email,
          password,
          displayName,
          ageAttestation,
          acceptedPoliciesVersion
        );
        setUser(response.user);
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Registration failed';
        updateState({ isLoading: false, error: message });
        throw error;
      }
    },
    [setUser, updateState]
  );

  /**
   * Logout and clear session.
   */
  const logout = useCallback(async (): Promise<void> => {
    updateState({ isLoading: true, error: null });

    try {
      await apiLogout();
    } finally {
      // Always clear local state even if API call fails
      setUser(null);
    }
  }, [setUser, updateState]);

  /**
   * Manually refresh the access token.
   */
  const refreshToken = useCallback(async (): Promise<void> => {
    try {
      await tokenManager.getValidToken();
    } catch {
      // Token refresh failed - logout
      setUser(null);
    }
  }, [setUser]);

  // Memoize context value
  const contextValue = useMemo<AuthContextValue>(
    () => ({
      ...state,
      login,
      register,
      logout,
      refreshToken,
    }),
    [state, login, register, logout, refreshToken]
  );

  return <AuthContext.Provider value={contextValue}>{children}</AuthContext.Provider>;
}

/**
 * Hook to access auth context.
 *
 * @throws Error if used outside AuthProvider
 */
export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }

  return context;
}

/**
 * Hook to check if user is authenticated.
 * Returns loading state while checking.
 */
export function useIsAuthenticated(): {
  isAuthenticated: boolean;
  isLoading: boolean;
} {
  const { isAuthenticated, isLoading } = useAuth();
  return { isAuthenticated, isLoading };
}

/**
 * Hook to get the current user.
 * Returns null while loading or if not authenticated.
 */
export function useCurrentUser(): User | null {
  const { user } = useAuth();
  return user;
}
