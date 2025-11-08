import { BrowserRouter, Routes, Route, Navigate, useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import Login from "./page/Login.tsx";
import Dashboard from "./page/Dashboard.tsx";

export default function App() {
  const [isLoggedIn, setIsLoggedIn] = useState<boolean>(false);
  const [dbStatus, setDbStatus] = useState<string>("Checking...");

  const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:8080/api";

  // Check login state and DB status on load
  useEffect(() => {
  const token = localStorage.getItem("authToken");
  setIsLoggedIn(!!token);

  const checkDbConnection = async () => {
    try {
      const res = await fetch(`${API_BASE}/ping-db`);
      if (!res.ok) throw new Error(`HTTP error! Status: ${res.status}`);
      const data = await res.json();
      setDbStatus(data.message || data.status || "Connected");
    } catch (err: unknown) {
      if (err instanceof Error) {
        setDbStatus(`Failed to connect: ${err.message}`);
      } else {
        setDbStatus("Failed to connect to API");
      }
    }
  };

  checkDbConnection();
}, [API_BASE]);

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
              <DashboardWrapper
                onLogout={() => setIsLoggedIn(false)}
                dbStatus={dbStatus}
              />
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

// ✅ Wrapper for Login to allow navigation
function LoginWrapper({ onLoginSuccess }: { onLoginSuccess: () => void }) {
  const navigate = useNavigate();

  const handleLoginSuccess = () => {
    onLoginSuccess();
    navigate("/dashboard");
  };

  return <Login onLoginSuccess={handleLoginSuccess} />;
}

// ✅ Wrapper for Dashboard
function DashboardWrapper({
  onLogout,
  dbStatus,
}: {
  onLogout: () => void;
  dbStatus: string;
}) {
  const navigate = useNavigate();

  const handleLogout = () => {
    localStorage.removeItem("authToken");
    onLogout();
    navigate("/");
  };

  return <Dashboard onLogout={handleLogout} dbStatus={dbStatus} />;
}
