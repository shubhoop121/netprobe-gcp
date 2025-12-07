import { useEffect, useState } from 'react';
import { FaExclamationTriangle, FaBan, FaCheckCircle } from 'react-icons/fa'; // Added FaCheckCircle
import axios from 'axios';
import './LiveAlertFeed.css';

// Define alert type
interface Alert {
  id: string;
  ts: string;
  severity: number | string;
  message: string;
  signature?: string;
  source_ip: string;
}

// Severity config
const severityConfig: Record<number, { icon: string; bg: string; label: string }> = {
  1: { icon: 'icon-high', bg: 'bg-high', label: 'High Severity Alert' },
  2: { icon: 'icon-medium', bg: 'bg-medium', label: 'Medium Severity Alert' },
  3: { icon: 'icon-low', bg: 'bg-low', label: 'Low Severity Alert' }
};

export default function LiveAlertFeed() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [blockingIp, setBlockingIp] = useState<string | null>(null);
  // NEW: Keep track of IPs blocked during this session
  const [blockedHistory, setBlockedHistory] = useState<Set<string>>(new Set());

  const handleBlockIp = async (ip: string) => {
    if (!ip || ip === 'Unknown') return;
    if (!confirm(`Are you sure you want to block IP: ${ip}?`)) return;

    setBlockingIp(ip);
    try {
      await axios.post('/api/v1/actions/block-ip', {
        ip: ip,
        reason: 'Blocked via Live Alert Feed',
        user: 'current-user'
      });
      
      // NEW: Add to local blocked history on success
      setBlockedHistory(prev => new Set(prev).add(ip));
      
      alert(`Success: IP ${ip} has been blocked.`);
    } catch (err: any) {
      console.error('Block IP failed', err);
      const errMsg = err.response?.data?.error || err.message;
      alert(`Failed to block IP: ${errMsg}`);
    } finally {
      setBlockingIp(null);
    }
  };

  useEffect(() => {
    const fetchAlerts = async () => {
      try {
        const res = await axios.get('/api/v1/logs/alerts');
        const raw = res.data && (res.data.logs ?? res.data);
        const arr = Array.isArray(raw) ? raw : [];

        const data = arr.map((item: any, i: number) => ({
          id: item.id?.toString() ?? i.toString(),
          ts: item.created_at ?? item.ts ?? item.time ?? '',
          severity: (() => {
            const s = item.severity ?? item.sev ?? item.level;
            const n = Number(s);
            return Number.isFinite(n) && (n === 1 || n === 2 || n === 3) ? n : 3;
          })(),
          message: item.signature ?? item.message ?? 'No details available',
          signature: item.signature,
          source_ip: item.source_ip ?? item.src_ip ?? item.ip ?? 'Unknown' 
        })) as Alert[];

        setAlerts(data.slice(0, 20));
      } catch (err) {
        console.error('Error fetching alerts:', err);
      }
    };

    fetchAlerts();
    const interval = setInterval(fetchAlerts, 5000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="border-2 border-gray-900 rounded-lg bg-white h-full flex flex-col">
      <div className="border-b-2 border-gray-900 px-6 py-4">
        <h2 className="text-xl font-bold">Live Alert Feed</h2>
      </div>

      <div className="alert-feed-container flex-1 overflow-y-auto p-2">
        {alerts.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">No alerts at this time</div>
        ) : (
          alerts.map((alert) => {
            const sev = Number(alert.severity) || 3;
            const config = severityConfig[sev] ?? severityConfig[3];
            
            // NEW: Check if this IP was just blocked
            const isBlocked = blockedHistory.has(alert.source_ip);

            return (
              <div key={alert.id} className={`alert-row ${config.bg} mb-2 p-3 rounded flex items-center justify-between`}>
                <div className="flex items-center gap-3">
                  <FaExclamationTriangle className={`alert-icon ${config.icon} text-lg`} />
                  <div className="alert-text">
                    <p className="alert-title font-bold text-sm">{config.label}</p>
                    <p className="alert-message text-sm">{alert.message}</p>
                    <div className="flex gap-2 text-xs text-gray-600 mt-1">
                      {alert.ts && <span>{alert.ts}</span>}
                      {alert.source_ip && <span className="font-mono bg-gray-200 px-1 rounded">Src: {alert.source_ip}</span>}
                    </div>
                  </div>
                </div>
                
                {/* NEW: Conditional Button Rendering */}
                {isBlocked ? (
                  <button disabled className="ml-4 px-3 py-1 bg-gray-400 text-white text-xs font-bold rounded shadow flex items-center gap-1 cursor-not-allowed">
                    <FaCheckCircle /> Blocked
                  </button>
                ) : (
                  <button 
                    onClick={() => handleBlockIp(alert.source_ip)}
                    disabled={blockingIp === alert.source_ip}
                    className="ml-4 px-3 py-1 bg-red-600 hover:bg-red-700 text-white text-xs font-bold rounded shadow flex items-center gap-1 transition-colors disabled:opacity-50"
                  >
                    <FaBan />
                    {blockingIp === alert.source_ip ? '...' : 'Block'}
                  </button>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}