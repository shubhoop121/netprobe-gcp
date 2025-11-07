import { useEffect, useState } from 'react';
import { FaExclamationTriangle } from 'react-icons/fa';
import axios from 'axios';

// Define alert type
interface Alert {
  id: string;
  ts: string;
  severity: 'high' | 'medium' | 'low' | 'info';
  message: string;
  signature?: string;
}

const severityConfig = {
  high: {
    icon: 'text-red-600',
    bg: 'bg-red-50',
    label: 'High Severity Alert'
  },
  medium: {
    icon: 'text-orange-600',
    bg: 'bg-orange-50',
    label: 'Medium Severity Alert'
  },
  low: {
    icon: 'text-yellow-600',
    bg: 'bg-yellow-50',
    label: 'Low Severity Alert'
  },
  info: {
    icon: 'text-blue-600',
    bg: 'bg-blue-50',
    label: 'Info Alert'
  }
};

export default function LiveAlertFeed() {
  const [alerts, setAlerts] = useState<Alert[]>([]);

  // Fetch alerts from Flask API
  useEffect(() => {
    const fetchAlerts = async () => {
      try {
        const res = await axios.get(`${import.meta.env.VITE_API_URL}/alerts/latest`);
        // Normalize backend data if necessary
        const data = (res.data as unknown as Alert[]).map((item, i) => ({
          id: item.id || i.toString(),
          ts: item.ts || '',
          severity: item.severity || 'info',
          message: item.signature || item.message || 'No details available',
        }));
        setAlerts(data);
      } catch (err) {
        console.error('Error fetching alerts:', err);
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
      <div className="divide-y-2 divide-gray-900">
        {alerts.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">
            No alerts at this time
          </div>
        ) : (
          alerts.map((alert) => {
            const config = severityConfig[alert.severity];
            return (
              <div
                key={alert.id}
                className={`px-6 py-4 flex items-center gap-4 hover:bg-gray-50 transition-colors ${config.bg}`}
              >
                <FaExclamationTriangle className={`w-6 h-6 ${config.icon}`} />
                <div className="flex-1">
                  <p className="font-medium text-gray-900">{config.label}</p>
                  <p className="text-sm text-gray-600 mt-1">{alert.message}</p>
                  <p className="text-xs text-gray-500 mt-1">{alert.ts}</p>
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
