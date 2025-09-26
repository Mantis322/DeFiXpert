import React, { useState, useEffect, useRef } from 'react';
import {
  Card,
  CardContent,
  Typography,
  Box,
  Grid,
  Chip,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  IconButton,
  Tooltip,
  Alert
} from '@mui/material';
import {
  Timeline,
  TrendingUp,
  TrendingDown,
  Refresh,
  SignalCellularAlt,
  SignalCellularConnectedNoInternet0Bar
} from '@mui/icons-material';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip, Legend, ResponsiveContainer } from 'recharts';
import algofiAPI from '../services/algofiAPI';

const RealTimePriceFeed = ({ onOpportunityFound }) => {
  const [priceData, setPriceData] = useState({});
  const [streamingStatus, setStreamingStatus] = useState({
    active: false,
    connections: [],
    lastUpdate: null
  });
  const [chartData, setChartData] = useState([]);
  const [opportunities, setOpportunities] = useState([]);
  const [error, setError] = useState(null);
  const intervalRef = useRef(null);

  // Filter function for ALGO/USD only
  const filterAlgoUsdOnly = (prices) => {
    const filtered = {};
    // Only keep ALGO/USD pair
    if (prices['ALGO/USD']) {
      filtered['ALGO/USD'] = prices['ALGO/USD'];
    }
    return filtered;
  };

  // Fetch real-time prices from backend API
  const fetchRealPrices = async () => {
    try {
      console.log('🔄 Fetching ALGO/USD prices...');
      const response = await algofiAPI.getCurrentPrices();
      const allPrices = response.prices || response; // Handle both response formats
      
      // Filter for ALGO/USD only
      const prices = filterAlgoUsdOnly(allPrices);
      
      console.log('📊 ALGO/USD multi-exchange prices:', prices);
      console.log('📊 Full response:', response);
      
      if (prices && typeof prices === 'object' && Object.keys(prices).length > 0) {
        const timestamp = new Date();
        
        // Add timestamp to each price entry
        const timestampedPrices = {};
        Object.entries(prices).forEach(([pair, dexes]) => {
          if (dexes && typeof dexes === 'object') {
            timestampedPrices[pair] = {};
            Object.entries(dexes).forEach(([dex, data]) => {
              timestampedPrices[pair][dex] = {
                ...data,
                timestamp,
                fee: 0.003 // Default fee, could come from API
              };
            });
          }
        });
        
        setPriceData(timestampedPrices);
        updateChartData(timestampedPrices, timestamp);
        detectArbitrageOpportunities(timestampedPrices, timestamp);
        
        setStreamingStatus(prev => ({
          ...prev,
          lastUpdate: timestamp,
          connections: Object.keys(timestampedPrices).flatMap(pair => 
            Object.keys(timestampedPrices[pair]).map(dex => `${dex}-${pair}`)
          )
        }));
        
        setError(null);
        console.log('✅ Successfully processed price data:', Object.keys(timestampedPrices));
      } else {
        console.warn('⚠️ No valid price data received. Response:', response);
        console.warn('⚠️ Prices object:', prices);
        setError('No price data available from backend');
      }
    } catch (error) {
      console.error('❌ Failed to fetch real-time prices:', error);
      console.error('❌ Error details:', error.stack);
      setError(`Failed to fetch real-time prices: ${error.message}`);
    }
  };

  // Start real-time price updates
  const startPriceFeed = () => {
    if (intervalRef.current) return;

    console.log('🚀 Starting real-time price feed...');
    setStreamingStatus(prev => ({ ...prev, active: true, lastUpdate: new Date() }));

    // Initial fetch
    fetchRealPrices();

    // Set up interval to fetch prices every 5 seconds
    intervalRef.current = setInterval(() => {
      fetchRealPrices();
    }, 5000); // 5 second updates for real-time feel
  };

  // Stop price feed
  const stopPriceFeed = () => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
    setStreamingStatus(prev => ({ ...prev, active: false }));
  };

  // Update chart data
  const updateChartData = (newPriceData, timestamp) => {
    const chartPoint = {
      timestamp: timestamp.toLocaleTimeString(),
      'ALGO/USD-coingecko': newPriceData['ALGO/USD']?.coingecko?.price,
      'ALGO/USD-htx': newPriceData['ALGO/USD']?.htx?.price,
      'ALGO/USD-tinyman': newPriceData['ALGO/USD']?.tinyman?.price,
    };

    setChartData(prev => {
      const newData = [...prev, chartPoint];
      // Keep only last 20 points
      return newData.slice(-20);
    });
  };

  // Detect arbitrage opportunities
  const detectArbitrageOpportunities = (priceData, timestamp) => {
    const newOpportunities = [];

    Object.entries(priceData).forEach(([pair, dexes]) => {
      const dexList = Object.entries(dexes);
      
      // Compare all DEX pairs
      for (let i = 0; i < dexList.length; i++) {
        for (let j = i + 1; j < dexList.length; j++) {
          const [dex1, data1] = dexList[i];
          const [dex2, data2] = dexList[j];
          
          const spreadPct = ((data2.price - data1.price) / data1.price) * 100;
          const totalFees = data1.fee + data2.fee;
          const netProfitPct = Math.abs(spreadPct) - (totalFees * 100);
          
          if (netProfitPct > 0.5) { // Minimum 0.5% profit after fees
            newOpportunities.push({
              id: `${pair}-${dex1}-${dex2}-${timestamp.getTime()}`,
              pair,
              buyDex: spreadPct > 0 ? dex1 : dex2,
              sellDex: spreadPct > 0 ? dex2 : dex1,
              buyPrice: spreadPct > 0 ? data1.price : data2.price,
              sellPrice: spreadPct > 0 ? data2.price : data1.price,
              spreadPct: Math.abs(spreadPct),
              netProfitPct,
              timestamp,
              expiresAt: new Date(timestamp.getTime() + 30000) // 30 seconds
            });
          }
        }
      }
    });

    if (newOpportunities.length > 0) {
      setOpportunities(prev => {
        const updated = [...prev, ...newOpportunities];
        // Remove expired opportunities
        const now = new Date();
        return updated.filter(opp => opp.expiresAt > now);
      });

      // Notify parent component
      if (onOpportunityFound) {
        newOpportunities.forEach(opp => onOpportunityFound(opp));
      }
    }
  };

  // Format price with proper decimals
  const formatPrice = (price) => {
    if (!price) return '-.----';
    return price.toFixed(4);
  };

  // Get price change color
  const getPriceChangeColor = (current, previous) => {
    if (!current || !previous) return 'inherit';
    return current > previous ? 'success.main' : 'error.main';
  };

  useEffect(() => {
    // Auto-start price feed
    startPriceFeed();
    
    return () => {
      stopPriceFeed();
    };
  }, []);

  const ConnectionStatus = () => (
    <Box display="flex" alignItems="center" gap={1}>
      {streamingStatus.active ? (
        <SignalCellularAlt color="success" />
      ) : (
        <SignalCellularConnectedNoInternet0Bar color="error" />
      )}
      <Typography variant="body2">
        {streamingStatus.active ? 'Live' : 'Disconnected'}
      </Typography>
      {streamingStatus.lastUpdate && (
        <Typography variant="caption" color="textSecondary">
          Last: {streamingStatus.lastUpdate.toLocaleTimeString()}
        </Typography>
      )}
    </Box>
  );

  return (
    <Box>
      {/* Status Header */}
      <Card sx={{ mb: 2 }}>
        <CardContent>
          <Box display="flex" justifyContent="space-between" alignItems="center">
            <Box>
              <Typography variant="h6" gutterBottom>
                ALGO/USD Live Prices
              </Typography>
              <Typography variant="body2" color="textSecondary" gutterBottom>
                Real-time ALGO pricing across CoinGecko, HTX & Tinyman
              </Typography>
              <ConnectionStatus />
            </Box>
            <Box display="flex" gap={1}>
              <Tooltip title="Toggle Stream">
                <IconButton 
                  onClick={streamingStatus.active ? stopPriceFeed : startPriceFeed}
                  color={streamingStatus.active ? "error" : "primary"}
                >
                  {streamingStatus.active ? <Timeline /> : <Refresh />}
                </IconButton>
              </Tooltip>
            </Box>
          </Box>
        </CardContent>
      </Card>

      <Grid container spacing={2}>
        {/* Price Data Table */}
        <Grid item xs={12} md={8}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>ALGO/USD Exchange Comparison</Typography>
              <TableContainer component={Paper} variant="outlined">
                <Table size="small">
                  <TableHead>
                    <TableRow>
                      <TableCell>Exchange</TableCell>
                      <TableCell>Price (USD)</TableCell>
                      <TableCell>24h Volume</TableCell>
                      <TableCell>24h Change</TableCell>
                      <TableCell>Spread vs Avg</TableCell>
                      <TableCell>Last Updated</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {Object.entries(priceData).map(([pair, exchanges]) => {
                      if (pair !== 'ALGO/USD') return null; // Only show ALGO/USD
                      
                      // Calculate average price for spread comparison
                      const exchangeList = Object.entries(exchanges);
                      const prices = exchangeList.map(([_, data]) => data.price);
                      const avgPrice = prices.reduce((sum, p) => sum + p, 0) / prices.length;
                      
                      return exchangeList.map(([exchangeName, exchangeData]) => {
                        const price = exchangeData.price || 0;
                        const volume = exchangeData.volume_24h || 0;
                        const change = exchangeData.change_24h || 0;
                        const lastUpdated = exchangeData.last_updated || 'N/A';
                        
                        // Calculate spread vs average
                        const spreadVsAvg = ((price - avgPrice) / avgPrice) * 100;
                        
                        return (
                          <TableRow key={`${pair}-${exchangeName}`}>
                            <TableCell>
                              <Box display="flex" alignItems="center" gap={1}>
                                <Typography variant="body2" fontWeight="bold" sx={{ textTransform: 'capitalize' }}>
                                  {exchangeName}
                                </Typography>
                                {exchangeName === 'coingecko' && <Chip label="CG" size="small" color="info" />}
                                {exchangeName === 'htx' && <Chip label="HTX" size="small" color="warning" />}
                                {exchangeName === 'tinyman' && <Chip label="TM" size="small" color="success" />}
                              </Box>
                            </TableCell>
                            <TableCell>
                              <Typography variant="body1" fontWeight="medium">
                                ${formatPrice(price)}
                              </Typography>
                            </TableCell>
                            <TableCell>
                              <Typography variant="body2" color="textSecondary">
                                ${(volume / 1000000).toFixed(2)}M
                              </Typography>
                            </TableCell>
                            <TableCell>
                              <Typography 
                                variant="body2" 
                                color={change >= 0 ? "success.main" : "error.main"}
                                fontWeight="medium"
                              >
                                {change >= 0 ? '+' : ''}{change.toFixed(2)}%
                              </Typography>
                            </TableCell>
                            <TableCell>
                              <Chip
                                label={`${spreadVsAvg >= 0 ? '+' : ''}${spreadVsAvg.toFixed(3)}%`}
                                size="small"
                                color={Math.abs(spreadVsAvg) > 0.1 ? 
                                  (spreadVsAvg > 0 ? "success" : "error") : "default"}
                                variant="outlined"
                              />
                            </TableCell>
                            <TableCell>
                              <Typography variant="caption" color="textSecondary">
                                {typeof lastUpdated === 'string' && lastUpdated.includes('T') ?
                                  new Date(lastUpdated).toLocaleTimeString() : 'Live'}
                              </Typography>
                            </TableCell>
                          </TableRow>
                        );
                      });
                    }).flat().filter(Boolean)}
                  </TableBody>
                </Table>
              </TableContainer>
            </CardContent>
          </Card>
        </Grid>

        {/* Live Opportunities */}
        <Grid item xs={12} md={4}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Live Opportunities ({opportunities.length})
              </Typography>
              {opportunities.length === 0 ? (
                <Typography variant="body2" color="textSecondary">
                  No opportunities detected
                </Typography>
              ) : (
                <Box sx={{ maxHeight: 300, overflow: 'auto' }}>
                  {opportunities.slice(-5).map((opp) => (
                    <Alert
                      key={opp.id}
                      severity="success"
                      icon={<TrendingUp />}
                      sx={{ mb: 1, fontSize: '0.875rem' }}
                    >
                      <Typography variant="body2" fontWeight="bold">
                        {opp.pair}
                      </Typography>
                      <Typography variant="caption" display="block">
                        Buy: {opp.buyDex} @ {formatPrice(opp.buyPrice)}
                      </Typography>
                      <Typography variant="caption" display="block">
                        Sell: {opp.sellDex} @ {formatPrice(opp.sellPrice)}
                      </Typography>
                      <Typography variant="caption" display="block" color="success.main">
                        Profit: {opp.netProfitPct.toFixed(2)}%
                      </Typography>
                    </Alert>
                  ))}
                </Box>
              )}
            </CardContent>
          </Card>
        </Grid>

        {/* Price Chart */}
        <Grid item xs={12}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>ALGO/USD Price Chart</Typography>
              <Box sx={{ height: 300 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={chartData}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="timestamp" />
                    <YAxis domain={['dataMin - 0.001', 'dataMax + 0.001']} />
                    <RechartsTooltip />
                    <Legend />
                    <Line type="monotone" dataKey="ALGO/USD-coingecko" stroke="#8884d8" strokeWidth={2} name="CoinGecko" />
                    <Line type="monotone" dataKey="ALGO/USD-htx" stroke="#82ca9d" strokeWidth={2} name="HTX" />
                    <Line type="monotone" dataKey="ALGO/USD-tinyman" stroke="#ffc658" strokeWidth={2} name="Tinyman" />
                  </LineChart>
                </ResponsiveContainer>
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  );
};

export default RealTimePriceFeed;