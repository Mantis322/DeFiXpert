import React, { useState, useEffect } from 'react';
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

// Mock data
const performanceData = [
  { time: '00:00', profit: 0, agents: 20 },
  { time: '04:00', profit: 1.2, agents: 18 },
  { time: '08:00', profit: 2.9, agents: 19 },
  { time: '12:00', profit: 4.1, agents: 17 },
  { time: '16:00', profit: 5.8, agents: 20 },
  { time: '20:00', profit: 7.2, agents: 19 },
  { time: '24:00', profit: 8.9, agents: 20 },
];

const strategyDistribution = [
  { name: 'Yield Farming', value: 35, color: '#00E5FF' },
  { name: 'Arbitrage', value: 25, color: '#00C853' },
  { name: 'Liquidity Mining', value: 20, color: '#FF6D00' },
  { name: 'Market Making', value: 20, color: '#9C27B0' },
];

const activeAgents = [
  {
    id: 1,
    name: 'AlgoYield Pro',
    type: 'Yield Farming',
    status: 'active',
    profit: '+2.4 ALGO',
    allocated: '500 ALGO',
    performance: 85,
  },
  {
    id: 2,
    name: 'ArbitrageMax',
    type: 'Arbitrage',
    status: 'active',
    profit: '+1.8 ALGO',
    allocated: '300 ALGO',
    performance: 92,
  },
  {
    id: 3,
    name: 'LiquidityBot',
    type: 'Liquidity Mining',
    status: 'paused',
    profit: '+0.9 ALGO',
    allocated: '200 ALGO',
    performance: 78,
  },
  {
    id: 4,
    name: 'MarketMaker AI',
    type: 'Market Making',
    status: 'active',
    profit: '+3.1 ALGO',
    allocated: '800 ALGO',
    performance: 88,
  },
];

const Dashboard = () => {
  const [totalProfit, setTotalProfit] = useState(8.9);
  const [totalValue, setTotalValue] = useState(1247.8);
  const [activeAgentsCount, setActiveAgentsCount] = useState(3);

  const formatCurrency = (amount) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
    }).format(amount);
  };

  const formatAlgo = (amount) => {
    return `${amount.toFixed(2)} ALGO`;
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'active':
        return '#00C853';
      case 'paused':
        return '#FF9800';
      case 'stopped':
        return '#F44336';
      default:
        return '#757575';
    }
  };

  const getStatusText = (status) => {
    return status.charAt(0).toUpperCase() + status.slice(1);
  };

  return (
    <Box sx={{ flexGrow: 1, p: 3 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h4" component="h1" sx={{ color: '#fff' }}>
          Dashboard
        </Typography>
        <Button
          variant="contained"
          startIcon={<Refresh />}
          sx={{
            bgcolor: '#00E5FF',
            '&:hover': { bgcolor: '#00B9D4' },
          }}
        >
          Refresh Data
        </Button>
      </Box>

      {/* Summary Cards */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card
            sx={{
              bgcolor: '#1e1e1e',
              border: '1px solid #333',
              borderRadius: 2,
            }}
          >
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <AccountBalance sx={{ color: '#00E5FF', mr: 1 }} />
                <Typography variant="h6" sx={{ color: '#fff' }}>
                  Total Value
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ color: '#00E5FF', fontWeight: 'bold' }}>
                {formatAlgo(totalValue)}
              </Typography>
              <Typography variant="body2" sx={{ color: '#00C853' }}>
                ↗ +12.4% today
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card
            sx={{
              bgcolor: '#1e1e1e',
              border: '1px solid #333',
              borderRadius: 2,
            }}
          >
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <TrendingUp sx={{ color: '#00C853', mr: 1 }} />
                <Typography variant="h6" sx={{ color: '#fff' }}>
                  24h Profit
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ color: '#00C853', fontWeight: 'bold' }}>
                +{formatAlgo(totalProfit)}
              </Typography>
              <Typography variant="body2" sx={{ color: '#00C853' }}>
                ↗ +8.2% from yesterday
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card
            sx={{
              bgcolor: '#1e1e1e',
              border: '1px solid #333',
              borderRadius: 2,
            }}
          >
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <SmartToy sx={{ color: '#FF6D00', mr: 1 }} />
                <Typography variant="h6" sx={{ color: '#fff' }}>
                  Active Agents
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ color: '#FF6D00', fontWeight: 'bold' }}>
                {activeAgentsCount}/{activeAgents.length}
              </Typography>
              <Typography variant="body2" sx={{ color: '#fff' }}>
                All systems operational
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card
            sx={{
              bgcolor: '#1e1e1e',
              border: '1px solid #333',
              borderRadius: 2,
            }}
          >
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                <Speed sx={{ color: '#9C27B0', mr: 1 }} />
                <Typography variant="h6" sx={{ color: '#fff' }}>
                  Avg Performance
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ color: '#9C27B0', fontWeight: 'bold' }}>
                85.8%
              </Typography>
              <Typography variant="body2" sx={{ color: '#00C853' }}>
                ↗ +3.2% this week
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Charts */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} md={8}>
          <Card
            sx={{
              bgcolor: '#1e1e1e',
              border: '1px solid #333',
              borderRadius: 2,
              p: 2,
            }}
          >
            <Typography variant="h6" sx={{ color: '#fff', mb: 2 }}>
              Performance Overview
            </Typography>
            <ResponsiveContainer width="100%" height={300}>
              <AreaChart data={performanceData}>
                <defs>
                  <linearGradient id="colorProfit" x1="0" y1="0" x2="0" y2="1">
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
                  dataKey="profit"
                  stroke="#00E5FF"
                  fillOpacity={1}
                  fill="url(#colorProfit)"
                />
              </AreaChart>
            </ResponsiveContainer>
          </Card>
        </Grid>

        <Grid item xs={12} md={4}>
          <Card
            sx={{
              bgcolor: '#1e1e1e',
              border: '1px solid #333',
              borderRadius: 2,
              p: 2,
            }}
          >
            <Typography variant="h6" sx={{ color: '#fff', mb: 2 }}>
              Strategy Distribution
            </Typography>
            <ResponsiveContainer width="100%" height={300}>
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
                  style={{ fontSize: '12px' }}
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
      </Grid>

      {/* Active Agents */}
      <Card
        sx={{
          bgcolor: '#1e1e1e',
          border: '1px solid #333',
          borderRadius: 2,
        }}
      >
        <CardContent>
          <Typography variant="h6" sx={{ color: '#fff', mb: 3 }}>
            Active Agents
          </Typography>
          <Grid container spacing={2}>
            {activeAgents.map((agent) => (
              <Grid item xs={12} md={6} key={agent.id}>
                <Card
                  sx={{
                    bgcolor: '#2e2e2e',
                    border: '1px solid #444',
                    borderRadius: 1,
                  }}
                >
                  <CardContent>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                      <Typography variant="h6" sx={{ color: '#fff' }}>
                        {agent.name}
                      </Typography>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Chip
                          label={getStatusText(agent.status)}
                          sx={{
                            bgcolor: getStatusColor(agent.status),
                            color: '#fff',
                            fontSize: '0.75rem',
                          }}
                        />
                        <IconButton
                          size="small"
                          sx={{
                            color: agent.status === 'active' ? '#FF6D00' : '#00C853',
                          }}
                        >
                          {agent.status === 'active' ? <Pause /> : <PlayArrow />}
                        </IconButton>
                      </Box>
                    </Box>
                    
                    <Typography variant="body2" sx={{ color: '#bbb', mb: 2 }}>
                      {agent.type}
                    </Typography>
                    
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 2 }}>
                      <Box>
                        <Typography variant="body2" sx={{ color: '#bbb' }}>
                          Allocated
                        </Typography>
                        <Typography variant="body1" sx={{ color: '#fff', fontWeight: 'bold' }}>
                          {agent.allocated}
                        </Typography>
                      </Box>
                      <Box sx={{ textAlign: 'right' }}>
                        <Typography variant="body2" sx={{ color: '#bbb' }}>
                          24h Profit
                        </Typography>
                        <Typography
                          variant="body1"
                          sx={{
                            color: agent.profit.startsWith('+') ? '#00C853' : '#F44336',
                            fontWeight: 'bold',
                          }}
                        >
                          {agent.profit}
                        </Typography>
                      </Box>
                    </Box>
                    
                    <Box>
                      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}>
                        <Typography variant="body2" sx={{ color: '#bbb' }}>
                          Performance
                        </Typography>
                        <Typography variant="body2" sx={{ color: '#fff' }}>
                          {agent.performance}%
                        </Typography>
                      </Box>
                      <LinearProgress
                        variant="determinate"
                        value={agent.performance}
                        sx={{
                          height: 6,
                          borderRadius: 3,
                          bgcolor: '#444',
                          '& .MuiLinearProgress-bar': {
                            bgcolor:
                              agent.performance >= 90
                                ? '#00C853'
                                : agent.performance >= 70
                                ? '#FF6D00'
                                : '#F44336',
                            borderRadius: 3,
                          },
                        }}
                      />
                    </Box>
                  </CardContent>
                </Card>
              </Grid>
            ))}
          </Grid>
        </CardContent>
      </Card>
    </Box>
  );
};

export default Dashboard;