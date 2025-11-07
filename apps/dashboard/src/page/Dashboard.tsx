import DeviceMap from '../components/DeviceMap';
import LiveAlertFeed from '../components/LiveAlertFeed';
import NetworkActivity from '../components/NetworkActivity';
import './Dashboard.css';

export default function Dashboard({ onLogout }: { onLogout: () => void }) {
  return (
    <div className="dashboard-container">
      {/* Header Section */}
      <header className="dashboard-header">
        <h1 className="dashboard-title">NetProbe Security Dashboard</h1>
        <div className="dashboard-status">
          <div className="status-indicator">
            <span className="status-dot"></span>
            <span>All Systems Operational</span>
          </div>
          <div className="user-section">
            <span className="user-dot"></span>
            <span>User</span>
          </div>
          <button className="logout-btn" onClick={onLogout}>
            Logout
          </button>
        </div>
      </header>

      {/* Dashboard Grid */}
      <div className="dashboard-grid">
        <div className="dashboard-card">
          <LiveAlertFeed />
        </div>
        <div className="dashboard-card">
          <NetworkActivity />
        </div>
        <div className="dashboard-card">
          <DeviceMap />
        </div>
      </div>
    </div>
  );
}
