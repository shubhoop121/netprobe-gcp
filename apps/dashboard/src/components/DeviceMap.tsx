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

export default function DeviceMap() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [connections, setConnections] = useState<DeviceConnection[]>([]);

  // Fetch data from Flask backend
  useEffect(() => {
    const fetchData = async () => {
      try {
        const resDevices = await axios.get('/api/v1/devices');
        const resConnections = await axios.get('/api/v1/logs/connections'); // Use the new v1 path
        setDevices(resDevices.data);
        setConnections(resConnections.data);
      } catch (err) {
        console.error('Error fetching device data:', err);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 10000); // refresh every 10 seconds
    return () => clearInterval(interval);
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
