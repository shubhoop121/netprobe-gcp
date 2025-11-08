import { useEffect, useRef, useState } from 'react';
import axios from 'axios';

// Define your data type (replacing Supabase)
interface NetworkDataPoint {
  ts: string; // timestamp
  value: number; // could represent active connections or bandwidth
}

export default function NetworkActivity() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [data, setData] = useState<NetworkDataPoint[]>([]);

  // Fetch network activity from Flask backend
  useEffect(() => {
    const fetchData = async () => {
      try {
       const res = await axios.get('/api/v1/logs/connections'); // Use the new v1 path
        // Normalize backend response to NetworkDataPoint[]
        const parsedData = (res.data as unknown as { ts?: string; duration?: number; bytes?: number }[]).map((item, index) => ({
          ts: item.ts || `T${index}`,
          value: item.duration || item.bytes || Math.random() * 100, // use any metric available
        }));
        setData(parsedData);
      } catch (err) {
        console.error('Error fetching network data:', err);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 5000); // refresh every 5s
    return () => clearInterval(interval);
  }, []);

  // Draw the chart when data changes
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

    if (data.length === 0) {
      ctx.fillStyle = '#9CA3AF';
      ctx.font = '14px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('No network activity data', rect.width / 2, rect.height / 2);
      return;
    }

    const padding = 40;
    const chartWidth = rect.width - padding * 2;
    const chartHeight = rect.height - padding * 2;

    const values = data.map((d) => d.value);
    const maxValue = Math.max(...values, 1);
    const minValue = Math.min(...values, 0);
    const range = maxValue - minValue || 1;

    const points: [number, number][] = data.map((d, i) => {
      const x = padding + (i / (data.length - 1)) * chartWidth;
      const normalizedValue = (d.value - minValue) / range;
      const y = padding + chartHeight - normalizedValue * chartHeight;
      return [x, y];
    });

    // Draw line
    ctx.strokeStyle = '#1F2937';
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';

    ctx.beginPath();
    points.forEach((point, i) => {
      if (i === 0) ctx.moveTo(point[0], point[1]);
      else ctx.lineTo(point[0], point[1]);
    });
    ctx.stroke();

    // Fill area under line
    ctx.fillStyle = 'rgba(31, 41, 55, 0.05)';
    ctx.beginPath();
    ctx.moveTo(points[0][0], rect.height - padding);
    points.forEach((point) => ctx.lineTo(point[0], point[1]));
    ctx.lineTo(points[points.length - 1][0], rect.height - padding);
    ctx.closePath();
    ctx.fill();
  }, [data]);

  return (
    <div className="border-2 border-gray-900 rounded-lg bg-white h-full">
      <div className="border-b-2 border-gray-900 px-6 py-4">
        <h2 className="text-xl font-bold">Network Activity</h2>
      </div>
      <div className="p-6">
        <canvas
          ref={canvasRef}
          className="w-full h-48"
          style={{ width: '100%', height: '192px' }}
        />
      </div>
    </div>
  );
}
