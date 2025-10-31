import { useState, useEffect } from 'react';

function App() {
  const [dbStatus, setDbStatus] = useState('Checking...');

  useEffect(() => {
    fetch('/api/ping-db')
      .then(res => {
        if (!res.ok) {
          throw new Error(`HTTP error! status: ${res.status}`);
        }
        return res.json();
      })
      .then(data => {
        setDbStatus(data.message || data.error || 'Connected, but got bad data');
      })
      .catch((err) => {
        console.error("Fetch error:", err);
        setDbStatus(`Failed to connect to API: ${err.message}`);
      });
  }, []); // The empty array ensures this runs only once on component mount

  return (
    <div style={{ padding: '20px', fontFamily: 'Arial' }}>
      <h1>NetProbe Dashboard</h1>
      <p>This is the starting point for your application.</p>
      <hr />
      {/* This will now show the real status */}
      <h2>Database Status: {dbStatus}</h2>
    </div>
  );
}

export default App;