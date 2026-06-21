'use client';

/**
 * Registration Form Component
 *
 * Account registration form with validation and error handling.
 */

import { useState, useCallback, type FormEvent } from 'react';
import Link from 'next/link';
import { useAuth } from './AuthProvider';
import { ApiError, POLICIES_VERSION } from '@/lib/api';

interface RegisterFormProps {
  /** Called after successful registration */
  onSuccess?: () => void;
  /** Called when user wants to switch to login */
  onSwitchToLogin?: () => void;
  /** Custom class name */
  className?: string;
}

interface FormErrors {
  displayName?: string;
  email?: string;
  password?: string;
  confirmPassword?: string;
  ageAttestation?: string;
  policyAcceptance?: string;
  general?: string;
}

// Password requirements
const MIN_PASSWORD_LENGTH = 8;

/**
 * Validate email format.
 */
function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/**
 * Validate password strength.
 */
function isStrongPassword(password: string): { valid: boolean; message?: string } {
  if (password.length < MIN_PASSWORD_LENGTH) {
    return {
      valid: false,
      message: `Password must be at least ${MIN_PASSWORD_LENGTH} characters`,
    };
  }

  if (!/[A-Z]/.test(password)) {
    return {
      valid: false,
      message: 'Password must contain at least one uppercase letter',
    };
  }

  if (!/[a-z]/.test(password)) {
    return {
      valid: false,
      message: 'Password must contain at least one lowercase letter',
    };
  }

  if (!/[0-9]/.test(password)) {
    return {
      valid: false,
      message: 'Password must contain at least one number',
    };
  }

  return { valid: true };
}

export function RegisterForm({ onSuccess, onSwitchToLogin, className = '' }: RegisterFormProps) {
  const { register, isLoading: authLoading } = useAuth();

  const [displayName, setDisplayName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [ageAttestation, setAgeAttestation] = useState(false);
  const [policyAcceptance, setPolicyAcceptance] = useState(false);
  const [errors, setErrors] = useState<FormErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  /**
   * Validate form inputs.
   */
  const validateForm = useCallback((): boolean => {
    const newErrors: FormErrors = {};

    // Display name validation
    if (!displayName.trim()) {
      newErrors.displayName = 'Display name is required';
    } else if (displayName.trim().length < 2) {
      newErrors.displayName = 'Display name must be at least 2 characters';
    }

    // Email validation
    if (!email.trim()) {
      newErrors.email = 'Email is required';
    } else if (!isValidEmail(email)) {
      newErrors.email = 'Please enter a valid email address';
    }

    // Password validation
    if (!password) {
      newErrors.password = 'Password is required';
    } else {
      const passwordCheck = isStrongPassword(password);
      if (!passwordCheck.valid) {
        newErrors.password = passwordCheck.message;
      }
    }

    // Confirm password validation
    if (!confirmPassword) {
      newErrors.confirmPassword = 'Please confirm your password';
    } else if (password !== confirmPassword) {
      newErrors.confirmPassword = 'Passwords do not match';
    }

    // Age attestation (13+). UnaMentis is not available to children under 13.
    if (!ageAttestation) {
      newErrors.ageAttestation = 'You must confirm you are at least 13 years old';
    }

    // Explicit, versioned Terms of Service + Privacy Policy acceptance.
    if (!policyAcceptance) {
      newErrors.policyAcceptance = 'You must accept the Terms of Service and Privacy Policy';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }, [displayName, email, password, confirmPassword, ageAttestation, policyAcceptance]);

  /**
   * Handle form submission.
   */
  const handleSubmit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();

      if (!validateForm()) {
        return;
      }

      setIsSubmitting(true);
      setErrors({});

      try {
        await register(email, password, displayName.trim(), ageAttestation, POLICIES_VERSION);
        onSuccess?.();
      } catch (error) {
        if (error instanceof ApiError) {
          switch (error.code) {
            case 'email_exists':
              setErrors({ email: 'An account with this email already exists' });
              break;
            case 'invalid_email':
              setErrors({ email: 'Please enter a valid email address' });
              break;
            case 'weak_password':
              setErrors({ password: 'Password is too weak' });
              break;
            case 'age_attestation_required':
              setErrors({
                ageAttestation: 'You must confirm you are at least 13 years old',
              });
              break;
            case 'policy_acceptance_required':
              setErrors({
                policyAcceptance: 'You must accept the Terms of Service and Privacy Policy',
              });
              break;
            default:
              setErrors({ general: error.message });
          }
        } else {
          setErrors({ general: 'An unexpected error occurred' });
        }
      } finally {
        setIsSubmitting(false);
      }
    },
    [displayName, email, password, ageAttestation, register, validateForm, onSuccess]
  );

  const isLoading = authLoading || isSubmitting;

  return (
    <form onSubmit={handleSubmit} className={`space-y-4 ${className}`}>
      {/* General error message */}
      {errors.general && (
        <div
          className="rounded-md bg-red-50 p-3 text-sm text-red-700 dark:bg-red-900/20 dark:text-red-400"
          role="alert"
        >
          {errors.general}
        </div>
      )}

      {/* Display name field */}
      <div>
        <label
          htmlFor="register-display-name"
          className="block text-sm font-medium text-gray-700 dark:text-gray-300"
        >
          Display Name
        </label>
        <input
          id="register-display-name"
          type="text"
          autoComplete="name"
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          disabled={isLoading}
          aria-invalid={!!errors.displayName}
          aria-describedby={errors.displayName ? 'register-display-name-error' : undefined}
          className={`mt-1 block w-full rounded-md border px-3 py-2 shadow-sm focus:ring-2 focus:ring-blue-500 focus:outline-none disabled:cursor-not-allowed disabled:bg-gray-100 dark:bg-gray-800 dark:text-white ${
            errors.displayName
              ? 'border-red-500 focus:border-red-500'
              : 'border-gray-300 focus:border-blue-500 dark:border-gray-600'
          }`}
          placeholder="Your name"
        />
        {errors.displayName && (
          <p
            id="register-display-name-error"
            className="mt-1 text-sm text-red-600 dark:text-red-400"
          >
            {errors.displayName}
          </p>
        )}
      </div>

      {/* Email field */}
      <div>
        <label
          htmlFor="register-email"
          className="block text-sm font-medium text-gray-700 dark:text-gray-300"
        >
          Email
        </label>
        <input
          id="register-email"
          type="email"
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          disabled={isLoading}
          aria-invalid={!!errors.email}
          aria-describedby={errors.email ? 'register-email-error' : undefined}
          className={`mt-1 block w-full rounded-md border px-3 py-2 shadow-sm focus:ring-2 focus:ring-blue-500 focus:outline-none disabled:cursor-not-allowed disabled:bg-gray-100 dark:bg-gray-800 dark:text-white ${
            errors.email
              ? 'border-red-500 focus:border-red-500'
              : 'border-gray-300 focus:border-blue-500 dark:border-gray-600'
          }`}
          placeholder="you@example.com"
        />
        {errors.email && (
          <p id="register-email-error" className="mt-1 text-sm text-red-600 dark:text-red-400">
            {errors.email}
          </p>
        )}
      </div>

      {/* Password field */}
      <div>
        <label
          htmlFor="register-password"
          className="block text-sm font-medium text-gray-700 dark:text-gray-300"
        >
          Password
        </label>
        <input
          id="register-password"
          type="password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          disabled={isLoading}
          aria-invalid={!!errors.password}
          aria-describedby={errors.password ? 'register-password-error' : 'register-password-hint'}
          className={`mt-1 block w-full rounded-md border px-3 py-2 shadow-sm focus:ring-2 focus:ring-blue-500 focus:outline-none disabled:cursor-not-allowed disabled:bg-gray-100 dark:bg-gray-800 dark:text-white ${
            errors.password
              ? 'border-red-500 focus:border-red-500'
              : 'border-gray-300 focus:border-blue-500 dark:border-gray-600'
          }`}
          placeholder="Create a strong password"
        />
        {errors.password ? (
          <p id="register-password-error" className="mt-1 text-sm text-red-600 dark:text-red-400">
            {errors.password}
          </p>
        ) : (
          <p id="register-password-hint" className="mt-1 text-xs text-gray-500 dark:text-gray-400">
            At least 8 characters with uppercase, lowercase, and number
          </p>
        )}
      </div>

      {/* Confirm password field */}
      <div>
        <label
          htmlFor="register-confirm-password"
          className="block text-sm font-medium text-gray-700 dark:text-gray-300"
        >
          Confirm Password
        </label>
        <input
          id="register-confirm-password"
          type="password"
          autoComplete="new-password"
          value={confirmPassword}
          onChange={(e) => setConfirmPassword(e.target.value)}
          disabled={isLoading}
          aria-invalid={!!errors.confirmPassword}
          aria-describedby={errors.confirmPassword ? 'register-confirm-password-error' : undefined}
          className={`mt-1 block w-full rounded-md border px-3 py-2 shadow-sm focus:ring-2 focus:ring-blue-500 focus:outline-none disabled:cursor-not-allowed disabled:bg-gray-100 dark:bg-gray-800 dark:text-white ${
            errors.confirmPassword
              ? 'border-red-500 focus:border-red-500'
              : 'border-gray-300 focus:border-blue-500 dark:border-gray-600'
          }`}
          placeholder="Confirm your password"
        />
        {errors.confirmPassword && (
          <p
            id="register-confirm-password-error"
            className="mt-1 text-sm text-red-600 dark:text-red-400"
          >
            {errors.confirmPassword}
          </p>
        )}
      </div>

      {/* Age attestation (13+) */}
      <div>
        <label className="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
          <input
            id="register-age-attestation"
            type="checkbox"
            checked={ageAttestation}
            onChange={(e) => setAgeAttestation(e.target.checked)}
            disabled={isLoading}
            aria-invalid={!!errors.ageAttestation}
            aria-describedby={errors.ageAttestation ? 'register-age-attestation-error' : undefined}
            className="mt-0.5 h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500 dark:border-gray-600"
          />
          <span>
            I confirm that I am at least 13 years old. UnaMentis is not available to children under
            13.
          </span>
        </label>
        {errors.ageAttestation && (
          <p
            id="register-age-attestation-error"
            className="mt-1 text-sm text-red-600 dark:text-red-400"
          >
            {errors.ageAttestation}
          </p>
        )}
      </div>

      {/* Terms of Service + Privacy Policy acceptance */}
      <div>
        <label className="flex items-start gap-2 text-sm text-gray-700 dark:text-gray-300">
          <input
            id="register-policy-acceptance"
            type="checkbox"
            checked={policyAcceptance}
            onChange={(e) => setPolicyAcceptance(e.target.checked)}
            disabled={isLoading}
            aria-invalid={!!errors.policyAcceptance}
            aria-describedby={
              errors.policyAcceptance ? 'register-policy-acceptance-error' : undefined
            }
            className="mt-0.5 h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500 dark:border-gray-600"
          />
          <span>
            I accept the{' '}
            <Link
              href="/terms"
              target="_blank"
              className="font-medium text-blue-600 hover:text-blue-500 dark:text-blue-400"
            >
              Terms of Service
            </Link>{' '}
            and{' '}
            <Link
              href="/privacy"
              target="_blank"
              className="font-medium text-blue-600 hover:text-blue-500 dark:text-blue-400"
            >
              Privacy Policy
            </Link>
            .
          </span>
        </label>
        {errors.policyAcceptance && (
          <p
            id="register-policy-acceptance-error"
            className="mt-1 text-sm text-red-600 dark:text-red-400"
          >
            {errors.policyAcceptance}
          </p>
        )}
      </div>

      {/* Submit button */}
      <button
        type="submit"
        disabled={isLoading}
        className="w-full rounded-md bg-blue-600 px-4 py-2 font-medium text-white shadow-sm hover:bg-blue-700 focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50"
      >
        {isLoading ? (
          <span className="flex items-center justify-center gap-2">
            <svg
              className="h-4 w-4 animate-spin"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            Creating account...
          </span>
        ) : (
          'Create account'
        )}
      </button>

      {/* Switch to login */}
      {onSwitchToLogin && (
        <p className="text-center text-sm text-gray-600 dark:text-gray-400">
          Already have an account?{' '}
          <button
            type="button"
            onClick={onSwitchToLogin}
            className="font-medium text-blue-600 hover:text-blue-500 dark:text-blue-400"
          >
            Sign in
          </button>
        </p>
      )}
    </form>
  );
}
