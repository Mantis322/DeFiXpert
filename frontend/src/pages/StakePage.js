import React, { useState, useEffect } from 'react';
import { 
  Box, 
  Container, 
  Typography, 
  Card, 
  CardContent, 
  Grid, 
  Tabs, 
  Tab, 
  TextField, 
  Button, 
  Table, 
  TableBody, 
  TableCell, 
  TableContainer, 
  TableHead, 
  TableRow, 
  Paper, 
  Chip, 
  Alert, 
  CircularProgress, 
  FormControl, 
  InputLabel, 
  Select, 
  MenuItem,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  List,
  ListItem,
  ListItemText,
  LinearProgress,
  Divider
} from '@mui/material';
import {
  AccountBalanceWallet as WalletIcon,
  TrendingUp as TrendingUpIcon,
  TrendingDown as TrendingDownIcon,
  Refresh as RefreshIcon,
  Security as SecurityIcon,
  SmartToy as AIIcon,
  CheckCircle as CheckIcon,
  Warning as WarningIcon
} from '@mui/icons-material';
import { useAuth } from '../contexts/AuthContext';
import { signTransaction, waitForConfirmation } from '../utils/algorand';

const StakePage = () => {
  const { user, isConnected, walletAddress, accountInfo, connector } = useAuth();
  const [currentTab, setCurrentTab] = useState(0);
  const [stakeAmount, setStakeAmount] = useState('');
  const [selectedStrategy, setSelectedStrategy] = useState('');
  const [riskPreference, setRiskPreference] = useState('medium');
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [selectedInvestment, setSelectedInvestment] = useState('');
  
  // State for data
  const [investments, setInvestments] = useState([]);
  const [strategies, setStrategies] = useState([]);
  const [transactionHistory, setTransactionHistory] = useState([]);
  const [userBalance, setUserBalance] = useState({ total_staked: 0, available_balance: 0 });
  const [loading, setLoading] = useState(false);
  const [alert, setAlert] = useState({ open: false, message: '', severity: 'success' });
  
  // New state for AI recommendations and real transactions
  const [availableProtocols, setAvailableProtocols] = useState([]);
  const [aiRecommendations, setAIRecommendations] = useState(null);
  const [selectedProtocol, setSelectedProtocol] = useState('');
  const [transactionDialog, setTransactionDialog] = useState({ open: false, step: 0, data: null });
  const [transactionStatus, setTransactionStatus] = useState(null);

  // API base URL
  const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8052';

  // API helper function
  const apiCall = async (endpoint, options = {}) => {
    try {
      const response = await fetch(`${API_BASE}/api/v1${endpoint}`, {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': walletAddress ? `Wallet ${walletAddress}` : '',
          ...options.headers
        },
        ...options
      });

      const data = await response.json();
      
      if (!response.ok) {
        throw new Error(data.error || 'API request failed');
      }
      
      return data;
    } catch (error) {
      console.error('API Error:', error);
      throw error;
    }
  };

  // Load initial data
  useEffect(() => {
    if (isConnected && walletAddress) {
      loadUserData();
    }
  }, [isConnected, walletAddress]);

  const loadUserData = async () => {
    setLoading(true);
    try {
      const [investmentsData, strategiesData, historyData, balanceData, protocolsData] = await Promise.all([
        apiCall('/stake/investments'),
        apiCall('/stake/strategies'),
        apiCall('/stake/history?limit=20'),
        apiCall('/stake/balance'),
        apiCall('/ai/protocols')  // Load available DeFi protocols
      ]);

      setInvestments(investmentsData.investments || []);
      setStrategies(strategiesData.strategies || []);
      setTransactionHistory(historyData.transactions || []);
      setUserBalance(balanceData);
      setAvailableProtocols(protocolsData.protocols || []);
    } catch (error) {
      console.error('Error loading user data:', error);
      showAlert('Error loading data: ' + error.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  const showAlert = (message, severity = 'success') => {
    setAlert({ open: true, message, severity });
    setTimeout(() => setAlert({ open: false, message: '', severity: 'success' }), 5000);
  };

  // Get AI Strategy Recommendations
  const getAIRecommendations = async () => {
    if (!stakeAmount || parseFloat(stakeAmount) <= 0) {
      showAlert('Enter a valid stake amount first', 'error');
      return;
    }

    setLoading(true);
    try {
      const microAlgos = Math.round(parseFloat(stakeAmount) * 1000000);
      
      const recommendations = await apiCall('/ai/strategy/recommend', {
        method: 'POST',
        body: JSON.stringify({
          amount_microalgo: microAlgos,
          risk_preference: riskPreference
        })
      });

      if (recommendations.status === 'success') {
        setAIRecommendations(recommendations);
        showAlert(`AI found ${recommendations.recommendations.length} suitable protocols for your investment`, 'success');
      } else {
        showAlert('AI recommendation failed: ' + recommendations.error, 'error');
      }
    } catch (error) {
      console.error('Error getting AI recommendations:', error);
      showAlert('Error getting AI recommendations: ' + error.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  // Create and execute real DeFi transaction
  const executeRealTransaction = async (protocolName, allocationAmount) => {
    setTransactionDialog({ open: true, step: 1, data: { protocol: protocolName, amount: allocationAmount } });
    
    try {
      // Step 1: Create unsigned transaction
      setTransactionStatus('Creating transaction...');
      const txResponse = await apiCall('/defi/transaction/create-deposit', {
        method: 'POST',
        body: JSON.stringify({
          protocol_name: protocolName,
          amount_microalgo: allocationAmount
        })
      });

      if (txResponse.status !== 'success') {
        throw new Error(txResponse.error || 'Failed to create transaction');
      }

      setTransactionDialog(prev => ({ ...prev, step: 2, data: { ...prev.data, unsignedTx: txResponse } }));

      // Step 2: Sign transaction with Pera Wallet
      setTransactionStatus('Waiting for wallet signature...');
      const signedTx = await signTransaction(txResponse.unsigned_transaction, connector);
      
      if (!signedTx) {
        throw new Error('Transaction was not signed');
      }

      setTransactionDialog(prev => ({ ...prev, step: 3, data: { ...prev.data, signedTx } }));

      // Step 3: Submit and confirm transaction
      setTransactionStatus('Submitting transaction to blockchain...');
      const completeResult = await apiCall('/defi/transaction/complete', {
        method: 'POST',
        body: JSON.stringify({
          protocol_name: protocolName,
          amount_microalgo: allocationAmount,
          signed_transaction: signedTx
        })
      });

      if (completeResult.status === 'success' || completeResult.confirmed) {
        setTransactionDialog(prev => ({ ...prev, step: 4, data: { ...prev.data, result: completeResult } }));
        setTransactionStatus('Transaction confirmed!');
        showAlert(`Successfully deposited ${(allocationAmount / 1000000).toFixed(2)} ALGO to ${protocolName}`, 'success');
        
        // Reload user data
        loadUserData();
      } else {
        throw new Error(completeResult.error || 'Transaction failed to confirm');
      }

    } catch (error) {
      console.error('Real transaction error:', error);
      showAlert('Transaction failed: ' + error.message, 'error');
      setTransactionDialog(prev => ({ ...prev, step: -1, data: { ...prev.data, error: error.message } }));
    }
  };

  // Handle stake submission with AI recommendations
  const handleStake = async (e) => {
    e.preventDefault();
    if (!stakeAmount || parseFloat(stakeAmount) <= 0) {
      showAlert('Enter a valid stake amount', 'error');
      return;
    }

    if (!aiRecommendations) {
      showAlert('Please get AI recommendations first', 'warning');
      return;
    }

    setLoading(true);
    try {
      // Execute transactions for each AI recommendation
      for (const recommendation of aiRecommendations.recommendations) {
        await executeRealTransaction(recommendation.protocol, recommendation.allocation_amount);
        
        // Small delay between transactions to prevent issues
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
      
      // Clear form after successful transactions
      setStakeAmount('');
      setSelectedStrategy('');
      setAIRecommendations(null);
      
    } catch (error) {
      console.error('Error in stake transaction:', error);
      showAlert('Stake failed: ' + error.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  // Handle stake submission (OLD - database only, kept for fallback)
  const handleDatabaseStake = async (e) => {
    e.preventDefault();
    if (!stakeAmount || parseFloat(stakeAmount) <= 0) {
      showAlert('Enter a valid stake amount', 'error');
      return;
    }

    setLoading(true);
    try {
      // Convert ALGO to microALGO (1 ALGO = 1,000,000 microALGO)
      const microAlgos = Math.round(parseFloat(stakeAmount) * 1000000);
      
      await apiCall('/stake/algo', {
        method: 'POST',
        body: JSON.stringify({
          amount: microAlgos,
          ai_strategy_id: selectedStrategy || null
        })
      });

      showAlert('Successfully staked! 🎉');
      setStakeAmount('');
      setSelectedStrategy('');
      loadUserData(); // Refresh data
    } catch (error) {
      showAlert('Stake operation failed: ' + error.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  // Handle withdraw submission
  const handleWithdraw = async (e) => {
    e.preventDefault();
    if (!withdrawAmount || !selectedInvestment) {
      showAlert('Select investment and enter withdraw amount', 'error');
      return;
    }

    setLoading(true);
    try {
      const microAlgos = Math.round(parseFloat(withdrawAmount) * 1000000);
      
      const result = await apiCall('/stake/withdraw', {
        method: 'POST',
        body: JSON.stringify({
          investment_id: parseInt(selectedInvestment),
          amount: microAlgos
        })
      });

      showAlert(`Successfully withdrawn! Net amount: ${(result.withdrawn_amount / 1000000).toFixed(6)} ALGO 💰`);
      setWithdrawAmount('');
      setSelectedInvestment('');
      loadUserData(); // Refresh data
    } catch (error) {
      showAlert('Withdrawal failed: ' + error.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  // Format functions
  const formatAlgo = (microAlgos) => {
    if (!microAlgos) return '0.000000';
    // Handle BigInt conversion for Algorand wallet amounts
    const amount = typeof microAlgos === 'bigint' ? Number(microAlgos) : microAlgos;
    return (amount / 1000000).toFixed(6);
  };

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const getRiskColor = (risk) => {
    switch(risk) {
      case 'low': return 'success';
      case 'medium': return 'warning';
      case 'high': return 'error';
      default: return 'default';
    }
  };

  const getStatusColor = (status) => {
    switch(status) {
      case 'active': return 'success';
      case 'confirmed': return 'success';
      case 'pending': return 'warning';
      case 'failed': return 'error';
      default: return 'default';
    }
  };

  const handleTabChange = (event, newValue) => {
    setCurrentTab(newValue);
  };

  if (!isConnected) {
    return (
      <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
        <Alert severity="warning" sx={{ mb: 2 }}>
          <Typography variant="h6">Wallet Connection Required</Typography>
          <Typography>
            Please connect your wallet first to perform stake operations.
          </Typography>
        </Alert>
      </Container>
    );
  }

  return (
    <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
      {/* Alert */}
      {alert.open && (
        <Alert 
          severity={alert.severity} 
          sx={{ mb: 2 }}
          onClose={() => setAlert({ open: false, message: '', severity: 'success' })}
        >
          {alert.message}
        </Alert>
      )}

      {/* Header */}
      <Box sx={{ mb: 3 }}>
        <Typography variant="h3" component="h1" gutterBottom sx={{ fontWeight: 'bold' }}>
          💰 Algorand Stake & AI Investment
        </Typography>
        <Typography variant="h6" color="text.secondary">
          Stake your ALGO and earn with AI-powered investment strategies
        </Typography>
      </Box>

      {/* Balance Cards */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
                <WalletIcon color="primary" sx={{ mr: 1 }} />
                <Typography color="text.secondary" variant="body2">
                  Wallet Balance
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ fontWeight: 'bold' }}>
                {accountInfo ? formatAlgo(accountInfo.amount) : '0.000000'}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                ALGO
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
                <TrendingUpIcon color="success" sx={{ mr: 1 }} />
                <Typography color="text.secondary" variant="body2">
                  Total Staked
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ fontWeight: 'bold' }} color="success.main">
                {formatAlgo(userBalance.total_staked)}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                ALGO
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
                <TrendingDownIcon color="info" sx={{ mr: 1 }} />
                <Typography color="text.secondary" variant="body2">
                  Available Balance
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ fontWeight: 'bold' }} color="info.main">
                {formatAlgo(userBalance.available_balance)}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                ALGO
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
                <SecurityIcon color="secondary" sx={{ mr: 1 }} />
                <Typography color="text.secondary" variant="body2">
                  Active Investments
                </Typography>
              </Box>
              <Typography variant="h4" sx={{ fontWeight: 'bold' }} color="secondary.main">
                {investments.length}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Count
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Main Content */}
      <Card>
        <CardContent>
          <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 3 }}>
            <Tabs value={currentTab} onChange={handleTabChange}>
              <Tab label="💎 Stake" />
              <Tab label="💸 Withdraw" />
              <Tab label="📊 Investments" />
              <Tab label="📋 History" />
            </Tabs>
          </Box>

          {/* Stake Tab */}
          {currentTab === 0 && (
            <Box>
              {/* Real Money Warning Alert */}
              <Alert severity="warning" sx={{ mb: 3 }}>
                <Typography variant="body2">
                  <strong>� Real Money Operations:</strong> This system now uses real ALGO transactions. 
                  All investments will be made to actual DeFi protocols. Ensure you understand the risks before proceeding.
                </Typography>
              </Alert>

              {/* Stake Amount Input */}
              <Paper elevation={3} sx={{ p: 3, mb: 3 }}>
                <Typography variant="h6" gutterBottom>
                  💎 Step 1: Enter Stake Amount
                </Typography>
                <TextField
                  fullWidth
                  label="Stake Amount (ALGO)"
                  type="number"
                  value={stakeAmount}
                  onChange={(e) => setStakeAmount(e.target.value)}
                  placeholder="e.g: 100"
                  inputProps={{ step: "0.000001", min: "1" }}
                  sx={{ mb: 2 }}
                  helperText="Minimum: 1 ALGO"
                />
                
                <FormControl fullWidth sx={{ mb: 2 }}>
                  <InputLabel>Risk Preference</InputLabel>
                  <Select
                    value={riskPreference}
                    label="Risk Preference"
                    onChange={(e) => setRiskPreference(e.target.value)}
                  >
                    <MenuItem value="low">🛡️ Low Risk (Stable Returns)</MenuItem>
                    <MenuItem value="medium">⚖️ Medium Risk (Balanced)</MenuItem>
                    <MenuItem value="high">🚀 High Risk (Maximum Returns)</MenuItem>
                  </Select>
                </FormControl>

                <Button
                  variant="outlined"
                  size="large"
                  fullWidth
                  onClick={getAIRecommendations}
                  disabled={loading || !stakeAmount || parseFloat(stakeAmount) < 1}
                  startIcon={loading ? <CircularProgress size={20} /> : <AIIcon />}
                  sx={{ mb: 2 }}
                >
                  {loading ? 'Getting AI Recommendations...' : 'Get AI Strategy Recommendations'}
                </Button>
              </Paper>

              {/* AI Recommendations */}
              {aiRecommendations && (
                <Paper elevation={3} sx={{ p: 3, mb: 3 }}>
                  <Typography variant="h6" gutterBottom sx={{ display: 'flex', alignItems: 'center' }}>
                    <AIIcon color="primary" sx={{ mr: 1 }} />
                    Step 2: AI Strategy Recommendations
                  </Typography>
                  
                  <Alert severity="success" sx={{ mb: 2 }}>
                    <Typography variant="body2">
                      AI analyzed your investment and found {aiRecommendations.recommendations.length} suitable protocols 
                      with {aiRecommendations.overall_safety_score}% overall safety score.
                      {aiRecommendations.arbitrage_opportunities_count && 
                        ` Found ${aiRecommendations.arbitrage_opportunities_count} live arbitrage opportunities.`}
                    </Typography>
                  </Alert>

                  <Grid container spacing={2} sx={{ mb: 2 }}>
                    {aiRecommendations.recommendations.map((rec, index) => (
                      <Grid item xs={12} md={6} key={index}>
                        <Card variant="outlined" sx={{ height: '100%' }}>
                          <CardContent>
                            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
                              <Typography variant="h6" gutterBottom>
                                {rec.protocol_info.name}
                              </Typography>
                              {rec.type === 'arbitrage' && (
                                <Chip 
                                  label="🔄 Arbitrage"
                                  color="secondary"
                                  size="small"
                                />
                              )}
                              {rec.type === 'staking' && (
                                <Chip 
                                  label="💎 Staking"
                                  color="primary"
                                  size="small"
                                />
                              )}
                            </Box>
                            
                            <Box sx={{ mb: 2 }}>
                              <Chip 
                                label={`${rec.allocation_percentage}% allocation`}
                                color="primary"
                                size="small"
                                sx={{ mr: 1, mb: 1 }}
                              />
                              <Chip 
                                label={`${rec.safety_score}% safe`}
                                color={rec.safety_score >= 90 ? "success" : rec.safety_score >= 70 ? "warning" : "error"}
                                size="small"
                                sx={{ mr: 1, mb: 1 }}
                              />
                              <Chip 
                                label={`${rec.protocol_info.risk_level} risk`}
                                color={getRiskColor(rec.protocol_info.risk_level)}
                                size="small"
                                sx={{ mb: 1 }}
                              />
                            </Box>

                            <Typography variant="body2" color="success.main" sx={{ mb: 1 }}>
                              Amount: {(rec.allocation_amount / 1000000).toFixed(2)} ALGO
                            </Typography>
                            <Typography variant="body2" color="success.main" sx={{ mb: 1 }}>
                              Est. Monthly Return: {(rec.estimated_monthly_return / 1000000).toFixed(4)} ALGO
                            </Typography>
                            
                            {/* Special display for arbitrage opportunities */}
                            {rec.type === 'arbitrage' && rec.arbitrage_details && (
                              <Box sx={{ mt: 1, p: 1, bgcolor: 'action.hover', borderRadius: 1 }}>
                                <Typography variant="caption" color="text.secondary">
                                  Spread: {rec.arbitrage_details.spread_percentage.toFixed(2)}%
                                </Typography>
                                <Typography variant="caption" display="block" color="text.secondary">
                                  {rec.arbitrage_details.buy_exchange} → {rec.arbitrage_details.sell_exchange}
                                </Typography>
                              </Box>
                            )}
                            
                            <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
                              {rec.reason}
                            </Typography>
                          </CardContent>
                        </Card>
                      </Grid>
                    ))}
                  </Grid>

                  <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                    Total Monthly Return Estimate: {(aiRecommendations.estimated_total_monthly_return / 1000000).toFixed(4)} ALGO
                  </Typography>
                </Paper>
              )}

              {/* Execute Transaction */}
              {aiRecommendations && (
                <Paper elevation={3} sx={{ p: 3 }}>
                  <Typography variant="h6" gutterBottom>
                    💎 Step 3: Execute Investment
                  </Typography>
                  <Box component="form" onSubmit={handleStake}>
                    <Button
                      type="submit"
                      variant="contained"
                      size="large"
                      fullWidth
                      disabled={loading}
                      startIcon={loading ? <CircularProgress size={20} /> : <WalletIcon />}
                      color="primary"
                    >
                      {loading ? 'Processing Real Transactions...' : 'Execute AI Strategy (Real ALGO)'}
                    </Button>
                  </Box>
                </Paper>
              )}

              {/* Available DeFi Protocols Info */}
              <Paper elevation={1} sx={{ p: 2, mt: 3, bgcolor: 'grey.50' }}>
                <Typography variant="subtitle2" gutterBottom>
                  Available DeFi Protocols:
                </Typography>
                <Grid container spacing={1}>
                  {availableProtocols.map((protocol) => (
                    <Grid item xs={12} sm={4} key={protocol.id}>
                      <Chip 
                        label={`${protocol.name} (${protocol.estimated_apy * 100}% APY)`}
                        size="small"
                        color={getRiskColor(protocol.risk_level)}
                        variant="outlined"
                      />
                    </Grid>
                  ))}
                </Grid>
              </Paper>
            </Box>
          )}

          {/* Withdraw Tab */}
          {currentTab === 1 && (
            <Box>
              <Typography variant="h5" gutterBottom>
                💸 Withdraw Funds
              </Typography>
              
              <Paper elevation={3} sx={{ p: 3 }}>
                <Box component="form" onSubmit={handleWithdraw}>
                  <FormControl fullWidth sx={{ mb: 2 }}>
                    <InputLabel>Select Investment</InputLabel>
                    <Select
                      value={selectedInvestment}
                      label="Select Investment"
                      onChange={(e) => setSelectedInvestment(e.target.value)}
                      required
                    >
                      {investments
                        .filter(inv => inv.stake_status === 'active' && inv.available_balance > 0)
                        .map((investment) => (
                        <MenuItem key={investment.id} value={investment.id}>
                          ID: {investment.id} - Available: {formatAlgo(investment.available_balance)} ALGO
                        </MenuItem>
                      ))}
                    </Select>
                  </FormControl>
                  
                  <TextField
                    fullWidth
                    label="Withdraw Amount (ALGO)"
                    type="number"
                    value={withdrawAmount}
                    onChange={(e) => setWithdrawAmount(e.target.value)}
                    placeholder="Amount to withdraw"
                    inputProps={{ step: "0.000001", min: "0" }}
                    sx={{ mb: 2 }}
                    required
                  />
                  
                  <Button
                    type="submit"
                    variant="contained"
                    size="large"
                    fullWidth
                    disabled={loading}
                    color="secondary"
                    startIcon={loading ? <CircularProgress size={20} /> : <TrendingDownIcon />}
                  >
                    {loading ? 'Processing...' : 'Withdraw'}
                  </Button>
                </Box>
              </Paper>
            </Box>
          )}

          {/* Investments Tab */}
          {currentTab === 2 && (
            <Box>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                <Typography variant="h5">
                  📊 Active Investments
                </Typography>
                <IconButton onClick={loadUserData} disabled={loading}>
                  <RefreshIcon />
                </IconButton>
              </Box>
              
              <TableContainer component={Paper}>
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>ID</TableCell>
                      <TableCell>Stake Amount</TableCell>
                      <TableCell>Available</TableCell>
                      <TableCell>Total Earnings</TableCell>
                      <TableCell>AI Strategy</TableCell>
                      <TableCell>Status</TableCell>
                      <TableCell>Date</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {investments.map((investment) => (
                      <TableRow key={investment.id}>
                        <TableCell>{investment.id}</TableCell>
                        <TableCell>{formatAlgo(investment.staked_amount)} ALGO</TableCell>
                        <TableCell>
                          <Typography color="success.main">
                            {formatAlgo(investment.available_balance)} ALGO
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography color="secondary.main">
                            {formatAlgo(investment.total_earnings)} ALGO
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Box>
                            <Typography variant="body2">
                              {investment.strategy_name || 'Basic Interest'}
                            </Typography>
                            {investment.risk_level && (
                              <Chip 
                                label={investment.risk_level}
                                color={getRiskColor(investment.risk_level)}
                                size="small"
                              />
                            )}
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Chip 
                            label={investment.stake_status}
                            color={getStatusColor(investment.stake_status)}
                            size="small"
                          />
                        </TableCell>
                        <TableCell>{formatDate(investment.created_at)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            </Box>
          )}

          {/* History Tab */}
          {currentTab === 3 && (
            <Box>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                <Typography variant="h5">
                  📋 Transaction History
                </Typography>
                <IconButton onClick={loadUserData} disabled={loading}>
                  <RefreshIcon />
                </IconButton>
              </Box>
              
              <TableContainer component={Paper}>
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>ID</TableCell>
                      <TableCell>Transaction Type</TableCell>
                      <TableCell>Amount</TableCell>
                      <TableCell>Status</TableCell>
                      <TableCell>Date</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {transactionHistory.map((tx) => (
                      <TableRow key={tx.id}>
                        <TableCell>{tx.id}</TableCell>
                        <TableCell>
                          <Chip 
                            label={tx.transaction_type}
                            color={
                              tx.transaction_type === 'stake' ? 'primary' :
                              tx.transaction_type === 'withdraw' ? 'secondary' : 'success'
                            }
                            size="small"
                          />
                        </TableCell>
                        <TableCell>{formatAlgo(tx.amount)} ALGO</TableCell>
                        <TableCell>
                          <Chip 
                            label={tx.status}
                            color={getStatusColor(tx.status)}
                            size="small"
                          />
                        </TableCell>
                        <TableCell>{formatDate(tx.created_at)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            </Box>
          )}
        </CardContent>
      </Card>

      {/* Loading Overlay */}
      {loading && (
        <Box
          sx={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            bgcolor: 'rgba(0, 0, 0, 0.5)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 9999
          }}
        >
          <Paper sx={{ p: 3, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <CircularProgress sx={{ mb: 2 }} />
            <Typography>Processing transaction...</Typography>
          </Paper>
        </Box>
      )}
      
      {/* Real Transaction Dialog */}
      <Dialog
        open={transactionDialog.open}
        maxWidth="md"
        fullWidth
        onClose={() => setTransactionDialog({ open: false, step: 0, data: null })}
      >
        <DialogTitle>
          {transactionDialog.step === -1 ? 'Transaction Failed' : 'Real DeFi Transaction Progress'}
        </DialogTitle>
        <DialogContent>
          {transactionDialog.step === -1 && (
            <Alert severity="error" sx={{ mb: 2 }}>
              <Typography variant="body2">
                Transaction failed: {transactionDialog.data?.error}
              </Typography>
            </Alert>
          )}
          
          {transactionDialog.step >= 1 && (
            <Box>
              <Typography variant="h6" gutterBottom>
                Protocol: {transactionDialog.data?.protocol}
              </Typography>
              <Typography variant="body1" sx={{ mb: 2 }}>
                Amount: {((transactionDialog.data?.amount || 0) / 1000000).toFixed(2)} ALGO
              </Typography>
              
              <List>
                <ListItem>
                  <ListItemText
                    primary="1. Create Transaction"
                    secondary={transactionDialog.step >= 1 ? "✅ Complete" : "⏳ Pending"}
                  />
                  {transactionDialog.step >= 1 && <CheckIcon color="success" />}
                </ListItem>
                
                <ListItem>
                  <ListItemText
                    primary="2. Sign with Wallet"
                    secondary={
                      transactionDialog.step >= 2 ? "✅ Complete" : 
                      transactionDialog.step === 1 ? "⏳ Waiting for signature..." : "🔲 Pending"
                    }
                  />
                  {transactionDialog.step >= 2 ? <CheckIcon color="success" /> : 
                   transactionDialog.step === 1 ? <CircularProgress size={20} /> : null}
                </ListItem>
                
                <ListItem>
                  <ListItemText
                    primary="3. Submit to Blockchain"
                    secondary={
                      transactionDialog.step >= 3 ? "✅ Complete" : 
                      transactionDialog.step === 2 ? "⏳ Submitting..." : "🔲 Pending"
                    }
                  />
                  {transactionDialog.step >= 3 ? <CheckIcon color="success" /> : 
                   transactionDialog.step === 2 ? <CircularProgress size={20} /> : null}
                </ListItem>
                
                <ListItem>
                  <ListItemText
                    primary="4. Confirm Transaction"
                    secondary={
                      transactionDialog.step >= 4 ? "✅ Confirmed!" : 
                      transactionDialog.step === 3 ? "⏳ Waiting for confirmation..." : "🔲 Pending"
                    }
                  />
                  {transactionDialog.step >= 4 ? <CheckIcon color="success" /> : 
                   transactionDialog.step === 3 ? <CircularProgress size={20} /> : null}
                </ListItem>
              </List>
              
              {transactionDialog.step >= 4 && transactionDialog.data?.result && (
                <Alert severity="success" sx={{ mt: 2 }}>
                  <Typography variant="body2">
                    Transaction confirmed! TX ID: {transactionDialog.data.result.transaction_id}
                  </Typography>
                </Alert>
              )}
              
              {transactionStatus && (
                <Box sx={{ mt: 2 }}>
                  <LinearProgress sx={{ mb: 1 }} />
                  <Typography variant="body2" color="text.secondary">
                    {transactionStatus}
                  </Typography>
                </Box>
              )}
            </Box>
          )}
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={() => setTransactionDialog({ open: false, step: 0, data: null })}
            disabled={transactionDialog.step > 0 && transactionDialog.step < 4 && transactionDialog.step !== -1}
          >
            {transactionDialog.step === 4 || transactionDialog.step === -1 ? 'Close' : 'Cancel'}
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
};

export default StakePage;