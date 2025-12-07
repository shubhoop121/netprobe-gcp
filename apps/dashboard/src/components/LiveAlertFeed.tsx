import { useEffect, useState } from 'react';
import { FaExclamationTriangle } from 'react-icons/fa';
import axios from 'axios';
import './LiveAlertFeed.css'; // make sure this path matches where your CSS lives

// Define alert type
interface Alert {
  id: string;
  ts: string;
  // backend might return numeric severity (1/2/3) or strings; accept both
  severity: number | string;
  message: string;
  signature?: string;
}

// Severity config (1=High, 2=Medium, 3=Low)
const severityConfig: Record<number, { icon: string; bg: string; label: string }> = {
  1: { icon: 'icon-high', bg: 'bg-high', label: 'High Severity Alert' },
  2: { icon: 'icon-medium', bg: 'bg-medium', label: 'Medium Severity Alert' },
  3: { icon: 'icon-low', bg: 'bg-low', label: 'Low Severity Alert' }
};

export default function LiveAlertFeed() {
  const [alerts, setAlerts] = useState<Alert[]>([]);

  // Fetch alerts from Flask API
  useEffect(() => {
    const fetchAlerts = async () => {
      try {
        const res = await axios.get('/api/v1/logs/alerts'); // v1 path used by backend
        // backend returns { "logs": [...] }
        const raw = res.data && (res.data.logs ?? res.data);
        const arr = Array.isArray(raw) ? raw : [];

        const data = arr.map((item: any, i: number) => ({
          id: item.id?.toString() ?? i.toString(),
          ts: item.created_at ?? item.ts ?? item.time ?? '',
          // coerce severity to number (default to 3 = low)
          severity: (() => {
            const s = item.severity ?? item.sev ?? item.level;
            const n = Number(s);
            return Number.isFinite(n) && (n === 1 || n === 2 || n === 3) ? n : 3;
          })(),
          message: item.signature ?? item.message ?? 'No details available',
          signature: item.signature
        })) as Alert[];

        // keep latest 20 alerts
        setAlerts(data.slice(0, 20));
      } catch (err) {
        console.error('Error fetching alerts:', err);
        setAlerts([]);
      }
    };

    fetchAlerts();
    const interval = setInterval(fetchAlerts, 5000); // refresh every 5s
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="border-2 border-gray-900 rounded-lg bg-white h-full">
      <div className="border-b-2 border-gray-900 px-6 py-4">
        <h2 className="text-xl font-bold">Live Alert Feed</h2>
      </div>

      {/* Scrollable container */}
      <div className="alert-feed-container">
        {alerts.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">
            No alerts at this time
          </div>
        ) : (
          alerts.map((alert) => {
            // get numeric severity and config (guaranteed to exist)
            const sev = Number(alert.severity) || 3;
            const config = severityConfig[sev] ?? severityConfig[3];

            return (
              <div key={alert.id} className={`alert-row ${config.bg}`}>
                <FaExclamationTriangle className={`alert-icon ${config.icon}`} />
                <div className="alert-text">
                  <p className="alert-title">{config.label}</p>
                  <p className="alert-message">{alert.message}</p>
                  {alert.ts && <p className="alert-ts">{alert.ts}</p>}
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
