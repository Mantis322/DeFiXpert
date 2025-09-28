import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import { Box, CircularProgress } from '@mui/material';
import { AuthProvider, useAuth } from './contexts/AuthContext';

import Sidebar from './components/Sidebar';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import SwarmControl from './pages/SwarmControl';
import PerformanceAnalytics from './pages/PerformanceAnalytics';
import About from './pages/About';
import Strategies from './pages/Strategies';
import StakePage from './pages/StakePage';

// Dark theme configuration
const darkTheme = createTheme({
  palette: {
    mode: 'dark',
    primary: {
      main: '#00E5FF', // Algorand cyan
      light: '#4AEAFF',
      dark: '#00B2CC',
    },
    secondary: {
      main: '#FF4081', // Accent pink
      light: '#FF79B0',
      dark: '#C60055',
    },
    background: {
      default: '#0A0E1A',
      paper: '#1A1F2E',
    },
    text: {
      primary: '#FFFFFF',
      secondary: '#B0B7C3',
    },
    success: {
      main: '#00C853',
    },
    warning: {
      main: '#FFB300',
    },
    error: {
      main: '#FF5252',
    },
  },
  components: {
    MuiCard: {
      styleOverrides: {
        root: {
          backgroundImage: 'linear-gradient(135deg, rgba(0, 229, 255, 0.05) 0%, rgba(26, 31, 46, 0.8) 100%)',
          backdropFilter: 'blur(10px)',
          border: '1px solid rgba(0, 229, 255, 0.2)',
        },
      },
    },
    MuiButton: {
      styleOverrides: {
        root: {
          textTransform: 'none',
          borderRadius: 8,
          fontWeight: 600,
          fontSize: '0.9rem',
        },
        contained: {
          boxShadow: '0 4px 20px rgba(0, 229, 255, 0.3)',
          '&:hover': {
            boxShadow: '0 6px 30px rgba(0, 229, 255, 0.4)',
          },
        },
      },
    },
  },
});

// Protected Route Component
function ProtectedRoute({ children }) {
  const { isConnected, loading } = useAuth();

  if (loading) {
    return (
      <Box
        sx={{
          height: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          bgcolor: '#0F1419',
        }}
      >
        <CircularProgress />
      </Box>
    );
  }

  if (!isConnected) {
    return <Navigate to="/login" replace />;
  }

  return children;
}

// Main App Layout
function AppLayout() {
  const { isConnected } = useAuth();

  return (
    <Routes>
      <Route path="/login" element={isConnected ? <Navigate to="/dashboard" replace /> : <Login />} />
      <Route
        path="/*"
        element={
          isConnected ? (
            <Box sx={{ display: 'flex', minHeight: '100vh' }}>
              <Sidebar />
              <Box component="main" sx={{ flexGrow: 1, p: 3, ml: '280px' }}>
                <Routes>
                  <Route path="/" element={<Navigate to="/dashboard" replace />} />
                  <Route path="/dashboard" element={<Dashboard />} />
                  <Route path="/swarm" element={<SwarmControl />} />
                  <Route path="/strategies" element={<Strategies />} />
                  <Route path="/performance" element={<PerformanceAnalytics />} />
                  <Route path="/stake" element={<StakePage />} />
                </Routes>
              </Box>
            </Box>
          ) : (
            <Navigate to="/login" replace />
          )
        }
      />
    </Routes>
  );
}

function App() {
  return (
    <ThemeProvider theme={darkTheme}>
      <CssBaseline />
      <Router>
        <AuthProvider>
          <AppLayout />
        </AuthProvider>
      </Router>
    </ThemeProvider>
  );
}

export default App;