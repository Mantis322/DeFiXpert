import React, { useState, useEffect, useCallback } from 'react';
import {
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Button,
  Slider,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Switch,
  FormControlLabel,
  Chip,
  IconButton,
  Alert,
  TextField,
  Divider,
  CircularProgress,
} from '@mui/material';
import {
  PlayArrow,
  Pause,
  Stop,
  Settings,
  Tune,
  SmartToy,
  Speed,
  TrendingUp,
  Warning,
  CheckCircle,
  Refresh,
} from '@mui/icons-material';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ScatterChart,
  Scatter,
  Cell,
} from 'recharts';

// API configuration
const API_BASE_URL = 'http://localhost:8052/api/v1';

// API service functions
const swarmAPI = {
  async getStatus() {
    const response = await fetch(`${API_BASE_URL}/swarm/status`);
    if (!response.ok) throw new Error('Failed to fetch swarm status');
    return response.json();
  },
  
  async getAgents() {
    const response = await fetch(`${API_BASE_URL}/swarm/agents`);
    if (!response.ok) throw new Error('Failed to fetch swarm agents');
    return response.json();
  },
  
  async startSwarm(config) {
    const response = await fetch(`${API_BASE_URL}/swarm/start`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(config),
    });
    if (!response.ok) throw new Error('Failed to start swarm');
    return response.json();
  },
  
  async stopSwarm() {
    const response = await fetch(`${API_BASE_URL}/swarm/stop`, {
      method: 'POST',
    });
    if (!response.ok) throw new Error('Failed to stop swarm');
    return response.json();
  },
  
  async getMetrics() {
    const response = await fetch(`${API_BASE_URL}/swarm/metrics`);
    if (!response.ok) throw new Error('Failed to fetch swarm metrics');
    return response.json();
  },
};

// Strategy color mapping
const strategyColors = {
  'Yield Farming': '#00E5FF',
  'Arbitrage': '#FF4081',
  'Liquidity Providing': '#00C853',
  'Portfolio Rebalancing': '#FFB300',
};

function SwarmControl() {
  // State management
  const [swarmState, setSwarmState] = useState('stopped');
  const [agents, setAgents] = useState([]);
  const [swarmMetrics, setSwarmMetrics] = useState({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  
  const [swarmConfig, setSwarmConfig] = useState({
    populationSize: 20,
    inertiaWeight: 0.5,
    cognitiveCoeff: 1.5,
    socialCoeff: 1.5,
    maxIterations: 100,
    convergenceThreshold: 0.001,
    riskTolerance: 0.3,
  });
  
  const [selectedStrategy, setSelectedStrategy] = useState('all');
  const [autoOptimize, setAutoOptimize] = useState(true);

  // API data fetching functions
  const fetchSwarmData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      
      const [statusData, agentsData, metricsData] = await Promise.all([
        swarmAPI.getStatus(),
        swarmAPI.getAgents(),
        swarmAPI.getMetrics(),
      ]);
      
      setSwarmState(statusData.status || 'stopped');
      setAgents(agentsData || []);
      setSwarmMetrics(metricsData || {});
      
    } catch (err) {
      console.error('Error fetching swarm data:', err);
      setError(`Failed to fetch swarm data: ${err.message}`);
    } finally {
      setLoading(false);
    }
  }, []);

  // Real-time updates with API polling
  useEffect(() => {
    // Initial data fetch
    fetchSwarmData();
    
    // Set up polling for real-time updates
    const interval = setInterval(() => {
      if (swarmState === 'running') {
        fetchSwarmData();
      }
    }, 3000); // Poll every 3 seconds when running

    return () => clearInterval(interval);
  }, [swarmState, fetchSwarmData]);

  // Swarm control handlers
  const handleSwarmControl = async (action) => {
    try {
      setLoading(true);
      setError(null);
      
      if (action === 'running') {
        const config = {
          populationSize: swarmConfig.populationSize,
          inertiaWeight: swarmConfig.inertiaWeight,
          cognitiveCoeff: swarmConfig.cognitiveCoeff,
          socialCoeff: swarmConfig.socialCoeff,
          maxIterations: swarmConfig.maxIterations,
          convergenceThreshold: swarmConfig.convergenceThreshold,
          riskTolerance: swarmConfig.riskTolerance,
          autoOptimize: autoOptimize,
        };
        
        await swarmAPI.startSwarm(config);
        setSwarmState('running');
      } else if (action === 'stopped') {
        await swarmAPI.stopSwarm();
        setSwarmState('stopped');
      } else {
        setSwarmState(action);
      }
      
      // Refresh data after state change
      setTimeout(() => fetchSwarmData(), 1000);
      
    } catch (err) {
      console.error('Error controlling swarm:', err);
      setError(`Failed to ${action} swarm: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleConfigChange = (key, value) => {
    setSwarmConfig(prev => ({
      ...prev,
      [key]: value,
    }));
  };

  const resetSwarm = async () => {
    try {
      setLoading(true);
      await swarmAPI.stopSwarm();
      setSwarmState('stopped');
      setTimeout(() => fetchSwarmData(), 1000);
    } catch (err) {
      console.error('Error resetting swarm:', err);
      setError(`Failed to reset swarm: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'active':
        return 'success';
      case 'paused':
        return 'warning';
      case 'optimizing':
        return 'info';
      default:
        return 'default';
    }
  };

  const filteredAgents = selectedStrategy === 'all' 
    ? agents 
    : agents.filter(agent => agent.strategy === selectedStrategy);

  return (
    <Box sx={{ flexGrow: 1 }}>
      {/* Header */}
      <Box sx={{ mb: 4 }}>
        <Typography variant="h3" component="h1" fontWeight={700} gutterBottom>
          AI Swarm Control Center
          {loading && <CircularProgress size={30} sx={{ ml: 2 }} />}
        </Typography>
        <Typography variant="body1" color="text.secondary">
          Configure and monitor your Particle Swarm Optimization agents
        </Typography>
        
        {/* Error Display */}
        {error && (
          <Alert severity="error" sx={{ mt: 2 }} onClose={() => setError(null)}>
            {error}
          </Alert>
        )}
        
        {/* Status Display */}
        <Box sx={{ mt: 2, display: 'flex', alignItems: 'center', gap: 2 }}>
          <Chip
            label={`Status: ${swarmState.toUpperCase()}`}
            color={swarmState === 'running' ? 'success' : swarmState === 'paused' ? 'warning' : 'default'}
            icon={swarmState === 'running' ? <CheckCircle /> : <Warning />}
          />
          <Typography variant="body2" color="text.secondary">
            Active Agents: {agents.length}
          </Typography>
          <IconButton onClick={fetchSwarmData} disabled={loading} title="Refresh Data">
            <Refresh />
          </IconButton>
        </Box>
      </Box>

      {/* Control Panel */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} md={8}>
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Swarm Control
              </Typography>
              
              <Box sx={{ display: 'flex', gap: 2, mb: 3 }}>
                <Button
                  variant={swarmState === 'running' ? 'contained' : 'outlined'}
                  startIcon={<PlayArrow />}
                  onClick={() => handleSwarmControl('running')}
                  color="success"
                >
                  Start Swarm
                </Button>
                <Button
                  variant={swarmState === 'paused' ? 'contained' : 'outlined'}
                  startIcon={<Pause />}
                  onClick={() => handleSwarmControl('paused')}
                  color="warning"
                >
                  Pause
                </Button>
                <Button
                  variant="outlined"
                  startIcon={<Stop />}
                  onClick={() => handleSwarmControl('stopped')}
                  color="error"
                >
                  Stop
                </Button>
                <Button
                  variant="outlined"
                  startIcon={<Settings />}
                  onClick={resetSwarm}
                >
                  Reset Swarm
                </Button>
              </Box>

              <Alert 
                severity={swarmState === 'running' ? 'success' : 'info'} 
                sx={{ mb: 3 }}
              >
                Swarm Status: {swarmState.toUpperCase()}
                {swarmState === 'running' && ' - Agents are actively optimizing strategies'}
                {swarmState === 'paused' && ' - Swarm execution paused'}
                {swarmState === 'stopped' && ' - All agents stopped'}
              </Alert>

              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <Box>
                  <Typography variant="body2" color="text.secondary" gutterBottom>
                    Filter by Strategy:
                  </Typography>
                  <FormControl size="small" sx={{ minWidth: 200 }}>
                    <Select
                      value={selectedStrategy}
                      onChange={(e) => setSelectedStrategy(e.target.value)}
                    >
                      <MenuItem value="all">All Strategies</MenuItem>
                      <MenuItem value="Yield Farming">Yield Farming</MenuItem>
                      <MenuItem value="Arbitrage">Arbitrage</MenuItem>
                      <MenuItem value="Liquidity Providing">Liquidity Providing</MenuItem>
                      <MenuItem value="Portfolio Rebalancing">Portfolio Rebalancing</MenuItem>
                    </Select>
                  </FormControl>
                </Box>
                <FormControlLabel
                  control={
                    <Switch
                      checked={autoOptimize}
                      onChange={(e) => setAutoOptimize(e.target.checked)}
                    />
                  }
                  label="Auto-optimize parameters"
                />
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={4}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Quick Stats
              </Typography>
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Active Agents
                  </Typography>
                  <Typography variant="h4" color="success.main">
                    {agents.filter(a => a.status === 'active').length}
                  </Typography>
                </Box>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Average Success Rate
                  </Typography>
                  <Typography variant="h4" color="primary.main">
                    {(agents.reduce((sum, a) => sum + a.successRate, 0) / agents.length).toFixed(1)}%
                  </Typography>
                </Box>
                <Box>
                  <Typography variant="body2" color="text.secondary">
                    Total Profit
                  </Typography>
                  <Typography variant="h4" color="warning.main">
                    {agents.reduce((sum, a) => sum + a.profit, 0).toFixed(3)} ALGO
                  </Typography>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Swarm Visualization */}
      <Grid container spacing={3} sx={{ mb: 4 }}>
        <Grid item xs={12} md={8}>
          <Card sx={{ height: 400 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Swarm Position Visualization
              </Typography>
              <ResponsiveContainer width="100%" height={320}>
                <ScatterChart>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                  <XAxis 
                    type="number" 
                    dataKey="x" 
                    domain={[0, 100]} 
                    stroke="#B0B7C3"
                    label={{ value: 'Solution Space X', position: 'insideBottom', offset: -10 }}
                  />
                  <YAxis 
                    type="number" 
                    dataKey="y" 
                    domain={[0, 100]} 
                    stroke="#B0B7C3"
                    label={{ value: 'Solution Space Y', angle: -90, position: 'insideLeft' }}
                  />
                  <Tooltip 
                    formatter={(value, name, props) => [
                      `Agent: ${props.payload.name}`,
                      `Strategy: ${props.payload.strategy}`,
                      `Profit: ${props.payload.profit.toFixed(3)} ALGO`,
                    ]}
                    contentStyle={{
                      backgroundColor: '#1A1F2E',
                      border: '1px solid rgba(0, 229, 255, 0.3)',
                      borderRadius: '8px',
                    }}
                  />
                  <Scatter 
                    data={filteredAgents.map(agent => ({
                      ...agent.position,
                      ...agent,
                    }))}
                    fill={(entry) => strategyColors[entry.strategy] || '#8884d8'}
                  >
                    {filteredAgents.map((agent, index) => (
                      <Cell key={index} fill={strategyColors[agent.strategy]} />
                    ))}
                  </Scatter>
                </ScatterChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={4}>
          <Card sx={{ height: 400 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                PSO Parameters
              </Typography>
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                <Box>
                  <Typography variant="body2" gutterBottom>
                    Population Size: {swarmConfig.populationSize}
                  </Typography>
                  <Slider
                    value={swarmConfig.populationSize}
                    onChange={(e, value) => handleConfigChange('populationSize', value)}
                    min={10}
                    max={50}
                    disabled={swarmState === 'running' && !autoOptimize}
                  />
                </Box>
                
                <Box>
                  <Typography variant="body2" gutterBottom>
                    Inertia Weight: {swarmConfig.inertiaWeight}
                  </Typography>
                  <Slider
                    value={swarmConfig.inertiaWeight}
                    onChange={(e, value) => handleConfigChange('inertiaWeight', value)}
                    min={0.1}
                    max={1.0}
                    step={0.1}
                    disabled={swarmState === 'running' && !autoOptimize}
                  />
                </Box>

                <Box>
                  <Typography variant="body2" gutterBottom>
                    Risk Tolerance: {swarmConfig.riskTolerance}
                  </Typography>
                  <Slider
                    value={swarmConfig.riskTolerance}
                    onChange={(e, value) => handleConfigChange('riskTolerance', value)}
                    min={0.1}
                    max={0.8}
                    step={0.1}
                    disabled={swarmState === 'running' && !autoOptimize}
                  />
                </Box>

                <Divider />

                <TextField
                  label="Max Iterations"
                  type="number"
                  value={swarmConfig.maxIterations}
                  onChange={(e) => handleConfigChange('maxIterations', parseInt(e.target.value))}
                  size="small"
                  disabled={swarmState === 'running'}
                />
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Agent List */}
      <Card>
        <CardContent>
          <Typography variant="h6" gutterBottom>
            Individual Agents ({filteredAgents.length})
          </Typography>
          <Grid container spacing={2}>
            {filteredAgents.map((agent) => (
              <Grid item xs={12} sm={6} md={4} lg={3} key={agent.id}>
                <Box
                  sx={{
                    p: 2,
                    borderRadius: 2,
                    border: '1px solid rgba(255, 255, 255, 0.1)',
                    background: `linear-gradient(135deg, ${strategyColors[agent.strategy]}15 0%, ${strategyColors[agent.strategy]}05 100%)`,
                  }}
                >
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                    <Typography variant="subtitle2" fontWeight={600}>
                      {agent.name}
                    </Typography>
                    <Chip
                      size="small"
                      label={agent.status}
                      color={getStatusColor(agent.status)}
                      variant="outlined"
                    />
                  </Box>
                  
                  <Typography variant="body2" color="text.secondary" gutterBottom>
                    {agent.strategy}
                  </Typography>
                  
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', mt: 2 }}>
                    <Box>
                      <Typography variant="body2" color="text.secondary">
                        Profit
                      </Typography>
                      <Typography variant="body2" fontWeight={600} color={agent.profit >= 0 ? 'success.main' : 'error.main'}>
                        {agent.profit >= 0 ? '+' : ''}{agent.profit.toFixed(3)}
                      </Typography>
                    </Box>
                    <Box sx={{ textAlign: 'right' }}>
                      <Typography variant="body2" color="text.secondary">
                        Success Rate
                      </Typography>
                      <Typography variant="body2" fontWeight={600}>
                        {agent.successRate.toFixed(1)}%
                      </Typography>
                    </Box>
                  </Box>
                </Box>
              </Grid>
            ))}
          </Grid>
        </CardContent>
      </Card>
    </Box>
  );
}

export default SwarmControl;