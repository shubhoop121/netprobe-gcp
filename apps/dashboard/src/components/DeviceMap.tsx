import { useEffect, useRef, useState } from 'react';
import axios from 'axios';

// Define types locally (instead of importing from Supabase)
interface Device {
  id: string;
  name: string;
  x_position: number;
  y_position: number;
  status: 'online' | 'offline';
}

interface DeviceConnection {
  id: string;
  source_device_id: string;
  target_device_id: string;
}

function asArray<T>(maybeArray: any): T[] {
  // If it's already an array, return it.
  if (Array.isArray(maybeArray)) return maybeArray as T[];
  // If it's an object with common array keys, return the first found.
  const candidates = ['devices', 'items', 'results', 'data', 'connections', 'rows'];
  if (maybeArray && typeof maybeArray === 'object') {
    for (const k of candidates) {
      if (Array.isArray(maybeArray[k])) return maybeArray[k] as T[];
    }
  }
  // Last resort: return empty array
  return [];
}

export default function DeviceMap() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [connections, setConnections] = useState<DeviceConnection[]>([]);

    useEffect(() => {
    let cancelled = false;

    // Helper: safely coerce many possible shapes to an array
    const toArray = <T,>(val: unknown): T[] => {
      if (!val) return [];
      if (Array.isArray(val)) return val as T[];
      if (typeof val === 'object' && val !== null) {
        const o = val as Record<string, unknown>;
        const keys = ['devices', 'items', 'results', 'data', 'logs', 'connections', 'rows'];
        for (const k of keys) {
          if (Array.isArray(o[k])) return o[k] as T[];
        }
      }
      return [];
    };

    const isFingerprintArray = (v: unknown): v is Array<{ type?: string; value?: string }> =>
      Array.isArray(v) && v.every(item => typeof item === 'object' && item !== null);

    const fetchData = async () => {
      try {
        const [resDevices, resConnections] = await Promise.all([
          axios.get('/api/v1/devices'),
          axios.get('/api/v1/logs/connections'),
        ]);

        if (cancelled) return;

        // Normalize responses into arrays
        const rawDevices = toArray<Record<string, unknown>>(resDevices.data);
        const rawConnections = toArray<Record<string, unknown>>(resConnections.data);

        // Map of IP -> known device object (raw)
        const ipToKnownDevice = new Map<string, Record<string, unknown>>();
        const ipSet = new Set<string>();

        // Inspect known devices for fingerprints of type 'internal_ip'
        rawDevices.forEach((d) => {
          // try a few common fingerprint locations (flexible)
          const fingerprints =
            (d.fingerprints as unknown) ?? (d.meta && (d.meta as any).fingerprints) ?? (d['fingerprint'] as unknown);

          if (isFingerprintArray(fingerprints)) {
            (fingerprints as Array<{ type?: string; value?: string }>).forEach((fp) => {
              if (fp && fp.type === 'internal_ip' && typeof fp.value === 'string') {
                ipSet.add(fp.value);
                ipToKnownDevice.set(fp.value, d);
              }
            });
          }

          // Also handle case where device has an 'internal_ip' top-level field
          if (typeof d.internal_ip === 'string') {
            ipSet.add(d.internal_ip as string);
            ipToKnownDevice.set(d.internal_ip as string, d);
          }

          // If device has an 'addresses' array with 'internal' or similar
          if (Array.isArray(d.addresses)) {
            (d.addresses as unknown[]).forEach((a) => {
              if (typeof a === 'string') {
                ipSet.add(a);
                ipToKnownDevice.set(a, d);
              } else if (typeof a === 'object' && a !== null) {
                const addr = (a as Record<string, unknown>).ip as string | undefined;
                if (typeof addr === 'string') {
                  ipSet.add(addr);
                  ipToKnownDevice.set(addr, d);
                }
              }
            });
          }
        });

        // Collect IPs from connections logs
        rawConnections.forEach((conn) => {
          const s = (conn.source_ip ?? conn.src_ip ?? conn.source) as unknown;
          const t = (conn.destination_ip ?? conn.dst_ip ?? conn.destination) as unknown;

          if (typeof s === 'string') ipSet.add(s);
          if (typeof t === 'string') ipSet.add(t);
        });

        // Build normalized devices array of type Device (expected by your drawing code)
        const normalizedDevices: Device[] = Array.from(ipSet).map((ip) => {
          const known = ipToKnownDevice.get(ip);
          // try to reuse coordinates if present on known device (flexible field names)
          const maybeX =
            (known && (known.x_position as unknown)) ??
            (known && (known.x as unknown)) ??
            (known && (known.position && (known.position.x as unknown)));
          const maybeY =
            (known && (known.y_position as unknown)) ??
            (known && (known.y as unknown)) ??
            (known && (known.position && (known.position.y as unknown)));

          const x_position =
            typeof maybeX === 'number' ? (maybeX as number) : Math.random() * 0.8 + 0.1; // random in [0.1,0.9]
          const y_position =
            typeof maybeY === 'number' ? (maybeY as number) : Math.random() * 0.8 + 0.1;

          const name =
            (known && (known.friendly_name as unknown)) ??
            (known && (known.name as unknown)) ??
            ip;

          const status =
            (known && (known.status as unknown)) === 'online' ||
            (known && (known.state as unknown)) === 'online'
              ? 'online'
              : 'offline';

          return {
            id: ip,
            name: typeof name === 'string' ? name : ip,
            x_position,
            y_position,
            status: status === 'online' ? 'online' : 'offline',
          } as Device;
        });

        // Build normalized connections in the DeviceConnection shape (source_device_id, target_device_id)
        const normalizedConnections: DeviceConnection[] = rawConnections
          .map((c, idx) => {
            const src =
              (c.source_ip as unknown) ??
              (c.src_ip as unknown) ??
              (c.source as unknown) ??
              (c.src as unknown);
            const dst =
              (c.destination_ip as unknown) ??
              (c.dst_ip as unknown) ??
              (c.destination as unknown) ??
              (c.dst as unknown);

            if (typeof src === 'string' && typeof dst === 'string') {
              return {
                id: (c.id as string) ?? `conn-${idx}-${src}-${dst}`,
                source_device_id: src,
                target_device_id: dst,
              } as DeviceConnection;
            }

            return null;
          })
          .filter((x): x is DeviceConnection => x !== null);

        // Update state (only if component still mounted)
        if (!cancelled) {
          setDevices(normalizedDevices);
          setConnections(normalizedConnections);
        }
      } catch (err) {
        if (!cancelled) {
          // log error for debugging
          console.error('Error fetching device data:', err);
        }
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 10000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  // Draw devices and connections
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, rect.width, rect.height);

    if (devices.length === 0) {
      ctx.fillStyle = '#9CA3AF';
      ctx.font = '14px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('No devices to display', rect.width / 2, rect.height / 2);
      return;
    }

    const padding = 60;
    const chartWidth = rect.width - padding * 2;
    const chartHeight = rect.height - padding * 2;
    const devicePositions = new Map<string, [number, number]>();

    devices.forEach((device) => {
      const x = padding + (device.x_position * chartWidth);
      const y = padding + (device.y_position * chartHeight);
      devicePositions.set(device.id, [x, y]);
    });

    // Draw connections (lines)
    ctx.strokeStyle = '#9CA3AF';
    ctx.lineWidth = 2;
    connections.forEach((conn) => {
      const source = devicePositions.get(conn.source_device_id);
      const target = devicePositions.get(conn.target_device_id);
      if (source && target) {
        ctx.beginPath();
        ctx.moveTo(source[0], source[1]);
        ctx.lineTo(target[0], target[1]);
        ctx.stroke();
      }
    });

    // Draw devices (nodes)
    devices.forEach((device) => {
      const pos = devicePositions.get(device.id);
      if (!pos) return;
      const [x, y] = pos;
      const radius = 16;

      ctx.fillStyle = device.status === 'online' ? '#34D399' : '#E5E7EB';
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.fill();

      ctx.strokeStyle = '#1F2937';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.stroke();

      // Label the device
      ctx.fillStyle = '#111827';
      ctx.font = '12px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(device.name, x, y + 28);
    });
  }, [devices, connections]);

  return (
    <div className="border-2 border-gray-900 rounded-lg bg-white h-full">
      <div className="border-b-2 border-gray-900 px-6 py-4">
        <h2 className="text-xl font-bold">Device Map</h2>
      </div>
      <div className="p-6">
        <canvas
          ref={canvasRef}
          className="w-full h-64"
          style={{ width: '100%', height: '256px' }}
        />
      </div>
    </div>
  );
}
