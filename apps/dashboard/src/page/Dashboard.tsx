import DeviceMap from '../components/DeviceMap.tsx';
import LiveAlertFeed from '../components/LiveAlertFeed.tsx';
import NetworkActivity from '../components/NetworkActivity.tsx';
import './Dashboard.css';

interface DashboardProps {
  onLogout: () => void;
  dbStatus: string;
}

export default function Dashboard({ onLogout, dbStatus }: DashboardProps) {
  return (
    <div className="dashboard-container">
      <header className="dashboard-header">
        <div className="dashboard-header-left">
          <img
            src="/netprobe-icon.png"
            alt="NetProbe Logo"
            className="netprobe-logo"
          />
          <h1 className="dashboard-title">NetProbe Security Dashboard</h1>
        </div>

        <div className="dashboard-status">
          <div className="status-indicator">
            <span className={`status-dot ${dbStatus.includes('Fail') ? 'status-fail' : 'status-ok'}`}></span>
            <span>{dbStatus}</span>
          </div>
          <button className="logout-btn" onClick={onLogout}>Logout</button>
        </div>
      </header>


      <div className="dashboard-grid">
  
  {/* LEFT SIDE — Live Alerts takes full height */}
  <div className="dashboard-left">
    <div className='dashboard-card'>
      <LiveAlertFeed />
    </div>
  </div>

  {/* RIGHT SIDE — Network Activity on top, DeviceMap on bottom */}
  <div className="dashboard-right">
    <div className="dashboard-right-top dashboard-card">
      <NetworkActivity />
    </div>
    <div className="dashboard-right-bottom dashboard-card">
      <DeviceMap />
    </div>
  </div>

</div>

    </div>
  );
}
