import { BrowserRouter, Routes, Route, Navigate, useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import Login from "./page/Login.tsx";
import Dashboard from "./page/Dashboard.tsx";

// Main App Component
export default function App() {
  const [isLoggedIn, setIsLoggedIn] = useState<boolean>(false);

  // Check login state from localStorage when app loads
  useEffect(() => {
    const token = localStorage.getItem("authToken");
    setIsLoggedIn(!!token);
  }, []);

  return (
    <BrowserRouter>
      <Routes>
        {/* Login Page */}
        <Route
          path="/"
          element={
            isLoggedIn ? (
              <Navigate to="/dashboard" replace />
            ) : (
              <LoginWrapper onLoginSuccess={() => setIsLoggedIn(true)} />
            )
          }
        />

        {/* Dashboard Page */}
        <Route
          path="/dashboard"
          element={
            isLoggedIn ? (
              <DashboardWrapper onLogout={() => setIsLoggedIn(false)} />
            ) : (
              <Navigate to="/" replace />
            )
          }
        />

        {/* Catch-all redirect */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}

// ✅ Wrapper for Login so we can use navigation inside
function LoginWrapper({ onLoginSuccess }: { onLoginSuccess: () => void }) {
  const navigate = useNavigate();

  const handleLoginSuccess = () => {
    onLoginSuccess();
    navigate("/dashboard"); // redirect after login
  };

  return <Login onLoginSuccess={handleLoginSuccess} />;
}

// ✅ Wrapper for Dashboard to handle logout and navigation
function DashboardWrapper({ onLogout }: { onLogout: () => void }) {
  const navigate = useNavigate();

  const handleLogout = () => {
    localStorage.removeItem("authToken");
    onLogout();
    navigate("/");
  };

  return <Dashboard onLogout={handleLogout} />;
}
