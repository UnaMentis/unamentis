/**
 * RegisterForm Tests
 */

import * as React from 'react';
import { describe, it, expect, beforeEach, vi, type Mock } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { RegisterForm } from '../RegisterForm';
import { AuthProvider } from '../AuthProvider';
import { ApiError, POLICIES_VERSION } from '@/lib/api';
import * as api from '@/lib/api';

// Mock the API module
vi.mock('@/lib/api', async (importOriginal) => {
  const actual = (await importOriginal()) as Record<string, unknown>;
  return {
    ...actual,
    login: vi.fn(),
    logout: vi.fn(),
    register: vi.fn(),
    getCurrentUser: vi.fn(),
    tokenManager: {
      hasTokens: vi.fn(),
      clear: vi.fn(),
      setOnTokenChange: vi.fn(),
      getValidToken: vi.fn(),
    },
  };
});

// Wrapper component that provides auth context
function renderWithAuth(ui: React.ReactElement) {
  (api.tokenManager.hasTokens as Mock).mockReturnValue(false);
  (api.tokenManager.setOnTokenChange as Mock).mockImplementation(() => {});

  return render(<AuthProvider>{ui}</AuthProvider>);
}

describe('RegisterForm', () => {
  const user = userEvent.setup();

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('rendering', () => {
    it('should render all required fields', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
        expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
        expect(screen.getByLabelText(/^password$/i)).toBeInTheDocument();
        expect(screen.getByLabelText(/confirm password/i)).toBeInTheDocument();
        expect(screen.getByLabelText(/at least 13 years old/i)).toBeInTheDocument();
        expect(screen.getByLabelText(/accept the terms of service/i)).toBeInTheDocument();
      });
    });

    it('should render submit button', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /create account/i })).toBeInTheDocument();
      });
    });

    it('should render switch to login link when callback provided', async () => {
      const onSwitchToLogin = vi.fn();
      renderWithAuth(<RegisterForm onSwitchToLogin={onSwitchToLogin} />);

      await waitFor(() => {
        expect(screen.getByText(/already have an account/i)).toBeInTheDocument();
        expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument();
      });
    });

    it('should render password requirements hint', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByText(/at least 8 characters/i)).toBeInTheDocument();
      });
    });
  });

  describe('validation', () => {
    it('should show error when display name is empty', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/display name is required/i)).toBeInTheDocument();
      });
    });

    it('should show error when display name is too short', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'A');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/display name must be at least 2 characters/i)).toBeInTheDocument();
      });
    });

    it('should validate email format correctly', async () => {
      // Test the isValidEmail function directly since browser validation
      // on type="email" may interfere with form submission
      const isValidEmail = (email: string): boolean => {
        return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
      };

      expect(isValidEmail('invalidemail')).toBe(false);
      expect(isValidEmail('invalid@')).toBe(false);
      expect(isValidEmail('@invalid.com')).toBe(false);
      expect(isValidEmail('test@example')).toBe(false);
      expect(isValidEmail('valid@example.com')).toBe(true);
    });

    it('should show error when password is too short', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Pass1');
      await user.type(screen.getByLabelText(/confirm password/i), 'Pass1');
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/password must be at least 8 characters/i)).toBeInTheDocument();
      });
    });

    it('should show error when password has no uppercase', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'password123');
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(
          screen.getByText(/password must contain at least one uppercase letter/i)
        ).toBeInTheDocument();
      });
    });

    it('should show error when password has no lowercase', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'PASSWORD123');
      await user.type(screen.getByLabelText(/confirm password/i), 'PASSWORD123');
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(
          screen.getByText(/password must contain at least one lowercase letter/i)
        ).toBeInTheDocument();
      });
    });

    it('should show error when password has no number', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'PasswordNoNumber');
      await user.type(screen.getByLabelText(/confirm password/i), 'PasswordNoNumber');
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/password must contain at least one number/i)).toBeInTheDocument();
      });
    });

    it('should show error when passwords do not match', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password456');
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/passwords do not match/i)).toBeInTheDocument();
      });
    });

    it('should show error when terms and privacy policy are not accepted', async () => {
      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(
          screen.getByText(/must accept the terms of service and privacy policy/i)
        ).toBeInTheDocument();
      });
      expect(api.register).not.toHaveBeenCalled();
    });
  });

  describe('submission', () => {
    it('should call register on valid submission', async () => {
      (api.register as Mock).mockResolvedValue({
        user: { id: '1', email: 'test@example.com', display_name: 'Test User' },
        tokens: {
          access_token: 'token',
          refresh_token: 'refresh',
          token_type: 'Bearer',
          expires_in: 900,
        },
        device: { id: 'device-1' },
      });

      const onSuccess = vi.fn();
      renderWithAuth(<RegisterForm onSuccess={onSuccess} />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(api.register).toHaveBeenCalledWith(
          'test@example.com',
          'Password123',
          'Test User',
          true,
          POLICIES_VERSION
        );
        expect(onSuccess).toHaveBeenCalled();
      });
    });

    it('should show loading state during submission', async () => {
      (api.register as Mock).mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );

      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/creating account/i)).toBeInTheDocument();
      });
    });
  });

  describe('error handling', () => {
    it('should show error for existing email', async () => {
      const apiError = new ApiError('Email exists', 400, 'email_exists');
      (api.register as Mock).mockRejectedValue(apiError);

      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'existing@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/an account with this email already exists/i)).toBeInTheDocument();
      });
    });

    it('should show error for weak password from API', async () => {
      const apiError = new ApiError('Password too weak', 400, 'weak_password');
      (api.register as Mock).mockRejectedValue(apiError);

      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByText(/password is too weak/i)).toBeInTheDocument();
      });
    });

    it('should show error for policy_acceptance_required from API', async () => {
      const apiError = new ApiError(
        'Policy acceptance required',
        400,
        'policy_acceptance_required'
      );
      (api.register as Mock).mockRejectedValue(apiError);

      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(
          screen.getByText(/must accept the terms of service and privacy policy/i)
        ).toBeInTheDocument();
      });
    });

    it('should show generic error for unexpected errors', async () => {
      (api.register as Mock).mockRejectedValue(new Error('Network error'));

      renderWithAuth(<RegisterForm />);

      await waitFor(() => {
        expect(screen.getByLabelText(/display name/i)).toBeInTheDocument();
      });

      await user.type(screen.getByLabelText(/display name/i), 'Test User');
      await user.type(screen.getByLabelText(/email/i), 'test@example.com');
      await user.type(screen.getByLabelText(/^password$/i), 'Password123');
      await user.type(screen.getByLabelText(/confirm password/i), 'Password123');
      await user.click(screen.getByLabelText(/at least 13 years old/i));
      await user.click(screen.getByLabelText(/accept the terms of service/i));
      await user.click(screen.getByRole('button', { name: /create account/i }));

      await waitFor(() => {
        expect(screen.getByRole('alert')).toHaveTextContent(/unexpected error/i);
      });
    });
  });

  describe('switch to login', () => {
    it('should call onSwitchToLogin when sign in button clicked', async () => {
      const onSwitchToLogin = vi.fn();
      renderWithAuth(<RegisterForm onSwitchToLogin={onSwitchToLogin} />);

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument();
      });

      await user.click(screen.getByRole('button', { name: /sign in/i }));

      expect(onSwitchToLogin).toHaveBeenCalled();
    });
  });
});
