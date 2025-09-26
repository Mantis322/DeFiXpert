import React, { useState, useEffect } from 'react';
import {
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Chip,
  IconButton,
  Button,
  Tabs,
  Tab,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Alert,
  LinearProgress,
} from '@mui/material';
import {
  TrendingUp,
  TrendingDown,
  Refresh,
  Warning,
  CheckCircle,
  Schedule,
  CompareArrows,
  Timeline,
} from '@mui/icons-material';
import {
  LineChart,
  Line,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  ComposedChart,
  ReferenceLine,
} from 'recharts';

// Mock market data
const generateMarketData = () => {
  const now = Date.now();
  return Array.from({ length: 24 }, (_, i) => {
    const time = new Date(now - (23 - i) * 60 * 60 * 1000);
    return {
      time: time.getHours() + ':00',
      algoPrice: 0.25 + Math.sin(i * 0.3) * 0.05 + Math.random() * 0.02,
      volume: 1000000 + Math.random() * 500000,
      tinyman: 0.25 + Math.sin(i * 0.3 + 0.1) * 0.05 + Math.random() * 0.02,
      pact: 0.25 + Math.sin(i * 0.3 + 0.2) * 0.05 + Math.random() * 0.02,
      algofi: 0.25 + Math.sin(i * 0.3 + 0.3) * 0.05 + Math.random() * 0.02,
    };
  });
};

const arbitrageOpportunities = [
  {
    id: 1,
    pair: 'ALGO/USDC',
    fromDex: 'Tinyman',
    toDex: 'Pact',
    spread: 2.34,
    profit: 0.045,
    confidence: 95,
    status: 'active',
    timeLeft: 45,
  },
  {
    id: 2,
    pair: 'USDt/ALGO',
    fromDex: 'AlgoFi',
    toDex: 'Tinyman',
    spread: 1.87,
    profit: 0.032,
    confidence: 88,
    status: 'executing',
    timeLeft: 12,
  },
  {
    id: 3,
    pair: 'YLDY/ALGO',
    fromDex: 'Pact',
    toDex: 'AlgoFi',
    spread: 3.21,
    profit: 0.067,
    confidence: 76,
    status: 'potential',
    timeLeft: 120,
  },
];

const dexStats = [
  { name: 'Tinyman', tvl: 45678000, volume24h: 2345000, fees24h: 12340, avgSlippage: 0.12, status: 'optimal' },
  { name: 'Pact', tvl: 23456000, volume24h: 1234000, fees24h: 8970, avgSlippage: 0.18, status: 'good' },
  { name: 'AlgoFi', tvl: 78901000, volume24h: 3456000, fees24h: 18450, status: 'optimal' },
  { name: 'Folks Finance', tvl: 34567000, volume24h: 1890000, fees24h: 9876, avgSlippage: 0.15, status: 'good' },
];

const predictionData = [
  { asset: 'ALGO', current: 0.2534, predicted1h: 0.2587, predicted24h: 0.2698, confidence: 84, trend: 'up' },
  { asset: 'USDt', current: 1.0001, predicted1h: 1.0003, predicted24h: 0.9998, confidence: 92, trend: 'stable' },
  { asset: 'YLDY', current: 0.0089, predicted1h: 0.0092, predicted24h: 0.0095, confidence: 67, trend: 'up' },
  { asset: 'OPUL', current: 0.1234, predicted1h: 0.1189, predicted24h: 0.1156, confidence: 71, trend: 'down' },
];

function MarketAnalysis() {
  const [tabValue, setTabValue] = useState(0);
  const [marketData, setMarketData] = useState(generateMarketData());
  const [lastUpdate, setLastUpdate] = useState(new Date());

  // Simulate real-time market updates
  useEffect(() => {
    const interval = setInterval(() => {
      setMarketData(generateMarketData());
      setLastUpdate(new Date());
    }, 10000);

    return () => clearInterval(interval);
  }, []);

  const handleTabChange = (event, newValue) => {
    setTabValue(newValue);
  };

  const formatCurrency = (value) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
    }).format(value);
  };

  const formatLargeNumber = (value) => {
    if (value >= 1000000) {
      return (value / 1000000).toFixed(1) + 'M';
    } else if (value >= 1000) {
      return (value / 1000).toFixed(1) + 'K';
    }
    return value.toLocaleString();
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'optimal':
        return 'success';
      case 'good':
        return 'primary';
      case 'warning':
        return 'warning';
      case 'active':
        return 'success';
      case 'executing':
        return 'warning';
      case 'potential':
        return 'info';
      default:
        return 'default';
    }
  };

  const getTrendIcon = (trend) => {
    switch (trend) {
      case 'up':
        return <TrendingUp sx={{ fontSize: 16, color: 'success.main' }} />;
      case 'down':
        return <TrendingDown sx={{ fontSize: 16, color: 'error.main' }} />;
      default:
        return <CompareArrows sx={{ fontSize: 16, color: 'text.secondary' }} />;
    }
  };

  return (
    <Box sx={{ flexGrow: 1 }}>
      {/* Header */}
      <Box sx={{ mb: 4, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Box>
          <Typography variant="h3" component="h1" fontWeight={700} gutterBottom>
            Market Analysis & Predictions
          </Typography>
          <Typography variant="body1" color="text.secondary">
            AI-powered market analysis across Algorand DeFi protocols
          </Typography>
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
          <Typography variant="body2" color="text.secondary">
            Last update: {lastUpdate.toLocaleTimeString()}
          </Typography>
          <IconButton color="primary">
            <Refresh />
          </IconButton>
        </Box>
      </Box>

      {/* Market Overview */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography color="text.secondary" gutterBottom variant="body2">
                    ALGO Price
                  </Typography>
                  <Typography variant="h5" component="div" fontWeight={700}>
                    ${marketData[marketData.length - 1]?.algoPrice.toFixed(4)}
                  </Typography>
                  <Box sx={{ display: 'flex', alignItems: 'center', mt: 1 }}>
                    <TrendingUp sx={{ fontSize: 16, color: 'success.main', mr: 0.5 }} />
                    <Typography variant="body2" color="success.main" fontWeight={600}>
                      +2.4%
                    </Typography>
                  </Box>
                </Box>
                <Timeline sx={{ fontSize: 40, color: 'primary.main', opacity: 0.8 }} />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography color="text.secondary" gutterBottom variant="body2">
                    Arbitrage Opportunities
                  </Typography>
                  <Typography variant="h5" component="div" fontWeight={700}>
                    {arbitrageOpportunities.filter(op => op.status === 'active').length}
                  </Typography>
                  <Typography variant="body2" color="warning.main" fontWeight={600}>
                    2 executing
                  </Typography>
                </Box>
                <CompareArrows sx={{ fontSize: 40, color: 'warning.main', opacity: 0.8 }} />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography color="text.secondary" gutterBottom variant="body2">
                    Total DEX Volume
                  </Typography>
                  <Typography variant="h5" component="div" fontWeight={700}>
                    ${formatLargeNumber(8925000)}
                  </Typography>
                  <Typography variant="body2" color="success.main" fontWeight={600}>
                    +12.8% 24h
                  </Typography>
                </Box>
                <TrendingUp sx={{ fontSize: 40, color: 'success.main', opacity: 0.8 }} />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card>
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography color="text.secondary" gutterBottom variant="body2">
                    AI Confidence
                  </Typography>
                  <Typography variant="h5" component="div" fontWeight={700}>
                    87%
                  </Typography>
                  <Typography variant="body2" color="info.main" fontWeight={600}>
                    High accuracy
                  </Typography>
                </Box>
                <CheckCircle sx={{ fontSize: 40, color: 'info.main', opacity: 0.8 }} />
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Tabs for different views */}
      <Card sx={{ mb: 4 }}>
        <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
          <Tabs value={tabValue} onChange={handleTabChange}>
            <Tab label="Price Charts" />
            <Tab label="Arbitrage Opportunities" />
            <Tab label="AI Predictions" />
            <Tab label="DEX Analysis" />
          </Tabs>
        </Box>

        <CardContent>
          {/* Price Charts Tab */}
          {tabValue === 0 && (
            <Box sx={{ height: 400 }}>
              <Typography variant="h6" gutterBottom>
                Cross-DEX Price Comparison
              </Typography>
              <ResponsiveContainer width="100%" height="100%">
                <ComposedChart data={marketData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                  <XAxis dataKey="time" stroke="#B0B7C3" />
                  <YAxis yAxisId="price" stroke="#B0B7C3" />
                  <YAxis yAxisId="volume" orientation="right" stroke="#B0B7C3" />
                  <Tooltip 
                    contentStyle={{
                      backgroundColor: '#1A1F2E',
                      border: '1px solid rgba(0, 229, 255, 0.3)',
                      borderRadius: '8px',
                    }}
                  />
                  <Legend />
                  <Area 
                    type="monotone" 
                    dataKey="volume" 
                    fill="rgba(0, 229, 255, 0.1)" 
                    stroke="none"
                    yAxisId="volume"
                  />
                  <Line 
                    type="monotone" 
                    dataKey="tinyman" 
                    stroke="#00E5FF" 
                    strokeWidth={2}
                    dot={false}
                    name="Tinyman"
                    yAxisId="price"
                  />
                  <Line 
                    type="monotone" 
                    dataKey="pact" 
                    stroke="#FF4081" 
                    strokeWidth={2}
                    dot={false}
                    name="Pact"
                    yAxisId="price"
                  />
                  <Line 
                    type="monotone" 
                    dataKey="algofi" 
                    stroke="#00C853" 
                    strokeWidth={2}
                    dot={false}
                    name="AlgoFi"
                    yAxisId="price"
                  />
                </ComposedChart>
              </ResponsiveContainer>
            </Box>
          )}

          {/* Arbitrage Opportunities Tab */}
          {tabValue === 1 && (
            <Box>
              <Typography variant="h6" gutterBottom>
                Real-time Arbitrage Opportunities
              </Typography>
              <TableContainer>
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>Pair</TableCell>
                      <TableCell>Route</TableCell>
                      <TableCell>Spread</TableCell>
                      <TableCell>Est. Profit</TableCell>
                      <TableCell>Confidence</TableCell>
                      <TableCell>Status</TableCell>
                      <TableCell>Time Left</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {arbitrageOpportunities.map((opportunity) => (
                      <TableRow key={opportunity.id}>
                        <TableCell>
                          <Typography fontWeight={600}>
                            {opportunity.pair}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Typography variant="body2">
                              {opportunity.fromDex}
                            </Typography>
                            <CompareArrows sx={{ fontSize: 16 }} />
                            <Typography variant="body2">
                              {opportunity.toDex}
                            </Typography>
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Typography color="success.main" fontWeight={600}>
                            {opportunity.spread}%
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography fontWeight={600}>
                            {opportunity.profit.toFixed(3)} ALGO
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Typography variant="body2">
                              {opportunity.confidence}%
                            </Typography>
                            <LinearProgress
                              variant="determinate"
                              value={opportunity.confidence}
                              sx={{ width: 60, height: 4 }}
                            />
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Chip
                            label={opportunity.status}
                            color={getStatusColor(opportunity.status)}
                            size="small"
                            variant="outlined"
                          />
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" color="text.secondary">
                            {opportunity.timeLeft}s
                          </Typography>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            </Box>
          )}

          {/* AI Predictions Tab */}
          {tabValue === 2 && (
            <Box>
              <Typography variant="h6" gutterBottom>
                AI Price Predictions
              </Typography>
              <Alert severity="info" sx={{ mb: 3 }}>
                Predictions are generated using advanced machine learning models trained on historical market data, 
                cross-DEX price movements, and on-chain activity patterns.
              </Alert>
              <TableContainer>
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>Asset</TableCell>
                      <TableCell>Current Price</TableCell>
                      <TableCell>1h Prediction</TableCell>
                      <TableCell>24h Prediction</TableCell>
                      <TableCell>Confidence</TableCell>
                      <TableCell>Trend</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {predictionData.map((prediction, index) => (
                      <TableRow key={index}>
                        <TableCell>
                          <Typography fontWeight={600}>
                            {prediction.asset}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography>
                            ${prediction.current.toFixed(4)}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography 
                            color={prediction.predicted1h > prediction.current ? 'success.main' : 'error.main'}
                          >
                            ${prediction.predicted1h.toFixed(4)}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography 
                            color={prediction.predicted24h > prediction.current ? 'success.main' : 'error.main'}
                          >
                            ${prediction.predicted24h.toFixed(4)}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Typography variant="body2">
                              {prediction.confidence}%
                            </Typography>
                            <LinearProgress
                              variant="determinate"
                              value={prediction.confidence}
                              sx={{ width: 60, height: 4 }}
                              color={prediction.confidence > 80 ? 'success' : prediction.confidence > 60 ? 'warning' : 'error'}
                            />
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            {getTrendIcon(prediction.trend)}
                            <Typography variant="body2" textTransform="capitalize">
                              {prediction.trend}
                            </Typography>
                          </Box>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            </Box>
          )}

          {/* DEX Analysis Tab */}
          {tabValue === 3 && (
            <Grid container spacing={3}>
              {dexStats.map((dex, index) => (
                <Grid item xs={12} md={6} key={index}>
                  <Card variant="outlined">
                    <CardContent>
                      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                        <Typography variant="h6" fontWeight={600}>
                          {dex.name}
                        </Typography>
                        <Chip
                          label={dex.status}
                          color={getStatusColor(dex.status)}
                          size="small"
                          variant="outlined"
                        />
                      </Box>
                      
                      <Grid container spacing={2}>
                        <Grid item xs={6}>
                          <Typography variant="body2" color="text.secondary">
                            TVL
                          </Typography>
                          <Typography variant="h6">
                            ${formatLargeNumber(dex.tvl)}
                          </Typography>
                        </Grid>
                        <Grid item xs={6}>
                          <Typography variant="body2" color="text.secondary">
                            24h Volume
                          </Typography>
                          <Typography variant="h6">
                            ${formatLargeNumber(dex.volume24h)}
                          </Typography>
                        </Grid>
                        <Grid item xs={6}>
                          <Typography variant="body2" color="text.secondary">
                            24h Fees
                          </Typography>
                          <Typography variant="h6">
                            ${formatLargeNumber(dex.fees24h)}
                          </Typography>
                        </Grid>
                        {dex.avgSlippage && (
                          <Grid item xs={6}>
                            <Typography variant="body2" color="text.secondary">
                              Avg Slippage
                            </Typography>
                            <Typography variant="h6">
                              {dex.avgSlippage}%
                            </Typography>
                          </Grid>
                        )}
                      </Grid>
                    </CardContent>
                  </Card>
                </Grid>
              ))}
            </Grid>
          )}
        </CardContent>
      </Card>
    </Box>
  );
}

export default MarketAnalysis;