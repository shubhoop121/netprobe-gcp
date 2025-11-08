import { useState } from 'react';
import axios from 'axios';
import {
  FaSignInAlt,
  FaEnvelope,
  FaLock,
  FaExclamationCircle
} from 'react-icons/fa';
import './Login.css';

interface LoginProps {
  onLoginSuccess: () => void;
}

export default function Login({ onLoginSuccess }: LoginProps) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isSignUp, setIsSignUp] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:8080/api';

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      // ✅ Default credentials (offline mode)
      if (email === 'admin@gmail.com' && password === 'admins') {
        localStorage.setItem('authToken', 'dev-local-token');
        onLoginSuccess();
        return;
      }

      // Otherwise, call the backend API
     const endpoint = isSignUp ? '/api/register' : '/api/login';
      const response = await axios.post(endpoint, { email, password });

      if (response.data.success) {
        if (isSignUp) {
          setError('Account created! Please sign in.');
          setIsSignUp(false);
          setPassword('');
        } else {
          if (response.data.token) {
            localStorage.setItem('authToken', response.data.token);
          }
          onLoginSuccess();
        }
      } else {
        setError(response.data.message || 'Authentication failed');
      }
    } catch (err: unknown) {
      if (axios.isAxiosError(err)) {
        setError(err.response?.data?.message || 'Server error occurred');
      } else if (err instanceof Error) {
        setError(err.message);
      } else {
        setError('An unexpected error occurred');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-container">
      <div className="login-card">
        <div className="login-header">
          <h1>
            <FaSignInAlt /> NetProbe
          </h1>
          <p>Security Dashboard</p>
        </div>

        <form onSubmit={handleSubmit} className="login-form">
          <label className="login-label">Email Address</label>
          <div className="input-group">
            <FaEnvelope />
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="login-input"
              placeholder="your@email.com"
              required
              disabled={loading}
            />
          </div>

          <label className="login-label">Password</label>
          <div className="input-group">
            <FaLock />
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="login-input"
              placeholder="••••••••"
              required
              disabled={loading}
            />
          </div>

          {error && (
            <div className="error-box">
              <FaExclamationCircle />
              <p>{error}</p>
            </div>
          )}

          <button type="submit" disabled={loading} className="signin-btn">
            {loading ? 'Processing...' : isSignUp ? 'Create Account' : 'Sign In'}
          </button>

          <div className="divider"></div>

          <div className="switch-section">
            {isSignUp ? 'Already have an account?' : "Don't have an account?"}
          </div>

          <button
            type="button"
            onClick={() => {
              setIsSignUp(!isSignUp);
              setError('');
              setPassword('');
            }}
            disabled={loading}
            className="switch-btn"
          >
            {isSignUp ? 'Sign In Instead' : 'Create New Account'}
          </button>
        </form>
      </div>
    </div>
  );
}
