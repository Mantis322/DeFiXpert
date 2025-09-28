import React, { useState, useEffect } from 'react';
import { useAuth } from '../contexts/AuthContext';
import {
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Chip,
  LinearProgress,
  IconButton,
  Button,
  Alert,
  CircularProgress,
} from '@mui/material';
import {
  TrendingUp,
  TrendingDown,
  AccountBalance,
  SmartToy,
  Speed,
  PlayArrow,
  Pause,
  Refresh,
  Stop,
} from '@mui/icons-material';
import {
  LineChart,
  Line,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
} from 'recharts';

const Dashboard = () => {
  const { user, walletAddress, accountInfo, api, refreshAccountInfo } = useAuth();
  const [performance, setPerformance] = useState(null);
  const [strategies, setStrategies] = useState([]);
  const [recentTransactions, setRecentTransactions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (walletAddress) {
      loadDashboardData();
    }
  }, [walletAddress]);

  const loadDashboardData = async () => {
    try {
      setLoading(true);
      setError(null);

      // Load performance data
  const perfData = await api.getUserPerformance();
  setPerformance(perfData || null);

      // Load strategies
  const strategiesData = await api.getUserStrategies();
  setStrategies(Array.isArray(strategiesData) ? strategiesData : []);

  // Load recent transactions
  const transactionsData = await api.getUserTransactions(10);
    setRecentTransactions(Array.isArray(transactionsData) ? transactionsData : []);

    } catch (err) {
      console.error('Error loading dashboard data:', err);
      setError('Unable to connect to backend server. Please check if the server is running.');
      
      // Set empty states instead of mock data
      setPerformance({
        total_invested_algo: 0,
        current_value_algo: 0,
        total_pnl_algo: 0,
        win_rate: 0,
        total_trades: 0,
        historical_data: []
      });
      setStrategies([]);
      setRecentTransactions([]);
    } finally {
      setLoading(false);
    }
  };

  const handleRefresh = async () => {
    await refreshAccountInfo();
    await loadDashboardData();
  };

  const handleToggleStrategy = async (strategyId, isActive) => {
    try {
      // This would call API to start/stop strategy
      console.log(`${isActive ? 'Stopping' : 'Starting'} strategy ${strategyId}`);
      // await api.toggleStrategy(strategyId, !isActive);
      // await loadDashboardData();
    } catch (err) {
      console.error('Error toggling strategy:', err);
    }
  };

  if (!user || !walletAddress) {
    return (
      <Box sx={{ 
        display: 'flex', 
        alignItems: 'center', 
        justifyContent: 'center', 
        minHeight: 'calc(100vh - 100px)',
        bgcolor: '#121212' 
      }}>
        <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', p: 4 }}>
          <Typography variant="h5" sx={{ color: '#fff', textAlign: 'center' }}>
            Please connect your wallet to continue
          </Typography>
        </Card>
      </Box>
    );
  }

  if (loading) {
    return (
      <Box sx={{ 
        display: 'flex', 
        alignItems: 'center', 
        justifyContent: 'center', 
        minHeight: 'calc(100vh - 100px)',
        bgcolor: '#121212' 
      }}>
        <CircularProgress size={80} sx={{ color: '#00E5FF' }} />
      </Box>
    );
  }

  const formatCurrency = (amount) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
    }).format(amount);
  };

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString();
  };

  // BigInt-safe formatter for microAlgos -> ALGO string with 6 decimals
  const formatMicroAlgo = (microAlgos) => {
    if (microAlgos === null || microAlgos === undefined) return '0.000000';
    if (typeof microAlgos === 'bigint') {
      const ONE_MILLION = 1000000n;
      const intPart = microAlgos / ONE_MILLION;
      const fracPart = microAlgos % ONE_MILLION;
      const fracStr6 = fracPart.toString().padStart(6, '0');
      return `${intPart.toString()}.${fracStr6}`;
    }
    const n = typeof microAlgos === 'string' ? Number(microAlgos) : microAlgos;
    if (!isFinite(n)) return '0.000000';
    return (n / 1_000_000).toFixed(6);
  };

  const formatAlgo = (amount) => {
    const n = typeof amount === 'string' ? Number(amount) : amount;
    if (!isFinite(n)) return '0.00 ALGO';
    return `${n.toFixed(2)} ALGO`;
  };

  const formatNumber6 = (val) => {
    const n = typeof val === 'string' ? Number(val) : val;
    if (!isFinite(n)) return '0.000000';
    return n.toFixed(6);
  };

  const getStatusColor = (status) => {
    return status ? '#00C853' : '#FF9800';
  };

  const getStatusText = (status) => {
    return status ? 'Active' : 'Inactive';
  };

  // Calculate active strategies count
  const activeStrategiesCount = (Array.isArray(strategies) ? strategies : []).filter(s => s.is_active).length;

  // Chart data from performance
  const chartData = performance?.historical_data ? 
    performance.historical_data.map(d => ({
      time: formatDate(d.date),
      profit: d.total_value_algo - (performance.historical_data[0]?.total_value_algo || 0),
      value: d.total_value_algo
    })) : [];

  // Strategy distribution for pie chart
  const strategyDistribution = (Array.isArray(strategies) ? strategies : []).map((strategy, index) => ({
    name: strategy.strategy_name,
    value: strategy.allocated_amount,
    color: ['#00E5FF', '#00C853', '#FF6D00', '#9C27B0'][index % 4]
  }));

  return (
    <Box sx={{ flexGrow: 1, p: 3, bgcolor: '#121212', minHeight: '100vh' }}>
      {/* Header */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Box>
          <Typography variant="h4" component="h1" sx={{ color: '#fff' }}>
            AlgoFi Dashboard
          </Typography>
          <Typography variant="body1" sx={{ color: '#bbb' }}>
            Welcome back! Here's your trading overview.
          </Typography>
        </Box>
        <Button
          variant="contained"
          startIcon={<Refresh />}
          onClick={handleRefresh}
          sx={{
            bgcolor: '#00E5FF',
            '&:hover': { bgcolor: '#00B9D4' },
          }}
        >
          Refresh Data
        </Button>
      </Box>

      {/* Error Alert */}
      {error && (
        <Alert severity="warning" sx={{ mb: 3, bgcolor: '#2e2e2e', color: '#fff' }}>
          {error}
        </Alert>
      )}

      {/* Account Info */}
      <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2, mb: 3 }}>
        <CardContent>
          <Typography variant="h6" sx={{ color: '#fff', mb: 2 }}>
            Wallet Information
          </Typography>
          <Grid container spacing={3}>
            <Grid item xs={12} md={4}>
              <Typography variant="body2" sx={{ color: '#bbb' }}>
                Wallet Address
              </Typography>
              <Typography 
                variant="body1" 
                sx={{ color: '#fff', fontFamily: 'monospace', fontSize: '0.9rem', wordBreak: 'break-all' }}
              >
                {walletAddress}
              </Typography>
            </Grid>
            <Grid item xs={12} md={4}>
              <Typography variant="body2" sx={{ color: '#bbb' }}>
                ALGO Balance
              </Typography>
              <Typography variant="h6" sx={{ color: '#00E5FF', fontWeight: 'bold' }}>
                {accountInfo ? formatMicroAlgo(accountInfo.amount) : '0.000000'} ALGO
              </Typography>
            </Grid>
            <Grid item xs={12} md={4}>
              <Typography variant="body2" sx={{ color: '#bbb' }}>
                Member Since
              </Typography>
              <Typography variant="body1" sx={{ color: '#fff' }}>
                {user.created_at ? formatDate(user.created_at) : 'N/A'}
              </Typography>
            </Grid>
          </Grid>
        </CardContent>
      </Card>

      {/* Summary Cards */}
      {performance && (
        <Grid container spacing={3} sx={{ mb: 3 }}>
          <Grid item xs={12} sm={6} md={3}>
            <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2 }}>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                  <AccountBalance sx={{ color: '#00E5FF', mr: 1 }} />
                  <Typography variant="h6" sx={{ color: '#fff' }}>
                    Total Invested
                  </Typography>
                </Box>
                <Typography variant="h4" sx={{ color: '#00E5FF', fontWeight: 'bold' }}>
                  {formatAlgo(performance.total_invested_algo)}
                </Typography>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} sm={6} md={3}>
            <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2 }}>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                  <AccountBalance sx={{ color: '#FF6D00', mr: 1 }} />
                  <Typography variant="h6" sx={{ color: '#fff' }}>
                    Current Value
                  </Typography>
                </Box>
                <Typography variant="h4" sx={{ color: '#FF6D00', fontWeight: 'bold' }}>
                  {formatAlgo(performance.current_value_algo)}
                </Typography>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} sm={6} md={3}>
            <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2 }}>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                  {performance.total_pnl_algo >= 0 ? 
                    <TrendingUp sx={{ color: '#00C853', mr: 1 }} /> :
                    <TrendingDown sx={{ color: '#F44336', mr: 1 }} />
                  }
                  <Typography variant="h6" sx={{ color: '#fff' }}>
                    Total P&L
                  </Typography>
                </Box>
                <Typography 
                  variant="h4" 
                  sx={{ 
                    color: performance.total_pnl_algo >= 0 ? '#00C853' : '#F44336', 
                    fontWeight: 'bold' 
                  }}
                >
                  {performance.total_pnl_algo >= 0 ? '+' : ''}{formatAlgo(performance.total_pnl_algo)}
                </Typography>
              </CardContent>
            </Card>
          </Grid>

          <Grid item xs={12} sm={6} md={3}>
            <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2 }}>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                  <Speed sx={{ color: '#9C27B0', mr: 1 }} />
                  <Typography variant="h6" sx={{ color: '#fff' }}>
                    Win Rate
                  </Typography>
                </Box>
                <Typography variant="h4" sx={{ color: '#9C27B0', fontWeight: 'bold' }}>
                  {(performance.win_rate * 100).toFixed(1)}%
                </Typography>
                <Typography variant="body2" sx={{ color: '#bbb' }}>
                  {performance.total_trades} total trades
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      )}

      {/* Charts */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        {chartData.length > 0 && (
          <Grid item xs={12} md={8}>
            <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2, p: 2 }}>
              <Typography variant="h6" sx={{ color: '#fff', mb: 2 }}>
                Portfolio Performance
              </Typography>
              <ResponsiveContainer width="100%" height={300} minWidth={400} minHeight={300}>
                <AreaChart data={chartData}>
                  <defs>
                    <linearGradient id="colorValue" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#00E5FF" stopOpacity={0.8} />
                      <stop offset="95%" stopColor="#00E5FF" stopOpacity={0.1} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#333" />
                  <XAxis dataKey="time" stroke="#fff" />
                  <YAxis stroke="#fff" />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#2e2e2e',
                      border: '1px solid #333',
                      color: '#fff',
                    }}
                  />
                  <Area
                    type="monotone"
                    dataKey="value"
                    stroke="#00E5FF"
                    fillOpacity={1}
                    fill="url(#colorValue)"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </Card>
          </Grid>
        )}

        {strategyDistribution.length > 0 && (
          <Grid item xs={12} md={4}>
            <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2, p: 2 }}>
              <Typography variant="h6" sx={{ color: '#fff', mb: 2 }}>
                Allocation Distribution
              </Typography>
              <ResponsiveContainer width="100%" height={300} minWidth={400} minHeight={300}>
                <PieChart>
                  <Pie
                    data={strategyDistribution}
                    cx="50%"
                    cy="50%"
                    innerRadius={60}
                    outerRadius={100}
                    paddingAngle={5}
                    dataKey="value"
                    label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                    labelLine={false}
                    style={{ fontSize: '12px', fill: '#fff' }}
                  >
                    {strategyDistribution.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={entry.color} />
                    ))}
                  </Pie>
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#2e2e2e',
                      border: '1px solid #333',
                      color: '#fff',
                    }}
                  />
                </PieChart>
              </ResponsiveContainer>
            </Card>
          </Grid>
        )}
      </Grid>

      {/* Strategies and Transactions */}
      <Grid container spacing={3}>
        {/* Active Strategies */}
        <Grid item xs={12} md={6}>
          <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2 }}>
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
                <Typography variant="h6" sx={{ color: '#fff' }}>
                  Trading Strategies
                </Typography>
                <Chip 
                  label={`${activeStrategiesCount} Active`}
                  sx={{ bgcolor: '#00C853', color: '#fff' }}
                />
              </Box>
              
              {strategies.length > 0 ? (
                <Box sx={{ space: 2 }}>
                  {strategies.map((strategy) => (
                    <Card
                      key={strategy.id}
                      sx={{
                        bgcolor: '#2e2e2e',
                        border: '1px solid #444',
                        borderRadius: 1,
                        mb: 2,
                      }}
                    >
                      <CardContent>
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                          <Box>
                            <Typography variant="h6" sx={{ color: '#fff' }}>
                              {strategy.strategy_name}
                            </Typography>
                            <Typography variant="body2" sx={{ color: '#bbb' }}>
                              {strategy.strategy_type}
                            </Typography>
                          </Box>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Chip
                              label={getStatusText(strategy.is_active)}
                              sx={{
                                bgcolor: getStatusColor(strategy.is_active),
                                color: '#fff',
                                fontSize: '0.75rem',
                              }}
                            />
                            <IconButton
                              size="small"
                              onClick={() => handleToggleStrategy(strategy.id, strategy.is_active)}
                              sx={{
                                color: strategy.is_active ? '#FF6D00' : '#00C853',
                              }}
                            >
                              {strategy.is_active ? <Pause /> : <PlayArrow />}
                            </IconButton>
                          </Box>
                        </Box>
                        
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                          <Box>
                            <Typography variant="body2" sx={{ color: '#bbb' }}>
                              Allocated
                            </Typography>
                            <Typography variant="body1" sx={{ color: '#fff', fontWeight: 'bold' }}>
                              {formatAlgo(strategy.allocated_amount)}
                            </Typography>
                          </Box>
                          <Box sx={{ textAlign: 'right' }}>
                            <Typography variant="body2" sx={{ color: '#bbb' }}>
                              P&L
                            </Typography>
                            <Typography
                              variant="body1"
                              sx={{
                                color: strategy.current_pnl >= 0 ? '#00C853' : '#F44336',
                                fontWeight: 'bold',
                              }}
                            >
                              {strategy.current_pnl >= 0 ? '+' : ''}{formatAlgo(strategy.current_pnl)}
                            </Typography>
                          </Box>
                        </Box>
                        
                        {strategy.performance_score && (
                          <Box>
                            <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
                              <Typography variant="body2" sx={{ color: '#bbb' }}>
                                Performance
                              </Typography>
                              <Typography variant="body2" sx={{ color: '#fff' }}>
                                {(strategy.performance_score * 100).toFixed(0)}%
                              </Typography>
                            </Box>
                            <LinearProgress
                              variant="determinate"
                              value={strategy.performance_score * 100}
                              sx={{
                                height: 6,
                                borderRadius: 3,
                                bgcolor: '#444',
                                '& .MuiLinearProgress-bar': {
                                  bgcolor:
                                    strategy.performance_score >= 0.9
                                      ? '#00C853'
                                      : strategy.performance_score >= 0.7
                                      ? '#FF6D00'
                                      : '#F44336',
                                  borderRadius: 3,
                                },
                              }}
                            />
                          </Box>
                        )}
                      </CardContent>
                    </Card>
                  ))}
                </Box>
              ) : (
                <Typography sx={{ color: '#bbb', textAlign: 'center', py: 4 }}>
                  No strategies configured
                </Typography>
              )}
            </CardContent>
          </Card>
        </Grid>

        {/* Recent Transactions */}
        <Grid item xs={12} md={6}>
          <Card sx={{ bgcolor: '#1e1e1e', border: '1px solid #333', borderRadius: 2 }}>
            <CardContent>
              <Typography variant="h6" sx={{ color: '#fff', mb: 3 }}>
                Recent Transactions
              </Typography>
              
              {recentTransactions.length > 0 ? (
                <Box>
                  {recentTransactions.map((transaction) => (
                    <Card
                      key={transaction.id}
                      sx={{
                        bgcolor: '#2e2e2e',
                        border: '1px solid #444',
                        borderRadius: 1,
                        mb: 2,
                      }}
                    >
                      <CardContent>
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <Box>
                            <Typography variant="body1" sx={{ color: '#fff', textTransform: 'capitalize' }}>
                              {transaction.transaction_type}
                            </Typography>
                            <Typography variant="body2" sx={{ color: '#bbb' }}>
                              {formatDate(transaction.timestamp)}
                            </Typography>
                          </Box>
                          <Box sx={{ textAlign: 'right' }}>
                            <Typography variant="body1" sx={{ color: '#fff', fontWeight: 'bold' }}>
                              {formatNumber6(transaction.amount)} {transaction.asset_id || 'ALGO'}
                            </Typography>
                            {transaction.pnl_amount !== undefined && transaction.pnl_amount !== null && (
                              <Typography
                                variant="body2"
                                sx={{
                                  color: transaction.pnl_amount >= 0 ? '#00C853' : '#F44336',
                                }}
                              >
                                P&L: {transaction.pnl_amount >= 0 ? '+' : ''}{formatNumber6(transaction.pnl_amount)} ALGO
                              </Typography>
                            )}
                          </Box>
                        </Box>
                      </CardContent>
                    </Card>
                  ))}
                </Box>
              ) : (
                <Typography sx={{ color: '#bbb', textAlign: 'center', py: 4 }}>
                  No transactions yet
                </Typography>
              )}
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
};

export default Dashboard;