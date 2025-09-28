import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import {
  Drawer,
  List,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Typography,
  Box,
  Divider,
  Avatar,
  Chip,
  Button,
  IconButton,
  Tooltip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Alert,
} from '@mui/material';
import {
  Dashboard as DashboardIcon,
  GroupWork as SwarmIcon,
  AccountTree as StrategyIcon,
  Analytics as PerformanceIcon,
  Settings as SettingsIcon,
  SmartToy as AIIcon,
  Logout as LogoutIcon,
  AccountBalanceWallet as WalletIcon,
  Refresh as RefreshIcon,
  ContentCopy as CopyIcon,
} from '@mui/icons-material';
import { useAuth } from '../contexts/AuthContext';

const drawerWidth = 280;

const menuItems = [
  { text: 'Dashboard', icon: <DashboardIcon />, path: '/dashboard' },
  { text: 'Swarm Control', icon: <SwarmIcon />, path: '/swarm' },
  { text: 'Stake & Invest', icon: <StrategyIcon />, path: '/stake' },
  { text: 'Strategies', icon: <StrategyIcon />, path: '/strategies' },
  { text: 'Performance', icon: <PerformanceIcon />, path: '/performance' },
];

function Sidebar() {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, walletAddress, accountInfo, networkStatus, disconnectWallet, refreshAccountInfo } = useAuth();
  const [logoutDialog, setLogoutDialog] = useState(false);
  const [copied, setCopied] = useState(false);



  const handleLogout = async () => {
    try {
      await disconnectWallet();
      setLogoutDialog(false);
    } catch (error) {
      console.error('Logout error:', error);
    }
  };

  const copyAddress = () => {
    if (walletAddress) {
      navigator.clipboard.writeText(walletAddress);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const formatAddress = (address) => {
    if (!address) return '';
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  const formatAlgo = (microAlgos) => {
    if (microAlgos === null || microAlgos === undefined) return '0.00';
    // Handle BigInt from Algorand SDK
    if (typeof microAlgos === 'bigint') {
      const ONE_MILLION = 1000000n;
      const intPart = microAlgos / ONE_MILLION; // BigInt division
      const fracPart = microAlgos % ONE_MILLION; // remainder
      // Build fractional part to 6 digits then trim to 2
      const fracStr6 = fracPart.toString().padStart(6, '0');
      const fracStr2 = fracStr6.slice(0, 2);
      return `${intPart.toString()}.${fracStr2}`;
    }
    // Fallback for numbers/strings
    const n = typeof microAlgos === 'string' ? Number(microAlgos) : microAlgos;
    if (!isFinite(n)) return '0.00';
    return (n / 1_000_000).toFixed(2);
  };

  return (
    <>
      <Drawer
        variant="permanent"
        sx={{
          width: drawerWidth,
          flexShrink: 0,
          '& .MuiDrawer-paper': {
            width: drawerWidth,
            boxSizing: 'border-box',
            backgroundColor: '#0F1419',
            borderRight: '1px solid rgba(255, 255, 255, 0.1)',
            backgroundImage: 'linear-gradient(180deg, rgba(0, 229, 255, 0.05) 0%, rgba(0, 229, 255, 0.01) 100%)',
            overflow: 'hidden',
            display: 'flex',
            flexDirection: 'column',
          },
        }}
      >
        <Box sx={{ p: 3 }}>
          {/* Logo and Title */}
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
            <Avatar
              sx={{
                bgcolor: 'primary.main',
                mr: 2,
                width: 48,
                height: 48,
                background: 'linear-gradient(135deg, #00E5FF 0%, #0091EA 100%)',
              }}
            >
              <AIIcon sx={{ fontSize: 28 }} />
            </Avatar>
            <Box>
              <Typography
                variant="h5"
                sx={{
                  fontWeight: 700,
                  background: 'linear-gradient(135deg, #00E5FF 0%, #FFFFFF 100%)',
                  backgroundClip: 'text',
                  WebkitBackgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                  lineHeight: 1.2,
                }}
              >
                AlgoFi
              </Typography>
              <Typography variant="caption" color="text.secondary">
                AI Swarm Platform
              </Typography>
            </Box>
          </Box>

          {/* Wallet Info */}
          {walletAddress && (
            <Box
              sx={{
                p: 2,
                mb: 2,
                borderRadius: 2,
                bgcolor: 'rgba(0, 229, 255, 0.05)',
                border: '1px solid rgba(0, 229, 255, 0.2)',
              }}
            >
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
                <Typography variant="body2" color="text.secondary">
                  Wallet Address
                </Typography>
                <Box>
                  <Tooltip title={copied ? 'Copied!' : 'Copy Address'}>
                    <IconButton size="small" onClick={copyAddress}>
                      <CopyIcon fontSize="small" />
                    </IconButton>
                  </Tooltip>
                  <Tooltip title="Refresh Info">
                    <IconButton size="small" onClick={refreshAccountInfo}>
                      <RefreshIcon fontSize="small" />
                    </IconButton>
                  </Tooltip>
                </Box>
              </Box>
              <Typography variant="body2" fontWeight={600} color="primary.main">
                {formatAddress(walletAddress)}
              </Typography>
              
              {accountInfo && (
                <Box sx={{ mt: 1 }}>
                  <Typography variant="body2" color="text.secondary">
                    Balance: {formatAlgo(accountInfo.amount)} ALGO
                  </Typography>
                </Box>
              )}
            </Box>
          )}

          {/* Status Indicator */}
          <Box sx={{ mb: 3 }}>
            <Chip
              icon={<Box sx={{ 
                width: 8, 
                height: 8, 
                borderRadius: '50%', 
                bgcolor: 'success.main',
                animation: 'pulse 2s infinite',
                '@keyframes pulse': {
                  '0%': { opacity: 1 },
                  '50%': { opacity: 0.5 },
                  '100%': { opacity: 1 },
                },
              }} />}
              label="Connected to Algorand"
              variant="outlined"
              size="small"
              sx={{
                color: 'success.main',
                borderColor: 'success.main',
                fontSize: '0.75rem',
              }}
            />
          </Box>
        </Box>

        <Divider sx={{ borderColor: 'rgba(255, 255, 255, 0.1)' }} />

        {/* Navigation Menu */}
        <List sx={{ px: 2, py: 1, flex: 1, overflow: 'hidden' }}>
          {menuItems.map((item) => {
            const isActive = location.pathname === item.path || 
              (location.pathname === '/' && item.path === '/dashboard');
            
            return (
              <ListItem key={item.text} disablePadding sx={{ mb: 0.5 }}>
                <ListItemButton
                  onClick={() => navigate(item.path)}
                  sx={{
                    borderRadius: 2,
                    py: 1.5,
                    px: 2,
                    backgroundColor: isActive ? 'rgba(0, 229, 255, 0.1)' : 'transparent',
                    border: isActive ? '1px solid rgba(0, 229, 255, 0.3)' : '1px solid transparent',
                    '&:hover': {
                      backgroundColor: 'rgba(0, 229, 255, 0.05)',
                      border: '1px solid rgba(0, 229, 255, 0.2)',
                    },
                    transition: 'all 0.2s ease-in-out',
                  }}
                >
                  <ListItemIcon
                    sx={{
                      color: isActive ? 'primary.main' : 'text.secondary',
                      minWidth: 40,
                    }}
                  >
                    {item.icon}
                  </ListItemIcon>
                  <ListItemText
                    primary={item.text}
                    sx={{
                      '& .MuiListItemText-primary': {
                        fontWeight: isActive ? 600 : 400,
                        color: isActive ? 'primary.main' : 'text.primary',
                      },
                    }}
                  />
                </ListItemButton>
              </ListItem>
            );
          })}
        </List>

        {/* Bottom Section */}
        <Box sx={{ mt: 'auto', p: 3 }}>

          {/* Debug: Clear Wallet Session (Development Only) */}
          {process.env.NODE_ENV === 'development' && (
            <Button
              fullWidth
              variant="outlined"
              size="small"
              onClick={async () => {
                const { clearWalletSession } = await import('../utils/algorand');
                await clearWalletSession();
                console.log('Wallet session cleared manually');
              }}
              sx={{
                mb: 1,
                fontSize: '0.75rem',
                borderColor: 'rgba(255, 193, 7, 0.5)',
                color: 'warning.main',
                '&:hover': {
                  borderColor: 'warning.main',
                  backgroundColor: 'rgba(255, 193, 7, 0.1)',
                },
              }}
            >
              🔧 Clear Wallet Session
            </Button>
          )}

          {/* Logout Button */}
          <Button
            fullWidth
            variant="outlined"
            startIcon={<LogoutIcon />}
            onClick={() => setLogoutDialog(true)}
            sx={{
              borderColor: 'rgba(255, 255, 255, 0.3)',
              color: 'text.secondary',
              '&:hover': {
                borderColor: 'error.main',
                backgroundColor: 'rgba(255, 82, 82, 0.1)',
                color: 'error.main',
              },
            }}
          >
            Log Out
          </Button>
        </Box>
      </Drawer>

      {/* Logout Confirmation Dialog */}
      <Dialog open={logoutDialog} onClose={() => setLogoutDialog(false)}>
  <DialogTitle>Log Out</DialogTitle>
        <DialogContent>
          <Typography>
            Are you sure you want to disconnect your wallet?
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setLogoutDialog(false)}>Cancel</Button>
          <Button onClick={handleLogout} color="error" variant="contained">
            Log Out
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
}

export default Sidebar;