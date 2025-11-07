import DeviceMap from '../components/DeviceMap';
import LiveAlertFeed from '../components/LiveAlertFeed';
import NetworkActivity from '../components/NetworkActivity';
import './Dashboard.css';

interface DashboardProps {
  onLogout: () => void;
  dbStatus: string;
}

export default function Dashboard({ onLogout, dbStatus }: DashboardProps) {
  return (
    <div className="dashboard-container">
      <header className="dashboard-header">
        <h1 className="dashboard-title">NetProbe Security Dashboard</h1>
        <div className="dashboard-status">
          <div className="status-indicator">
            <span
              className={`status-dot ${
                dbStatus.includes('Fail') ? 'status-fail' : 'status-ok'
              }`}
            ></span>
            <span>{dbStatus}</span>
          </div>
          <button className="logout-btn" onClick={onLogout}>
            Logout
          </button>
        </div>
      </header>

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
