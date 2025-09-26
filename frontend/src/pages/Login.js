import React, { useState } from 'react';
import {
  Box,
  Paper,
  Typography,
  Button,
  CircularProgress,
  Alert,
  Avatar,
  Container,
  Stack,
} from '@mui/material';
import {
  AccountBalanceWallet as WalletIcon,
  Security as SecurityIcon,
  Speed as SpeedIcon,
  TrendingUp as TrendingUpIcon,
} from '@mui/icons-material';
import { useAuth } from '../contexts/AuthContext';

function Login() {
  const { connectWallet, loading, error } = useAuth();
  const [connecting, setConnecting] = useState(false);

  const handleConnectWallet = async () => {
    try {
      setConnecting(true);
      await connectWallet();
    } catch (error) {
      console.error('Wallet connection failed:', error);
    } finally {
      setConnecting(false);
    }
  };

  return (
    <Container maxWidth="md">
      <Box
        sx={{
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          background: 'linear-gradient(135deg, #0F1419 0%, #1A1F2E 100%)',
        }}
      >
        <Paper
          elevation={24}
          sx={{
            p: 6,
            borderRadius: 4,
            background: 'linear-gradient(135deg, #1A1F2E 0%, #0F1419 100%)',
            border: '1px solid rgba(0, 229, 255, 0.2)',
            width: '100%',
            maxWidth: 500,
          }}
        >
          {/* Logo and Title */}
          <Box sx={{ textAlign: 'center', mb: 4 }}>
            <Avatar
              sx={{
                width: 80,
                height: 80,
                mx: 'auto',
                mb: 2,
                background: 'linear-gradient(135deg, #00E5FF 0%, #0091EA 100%)',
              }}
            >
              <WalletIcon sx={{ fontSize: 40 }} />
            </Avatar>
            <Typography
              variant="h3"
              sx={{
                fontWeight: 700,
                background: 'linear-gradient(135deg, #00E5FF 0%, #FFFFFF 100%)',
                backgroundClip: 'text',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                mb: 1,
              }}
            >
              AlgoFi
            </Typography>
            <Typography variant="h6" color="text.secondary">
              AI Swarm Trading Platform
            </Typography>
          </Box>

          {/* Features */}
          <Stack spacing={2} sx={{ mb: 4 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <Avatar sx={{ bgcolor: 'primary.main', width: 40, height: 40 }}>
                <SecurityIcon />
              </Avatar>
              <Box>
                <Typography variant="subtitle1" fontWeight={600}>
                  Secure Wallet Connection
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Safely connect with your Algorand wallet
                </Typography>
              </Box>
            </Box>

            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <Avatar sx={{ bgcolor: 'success.main', width: 40, height: 40 }}>
                <SpeedIcon />
              </Avatar>
              <Box>
                <Typography variant="subtitle1" fontWeight={600}>
                  Fast Transactions
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Thousands of transactions per second on Algorand
                </Typography>
              </Box>
            </Box>

            <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
              <Avatar sx={{ bgcolor: 'warning.main', width: 40, height: 40 }}>
                <TrendingUpIcon />
              </Avatar>
              <Box>
                <Typography variant="subtitle1" fontWeight={600}>
                  AI-Powered Trading
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  Automated strategy execution with 20 AI agents
                </Typography>
              </Box>
            </Box>
          </Stack>

          {/* Error Display */}
          {error && (
            <Alert severity="error" sx={{ mb: 3 }}>
              {error}
            </Alert>
          )}

          {/* Connect Button */}
          <Button
            fullWidth
            size="large"
            variant="contained"
            onClick={handleConnectWallet}
            disabled={connecting || loading}
            sx={{
              py: 2,
              background: 'linear-gradient(135deg, #00E5FF 0%, #0091EA 100%)',
              '&:hover': {
                background: 'linear-gradient(135deg, #0091EA 0%, #006064 100%)',
              },
            }}
          >
            {connecting || loading ? (
              <CircularProgress size={24} color="inherit" />
            ) : (
              <>
                <WalletIcon sx={{ mr: 2 }} />
                Connect with Algorand Wallet
              </>
            )}
          </Button>

          {/* Info Text */}
          <Typography
            variant="body2"
            color="text.secondary"
            sx={{ textAlign: 'center', mt: 3 }}
          >
            You can connect with Pera Wallet, MyAlgo, or other Algorand wallets.
            Your wallet address will be used as your unique identifier.
          </Typography>
        </Paper>
      </Box>
    </Container>
  );
}

export default Login;