import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../contexts/AuthContext';
import RealTimePriceFeed from '../components/RealTimePriceFeed';
import {
  Container,
  Typography,
  Card,
  CardContent,
  Box,
  Button,
  Grid,
  Chip,
  LinearProgress,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  MenuItem,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Switch,
  FormControlLabel,
  Alert,
  Tabs,
  Tab,
  Divider,
  Badge,
  CircularProgress
} from '@mui/material';
import {
  Add as AddIcon,
  PlayArrow as PlayIcon,
  Pause as PauseIcon,
  Delete as DeleteIcon,
  Edit as EditIcon,
  TrendingUp,
  AccountBalance,
  Speed,
  Refresh,
  Timeline,
  Notifications
} from '@mui/icons-material';

const strategyTypes = [
  { value: 'arbitrage', label: 'Arbitrage', icon: <Speed />, description: 'Cross-DEX arbitrage opportunities' },
  { value: 'yield_farming', label: 'Yield Farming', icon: <AccountBalance />, description: 'Automated yield optimization' },
  { value: 'market_making', label: 'Market Making', icon: <TrendingUp />, description: 'Provide liquidity and earn fees' }
];

function TabPanel(props) {
  const { children, value, index, ...other } = props;
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`strategy-tabpanel-${index}`}
      aria-labelledby={`strategy-tab-${index}`}
      {...other}
    >
      {value === index && <Box sx={{ pt: 3 }}>{children}</Box>}
    </div>
  );
}

function Strategies() {
  const { api } = useAuth();
  const [strategies, setStrategies] = useState([]);
  const [opportunities, setOpportunities] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [opportunitiesError, setOpportunitiesError] = useState(null);
  const [createDialog, setCreateDialog] = useState(false);
  const [editDialog, setEditDialog] = useState(false);
  const [selectedStrategy, setSelectedStrategy] = useState(null);
  const [tabValue, setTabValue] = useState(0);
  const [newStrategy, setNewStrategy] = useState({
    strategy_name: '',
    strategy_type: 'arbitrage',
    allocated_amount: 100,
    settings: {
      min_spread_pct: 0.5,
      max_position_size: 1000,
      stop_loss_pct: 5,
      take_profit_pct: 10
    }
  });

  const loadStrategies = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await api.getUserStrategies();
      setStrategies(Array.isArray(data) ? data : []);
    } catch (error) {
      console.error('Failed to load strategies:', error);
      setError(`Failed to connect to backend: ${error.message}`);
      setStrategies([]); // Clear any existing data
    } finally {
      setLoading(false);
    }
  }, [api]);

  const loadOpportunities = useCallback(async () => {
    try {
      setOpportunitiesError(null);
      const data = await api.getArbitrageOpportunities();
      setOpportunities(Array.isArray(data) ? data : []);
    } catch (error) {
      console.error('Failed to load opportunities:', error);
      setOpportunitiesError(`Failed to load live opportunities: ${error.message}`);
      setOpportunities([]); // Clear any existing data
    }
  }, [api]);

  // Simulate performance for all active strategies
  const simulateActiveStrategiesPerformance = useCallback(async () => {
    console.log('🚀 Starting strategy performance simulation with real market data...');
    try {
      const activeStrategies = strategies.filter(s => s.is_active);
      console.log(`📊 Found ${activeStrategies.length} active strategies:`, activeStrategies.map(s => ({ id: s.id, name: s.strategy_name })));
      
      for (const strategy of activeStrategies) {
        try {
          console.log(`⚡ Simulating performance for strategy ${strategy.id} (${strategy.strategy_name}) based on live market data`);
          const result = await api.simulateStrategyPerformance(strategy.id);
          console.log(`✅ Live simulation result for strategy ${strategy.id}:`, result);
        } catch (error) {
          console.warn(`⚠️ Failed to simulate performance for strategy ${strategy.id}:`, error);
        }
      }
      // Reload strategies to get updated P&L
      console.log('🔄 Reloading strategies to get updated P&L...');
      await loadStrategies();
      console.log('✅ Strategies reloaded with live market-based P&L');
    } catch (error) {
      console.error('❌ Failed to simulate strategies performance:', error);
    }
  }, [api, loadStrategies]); // strategies'i dependency'den çıkardık

  useEffect(() => {
    loadStrategies();
    loadOpportunities();
    
    // Set up auto-refresh for opportunities (every 45 seconds)
    const opportunitiesInterval = setInterval(() => {
      if (tabValue === 1) { // Only refresh when on opportunities tab
        loadOpportunities();
      }
    }, 45000);

    // Set up auto-refresh for strategy P&L (every 90 seconds)
    const strategiesInterval = setInterval(() => {
      if (tabValue === 0) { // Only refresh when on strategies tab
        console.log('⏰ Auto-refreshing strategy P&L...');
        simulateActiveStrategiesPerformance();
      }
    }, 90000); // Reduced frequency to 90 seconds

    return () => {
      clearInterval(opportunitiesInterval);
      clearInterval(strategiesInterval);
    };
  }, [loadStrategies, loadOpportunities, simulateActiveStrategiesPerformance, tabValue]); // strategies.length'i çıkardık

  const handleCreateStrategy = async () => {
    try {
      const result = await api.createUserStrategy(newStrategy);
      console.log('Strategy created:', result);
      setCreateDialog(false);
      setNewStrategy({
        strategy_name: '',
        strategy_type: 'arbitrage',
        allocated_amount: 100,
        settings: {}
      });
      loadStrategies();
    } catch (error) {
      console.error('Failed to create strategy:', error);
    }
  };

  const handleToggleStrategy = async (strategyId, isActive) => {
    try {
      await api.updateUserStrategy(strategyId, { is_active: !isActive });
      loadStrategies();
    } catch (error) {
      console.error('Failed to toggle strategy:', error);
    }
  };

  const handleEditStrategy = (strategy) => {
    setSelectedStrategy(strategy);
    setEditDialog(true);
  };

  const getStrategyTypeInfo = (type) => {
    return strategyTypes.find(t => t.value === type) || strategyTypes[0];
  };

  const formatAlgo = (amount) => {
    return `${Number(amount).toFixed(2)} ALGO`;
  };

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString();
  };

  const formatTimeRemaining = (expiresAt) => {
    const now = new Date();
    const expires = new Date(expiresAt);
    const diff = expires - now;
    
    if (diff <= 0) return 'Expired';
    
    const minutes = Math.floor(diff / 60000);
    const seconds = Math.floor((diff % 60000) / 1000);
    
    return `${minutes}m ${seconds}s`;
  };

  return (
    <Container maxWidth="lg" sx={{ py: 4 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 4 }}>
        <Typography variant="h4" fontWeight={700}>
          Trading Strategies
        </Typography>
        <Box sx={{ display: 'flex', gap: 2 }}>
          <Button
            variant="outlined"
            startIcon={<Refresh />}
            onClick={() => {
              loadStrategies();
              if (tabValue === 1) loadOpportunities();
            }}
          >
            Refresh
          </Button>
          <Button
            variant="contained"
            startIcon={<AddIcon />}
            onClick={() => setCreateDialog(true)}
          >
            Create Strategy
          </Button>
        </Box>
      </Box>

      {/* Navigation Tabs */}
      <Card sx={{ mb: 3 }}>
        <Tabs 
          value={tabValue} 
          onChange={(event, newValue) => setTabValue(newValue)}
          sx={{ borderBottom: 1, borderColor: 'divider' }}
        >
          <Tab 
            label="My Strategies" 
            icon={<Timeline />} 
            iconPosition="start"
            id="strategy-tab-0"
            aria-controls="strategy-tabpanel-0"
          />
          <Tab 
            label={
              <Badge badgeContent={opportunities.length} color="success">
                Live Opportunities
              </Badge>
            }
            icon={<Notifications />} 
            iconPosition="start"
            id="strategy-tab-1"
            aria-controls="strategy-tabpanel-1"
          />
          <Tab 
            label="Real-Time Feeds" 
            icon={<TrendingUp />} 
            iconPosition="start"
            id="strategy-tab-2"
            aria-controls="strategy-tabpanel-2"
          />
        </Tabs>
      </Card>

      {/* Strategy Types Overview */}
      <TabPanel value={tabValue} index={0}>
        <Grid container spacing={3} sx={{ mb: 4 }}>
          {strategyTypes.map((type) => (
            <Grid item xs={12} md={4} key={type.value}>
              <Card>
                <CardContent>
                  <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                    <Box sx={{ p: 1, borderRadius: 1, bgcolor: 'primary.main', color: 'white', mr: 2 }}>
                      {type.icon}
                    </Box>
                    <Typography variant="h6" fontWeight={600}>
                      {type.label}
                    </Typography>
                  </Box>
                  <Typography variant="body2" color="text.secondary">
                    {type.description}
                  </Typography>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>

        {/* Active Strategies */}
        <Card>
          <CardContent>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Typography variant="h6" fontWeight={600}>
                Your Strategies ({strategies.length})
              </Typography>
              <Box sx={{ display: 'flex', gap: 1 }}>
                <Button
                  variant="outlined"
                  size="small"
                  onClick={simulateActiveStrategiesPerformance}
                  color="primary"
                >
                  🚀 Test P&L
                </Button>
                <Button
                  variant="contained"
                  size="small"
                  startIcon={<AddIcon />}
                  onClick={() => setCreateDialog(true)}
                  color="primary"
                >
                  Create Strategy
                </Button>
              </Box>
            </Box>
            
            {loading ? (
              <Box sx={{ textAlign: 'center', py: 4 }}>
                <LinearProgress />
                <Typography sx={{ mt: 2 }}>Loading strategies...</Typography>
              </Box>
            ) : error ? (
              <Alert severity="error" sx={{ mt: 2 }}>
                <Typography variant="subtitle2" gutterBottom>
                  Backend Connection Error
                </Typography>
                {error}
                <Box sx={{ mt: 2 }}>
                  <Button 
                    variant="outlined" 
                    size="small" 
                    onClick={loadStrategies}
                    startIcon={<Refresh />}
                  >
                    Retry Connection
                  </Button>
                </Box>
              </Alert>
            ) : strategies.length === 0 ? (
              <Alert severity="info" sx={{ mt: 2 }}>
                No strategies created yet. Click "Create Strategy" to get started.
              </Alert>
            ) : (
              <TableContainer component={Paper} variant="outlined">
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>Strategy</TableCell>
                      <TableCell>Type</TableCell>
                      <TableCell align="right">Allocated</TableCell>
                      <TableCell align="right">P&L</TableCell>
                      <TableCell align="right">Performance</TableCell>
                      <TableCell>Status</TableCell>
                      <TableCell align="right">Actions</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {strategies.map((strategy) => {
                      const typeInfo = getStrategyTypeInfo(strategy.strategy_type);
                      return (
                        <TableRow key={strategy.id}>
                          <TableCell>
                            <Box>
                              <Typography variant="subtitle2" fontWeight={600}>
                                {strategy.strategy_name}
                              </Typography>
                              <Typography variant="caption" color="text.secondary">
                                Created {formatDate(strategy.created_at)}
                              </Typography>
                            </Box>
                          </TableCell>
                          <TableCell>
                            <Chip 
                              icon={typeInfo.icon}
                              label={typeInfo.label}
                              size="small"
                              variant="outlined"
                            />
                          </TableCell>
                          <TableCell align="right">
                            <Typography fontWeight={600}>
                              {formatAlgo(strategy.allocated_amount)}
                            </Typography>
                          </TableCell>
                          <TableCell align="right">
                            <Typography
                              color={strategy.current_pnl >= 0 ? 'success.main' : 'error.main'}
                              fontWeight={600}
                            >
                              {strategy.current_pnl >= 0 ? '+' : ''}{formatAlgo(strategy.current_pnl)}
                            </Typography>
                          </TableCell>
                          <TableCell align="right">
                            <Box sx={{ minWidth: 80 }}>
                              <Typography variant="body2" fontWeight={600}>
                                {(strategy.performance_score * 100).toFixed(0)}%
                              </Typography>
                              <LinearProgress
                                variant="determinate"
                                value={strategy.performance_score * 100}
                                sx={{ mt: 0.5 }}
                                color={strategy.performance_score >= 0.8 ? 'success' : 
                                       strategy.performance_score >= 0.6 ? 'warning' : 'error'}
                              />
                            </Box>
                          </TableCell>
                          <TableCell>
                            <Chip
                              label={strategy.is_active ? 'Active' : 'Inactive'}
                              color={strategy.is_active ? 'success' : 'default'}
                              size="small"
                            />
                          </TableCell>
                          <TableCell align="right">
                            <Box sx={{ display: 'flex', gap: 0.5 }}>
                              <IconButton
                                size="small"
                                onClick={() => handleToggleStrategy(strategy.id, strategy.is_active)}
                                color={strategy.is_active ? 'warning' : 'success'}
                              >
                                {strategy.is_active ? <PauseIcon /> : <PlayIcon />}
                              </IconButton>
                              <IconButton
                                size="small"
                                onClick={() => handleEditStrategy(strategy)}
                              >
                                <EditIcon />
                              </IconButton>
                            </Box>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </TableContainer>
            )}
          </CardContent>
        </Card>
      </TabPanel>

      {/* Live Opportunities Tab */}
      <TabPanel value={tabValue} index={1}>
        <Card>
          <CardContent>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
              <Typography variant="h6" fontWeight={600}>
                Live Arbitrage Opportunities ({opportunities.length})
              </Typography>
              <Button
                variant="outlined"
                size="small"
                startIcon={<Refresh />}
                onClick={loadOpportunities}
              >
                Refresh
              </Button>
            </Box>
            
            {opportunitiesError ? (
              <Alert severity="error" sx={{ mb: 3 }}>
                <Typography variant="subtitle2" gutterBottom>
                  Live Data Connection Error
                </Typography>
                {opportunitiesError}
                <Box sx={{ mt: 2 }}>
                  <Button 
                    variant="outlined" 
                    size="small" 
                    onClick={loadOpportunities}
                    startIcon={<Refresh />}
                  >
                    Retry Connection
                  </Button>
                </Box>
              </Alert>
            ) : opportunities.length === 0 ? (
              <Alert severity="info">
                No arbitrage opportunities currently detected. The system continuously scans for new opportunities.
              </Alert>
            ) : (
              <TableContainer component={Paper} variant="outlined">
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>Asset Pair</TableCell>
                      <TableCell>Buy From</TableCell>
                      <TableCell>Sell To</TableCell>
                      <TableCell align="right">Buy Price</TableCell>
                      <TableCell align="right">Sell Price</TableCell>
                      <TableCell align="right">Profit %</TableCell>
                      <TableCell align="right">Min Amount</TableCell>
                      <TableCell align="right">Max Amount</TableCell>
                      <TableCell>Expires In</TableCell>
                      <TableCell align="right">Action</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {opportunities.map((opp) => (
                      <TableRow key={opp.id}>
                        <TableCell>
                          <Typography variant="subtitle2" fontWeight={600}>
                            {opp.asset_pair}
                          </Typography>
                        </TableCell>
                        <TableCell>{opp.dex_1}</TableCell>
                        <TableCell>{opp.dex_2}</TableCell>
                        <TableCell align="right">
                          <Typography color="success.main" fontWeight={600}>
                            ${opp.price_1.toFixed(4)}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Typography color="error.main" fontWeight={600}>
                            ${opp.price_2.toFixed(4)}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Chip
                            label={`+${opp.profit_percentage.toFixed(2)}%`}
                            color="success"
                            size="small"
                            variant="filled"
                          />
                        </TableCell>
                        <TableCell align="right">
                          {formatAlgo(opp.min_trade_amount)}
                        </TableCell>
                        <TableCell align="right">
                          {formatAlgo(opp.max_trade_amount)}
                        </TableCell>
                        <TableCell>
                          <Typography 
                            variant="body2" 
                            color={new Date(opp.expires_at) - new Date() < 60000 ? 'error.main' : 'text.primary'}
                          >
                            {formatTimeRemaining(opp.expires_at)}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Button
                            variant="contained"
                            size="small"
                            color="success"
                            disabled={new Date(opp.expires_at) <= new Date()}
                          >
                            Execute
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            )}
          </CardContent>
        </Card>
      </TabPanel>

      {/* Real-Time Feeds Tab */}
      <TabPanel value={tabValue} index={2}>
        <RealTimePriceFeed 
          onOpportunityFound={(opportunity) => {
            console.log('New arbitrage opportunity detected:', opportunity);
            // Optionally add to opportunities list or trigger notifications
          }}
        />
      </TabPanel>

      {/* Create Strategy Dialog */}
      <Dialog open={createDialog} onClose={() => setCreateDialog(false)} maxWidth="md" fullWidth>
        <DialogTitle>Create New Strategy</DialogTitle>
        <DialogContent>
          <Grid container spacing={3} sx={{ mt: 1 }}>
            <Grid item xs={12}>
              <TextField
                fullWidth
                label="Strategy Name"
                value={newStrategy.strategy_name}
                onChange={(e) => setNewStrategy({...newStrategy, strategy_name: e.target.value})}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                select
                label="Strategy Type"
                value={newStrategy.strategy_type}
                onChange={(e) => setNewStrategy({...newStrategy, strategy_type: e.target.value})}
              >
                {strategyTypes.map((type) => (
                  <MenuItem key={type.value} value={type.value}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                      {type.icon}
                      {type.label}
                    </Box>
                  </MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                label="Allocated Amount (ALGO)"
                type="number"
                value={newStrategy.allocated_amount}
                onChange={(e) => setNewStrategy({...newStrategy, allocated_amount: Number(e.target.value)})}
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCreateDialog(false)}>Cancel</Button>
          <Button 
            onClick={handleCreateStrategy} 
            variant="contained"
            disabled={!newStrategy.strategy_name || newStrategy.allocated_amount <= 0}
          >
            Create Strategy
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
}

export default Strategies;
