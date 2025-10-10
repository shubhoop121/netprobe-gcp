import React from 'react'
import ReactDOM from 'react-dom/client'
import { createBrowserRouter, RouterProvider } from 'react-router-dom'
import './styles.css'
import App from './App'
import Dashboard from './pages/Dashboard'
import Logs from './pages/Logs'
import Devices from './pages/Devices'
import Policies from './pages/Policies'
import Settings from './pages/Settings'

const router = createBrowserRouter([
  {
    path: '/',
    element: <App />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'logs', element: <Logs /> },
      { path: 'devices', element: <Devices /> },
      { path: 'policies', element: <Policies /> },
      { path: 'settings', element: <Settings /> },
    ]
  }
])

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
)