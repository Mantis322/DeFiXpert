import React, { useState, useEffect, useCallback, useRef } from 'react';
import { useAuth } from '../contexts/AuthContext';
import RealTimePriceFeed from '../components/RealTimePriceFeed';
import { aiArbitrageEngine } from '../services/aiArbitrageEngine';
import algofiAPI from '../services/algofiAPI';
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
  PlayArrow,
  PlayArrow as PlayIcon,
  Pause as PauseIcon,
  Delete as DeleteIcon,
  Edit as EditIcon,
  TrendingUp,
  AccountBalance,
  Speed,
  Refresh,
  Timeline,
  Notifications,
  SmartToy,
  SignalCellularAlt,
  Visibility
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
  const [aiStrategies, setAiStrategies] = useState([]); // AI managed strategies
  const [opportunities, setOpportunities] = useState([]);
  const [realTimeOpportunities, setRealTimeOpportunities] = useState([]);
  const [liveDetectedOpportunities, setLiveDetectedOpportunities] = useState([]);
  const [aiSelectedOpportunities, setAiSelectedOpportunities] = useState([]);
  const [aiLoading, setAiLoading] = useState(false);
  const [currentPrices, setCurrentPrices] = useState({});
  const [priceHistory, setPriceHistory] = useState({});
  const [liveOpportunitiesFetching, setLiveOpportunitiesFetching] = useState(false);
  const [liveOpportunitiesInterval, setLiveOpportunitiesInterval] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [opportunitiesError, setOpportunitiesError] = useState(null);
  const [createDialog, setCreateDialog] = useState(false);
  const [editDialog, setEditDialog] = useState(false);
  const [selectedStrategy, setSelectedStrategy] = useState(null);
  const [selectedAiStrategy, setSelectedAiStrategy] = useState(null); // AI strategy selection
  const [tabValue, setTabValue] = useState(0);
  const [aiEngineRunning, setAiEngineRunning] = useState(false);
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

  // Load AI selected opportunities using Groq LLM
  const loadAiSelectedOpportunities = useCallback(async () => {
    try {
      setAiLoading(true);
      console.log('🤖 Loading AI selected opportunities...');
      
      // Get fresh opportunities data
      const opportunitiesResponse = await api.getArbitrageOpportunities();
      const allOpportunities = Array.isArray(opportunitiesResponse) ? opportunitiesResponse : [];
      
      if (allOpportunities.length === 0) {
        console.log('📊 No opportunities available for AI analysis');
        setAiSelectedOpportunities([]);
        return;
      }

      // Call AI analysis endpoint
      const response = await fetch(`${process.env.REACT_APP_API_URL || 'http://localhost:8052'}/api/v1/ai/analyze/opportunities`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          opportunities: allOpportunities,
          selection_criteria: {
            max_selections: 10,
            risk_preference: 'medium',
            min_profit_threshold: 0.0113
          }
        })
      });

      if (response.ok) {
        const aiAnalysis = await response.json();
        if (aiAnalysis.status === 'success') {
          console.log('✅ AI selected opportunities:', aiAnalysis.selected_opportunities.length);
          setAiSelectedOpportunities(aiAnalysis.selected_opportunities || []);
        } else {
          console.error('❌ AI analysis failed:', aiAnalysis.error);
          setAiSelectedOpportunities([]);
        }
      } else {
        console.error('❌ AI analysis API call failed');
        setAiSelectedOpportunities([]);
      }
    } catch (error) {
      console.error('Failed to load AI selected opportunities:', error);
      setAiSelectedOpportunities([]);
    } finally {
      setAiLoading(false);
    }
  }, [api]); // Only depend on api, remove state dependencies to prevent infinite loop

  // Live Opportunities Price Fetching - Similar to RealTimePriceFeed
  const liveOpportunitiesIntervalRef = useRef(null);

  // Filter function for ALGO/USD only
  const filterAlgoUsdOnly = (prices) => {
    console.log('🔍 Filtering prices for ALGO/USD only. Input:', prices);
    const filtered = {};
    if (prices['ALGO/USD']) {
      filtered['ALGO/USD'] = prices['ALGO/USD'];
      console.log('✅ Found ALGO/USD data:', prices['ALGO/USD']);
    } else {
      console.log('❌ No ALGO/USD data found in:', Object.keys(prices));
    }
    console.log('🎯 Filtered result:', filtered);
    return filtered;
  };

  // Fetch live prices for opportunities
  const fetchLivePricesForOpportunities = async () => {
    try {
      setLiveOpportunitiesFetching(true);
      console.log('🔄 Live Opportunities: Fetching ALGO/USD prices...');
      
      const response = await algofiAPI.getCurrentPrices();
      console.log('📥 Live Opportunities: Raw response:', response);
      
      const allPrices = response.prices || response;
      console.log('📊 Live Opportunities: All prices:', allPrices);
      
      // Filter for ALGO/USD only
      const prices = filterAlgoUsdOnly(allPrices);
      console.log('🎯 Live Opportunities: Filtered ALGO/USD prices:', prices);
      
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
                fee: 0.003 // Default 0.3% fee per exchange
              };
            });
          }
        });
        
        setCurrentPrices(timestampedPrices);
        
        // Store price history for trend detection
        setPriceHistory(prev => {
          const newHistory = { ...prev };
          Object.entries(timestampedPrices).forEach(([pair, exchanges]) => {
            if (!newHistory[pair]) newHistory[pair] = {};
            Object.entries(exchanges).forEach(([exchange, data]) => {
              if (!newHistory[pair][exchange]) newHistory[pair][exchange] = [];
              newHistory[pair][exchange].push({
                price: data.price,
                timestamp: timestamp.toISOString(),
                volume: data.volume_24h || 0
              });
              // Keep only last 10 price points per exchange
              if (newHistory[pair][exchange].length > 10) {
                newHistory[pair][exchange] = newHistory[pair][exchange].slice(-10);
              }
            });
          });
          return newHistory;
        });
        
        // Detect arbitrage opportunities
        detectLiveArbitrageOpportunities(timestampedPrices, timestamp);
        
        setOpportunitiesError(null);
        console.log('✅ Live Opportunities: Successfully processed price data');
      } else {
        console.warn('⚠️ Live Opportunities: No valid price data received');
        setOpportunitiesError('No price data available from backend');
      }
    } catch (error) {
      console.error('❌ Live Opportunities: Failed to fetch prices:', error);
      setOpportunitiesError(`Failed to fetch live prices: ${error.message}`);
    } finally {
      setLiveOpportunitiesFetching(false);
    }
  };

  // Detect arbitrage opportunities from live prices
  const detectLiveArbitrageOpportunities = (priceData, timestamp) => {
    console.log('🎯 Live Opportunities: Starting arbitrage detection with data:', priceData);
    const newOpportunities = [];
    
    Object.entries(priceData).forEach(([pair, exchanges]) => {
      console.log(`🔍 Analyzing pair ${pair} with exchanges:`, exchanges);
      const exchangeList = Object.entries(exchanges);
      console.log(`📊 Exchange list for ${pair}:`, exchangeList);
      
      // Compare all exchange pairs for arbitrage opportunities
      for (let i = 0; i < exchangeList.length; i++) {
        for (let j = i + 1; j < exchangeList.length; j++) {
          const [exchange1, data1] = exchangeList[i];
          const [exchange2, data2] = exchangeList[j];
          
          console.log(`🔄 Comparing ${exchange1} (${data1.price}) vs ${exchange2} (${data2.price})`);
          
          if (!data1.price || !data2.price) {
            console.log(`⚠️ Missing price data: ${exchange1}=${data1.price}, ${exchange2}=${data2.price}`);
            continue;
          }
          
          const price1 = data1.price;
          const price2 = data2.price;
          
          // Calculate spread percentage
          const spreadPct = Math.abs((price2 - price1) / Math.min(price1, price2)) * 100;
          
          // Estimate total fees (0.05% per exchange = 0.1% total, very optimistic for testing)
          const totalFees = 0.1; // 0.05% x 2 exchanges (very low for testing)
          const netProfitPct = spreadPct - totalFees;
          
          console.log(`📈 Spread analysis: ${exchange1} vs ${exchange2}: spread=${spreadPct.toFixed(4)}%, net_profit=${netProfitPct.toFixed(4)}%`);
          
          if (netProfitPct > 0.001) { // Minimum 0.001% profit after fees (very low for testing)
            console.log(`✅ Found arbitrage opportunity: ${netProfitPct.toFixed(2)}% profit`);
            const buyExchange = price1 < price2 ? exchange1 : exchange2;
            const sellExchange = price1 < price2 ? exchange2 : exchange1;
            const buyPrice = Math.min(price1, price2);
            const sellPrice = Math.max(price1, price2);
            
            // Estimate trade amounts based on volume
            const minVolume = Math.min(data1.volume_24h || 50000, data2.volume_24h || 50000);
            const minTradeAmount = Math.max(100, minVolume * 0.001); // 0.1% of daily volume
            const maxTradeAmount = Math.min(5000, minVolume * 0.01); // 1% of daily volume
            
            newOpportunities.push({
              id: `live-opp-${pair}-${buyExchange}-${sellExchange}-${timestamp.getTime()}`,
              asset_pair: pair,
              dex_1: buyExchange,
              dex_2: sellExchange,
              price_1: buyPrice,
              price_2: sellPrice,
              profit_percentage: netProfitPct,
              min_trade_amount: minTradeAmount,
              max_trade_amount: maxTradeAmount,
              is_active: true,
              expires_at: new Date(timestamp.getTime() + 15000).toISOString(), // 15 seconds
              created_at: timestamp.toISOString(),
              source: 'LIVE_OPPORTUNITIES',
              confidence: spreadPct > 1.0 ? 'HIGH' : spreadPct > 0.5 ? 'MEDIUM' : 'LOW',
              recommendation: `📈 Buy from ${(buyExchange || 'Unknown').toUpperCase()} at $${buyPrice.toFixed(4)} → Sell to ${(sellExchange || 'Unknown').toUpperCase()} at $${sellPrice.toFixed(4)}`
            });
          }
        }
      }
    });
    
    // Update live detected opportunities, removing expired ones
    setLiveDetectedOpportunities(prev => {
      const now = new Date();
      const validOpportunities = prev.filter(opp => new Date(opp.expires_at) > now);
      return [...validOpportunities, ...newOpportunities]
        .sort((a, b) => b.profit_percentage - a.profit_percentage) // Sort by profit desc
        .slice(0, 20); // Keep only top 20
    });
    
    console.log(`🎯 Live Opportunities: Detected ${newOpportunities.length} new arbitrage opportunities`);
  };

  // Start Live Opportunities price feed
  const startLiveOpportunitiesPriceFeed = () => {
    if (liveOpportunitiesIntervalRef.current) return;

    console.log('🚀 Starting Live Opportunities price feed...');
    setLiveOpportunitiesFetching(true);

    // Initial fetch
    fetchLivePricesForOpportunities();

    // Set up interval to fetch prices every 5 seconds (same as RealTimePriceFeed)
    liveOpportunitiesIntervalRef.current = setInterval(() => {
      fetchLivePricesForOpportunities();
    }, 5000);
  };

  // Stop Live Opportunities price feed
  const stopLiveOpportunitiesPriceFeed = () => {
    if (liveOpportunitiesIntervalRef.current) {
      clearInterval(liveOpportunitiesIntervalRef.current);
      liveOpportunitiesIntervalRef.current = null;
    }
    setLiveOpportunitiesFetching(false);
    console.log('⏹️ Stopped Live Opportunities price feed');
  };

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

  // Handle real-time opportunities from RealTimePriceFeed
  const handleRealTimeOpportunity = useCallback((opportunity) => {
    console.log('📈 New real-time opportunity received:', opportunity);
    setRealTimeOpportunities(prev => {
      const updated = [opportunity, ...prev];
      // Keep only last 10 real-time opportunities
      return updated.slice(0, 10);
    });
  }, []);

  // Handle price updates from RealTimePriceFeed
  const handlePriceUpdate = useCallback((priceData) => {
    console.log('📊 HANDLE PRICE UPDATE CALLED:');
    console.log('📊 Price update received:', priceData);
    console.log('📊 Data keys:', Object.keys(priceData || {}));
    console.log('📊 ALGO/USD data:', priceData?.['ALGO/USD']);
    
    setCurrentPrices(priceData);
    
    // Update AI Engine with new price data
    if (aiArbitrageEngine && Object.keys(priceData).length > 0) {
      console.log('🤖 Sending price data to AI Engine...');
      // This will trigger processOpportunitiesForActiveStrategies inside updatePriceData
      aiArbitrageEngine.updatePriceData(priceData);
      
      // Update AI opportunities from engine
      setRealTimeOpportunities(aiArbitrageEngine.getCurrentOpportunities());
      
      // Update AI strategies state with new P&L calculations
      const updatedStrategies = aiArbitrageEngine.getAllStrategies();
      setAiStrategies([...updatedStrategies]); // Force new array reference for re-render
      
      console.log('🤖 AI Engine processed opportunities, strategies updated:', 
        updatedStrategies.map(s => `${s.name}: ${s.currentValue.toFixed(2)} ALGO`));
    } else {
      console.log('❌ AI Engine not available or no price data');
    }
    
    // Store price history for trend detection
    setPriceHistory(prev => {
      const timestamp = new Date().toISOString();
      const newHistory = { ...prev };
      
      Object.entries(priceData).forEach(([pair, exchanges]) => {
        if (!newHistory[pair]) newHistory[pair] = {};
        Object.entries(exchanges).forEach(([exchange, data]) => {
          if (!newHistory[pair][exchange]) newHistory[pair][exchange] = [];
          newHistory[pair][exchange].push({
            price: data.price,
            timestamp,
            volume: data.volume_24h || 0
          });
          // Keep only last 10 price points per exchange
          if (newHistory[pair][exchange].length > 10) {
            newHistory[pair][exchange] = newHistory[pair][exchange].slice(-10);
          }
        });
      });
      
      return newHistory;
    });
    
    // Detect live opportunities from current prices
    detectLiveOpportunities(priceData);
    
    // Update strategy P&L based on current prices
    if (Object.keys(priceData).length > 0) {
      updateStrategiesWithCurrentPrices(priceData);
    }
  }, []);

  // Update strategy performance with current prices
  const updateStrategiesWithCurrentPrices = useCallback((priceData) => {
    setStrategies(prevStrategies => 
      prevStrategies.map(strategy => {
        if (!strategy.is_active) return strategy;
        
        // Simple P&L simulation based on current price movements
        const algoUsdPrice = priceData['ALGO/USD'];
        if (algoUsdPrice) {
          const avgPrice = Object.values(algoUsdPrice).reduce((sum, data) => sum + data.price, 0) / Object.keys(algoUsdPrice).length;
          const priceChange = Math.random() * 0.02 - 0.01; // ±1% random for simulation
          const newPnl = strategy.allocated_amount * priceChange;
          
          return {
            ...strategy,
            current_pnl: newPnl,
            performance_score: Math.max(0, Math.min(1, 0.7 + priceChange * 10))
          };
        }
        return strategy;
      })
    );
  }, []);

  // Detect live opportunities from current price data
  const detectLiveOpportunities = useCallback((priceData) => {
    const newOpportunities = [];
    const timestamp = new Date();
    
    Object.entries(priceData).forEach(([pair, exchanges]) => {
      const exchangeList = Object.entries(exchanges);
      
      // Compare all exchange pairs for arbitrage opportunities
      for (let i = 0; i < exchangeList.length; i++) {
        for (let j = i + 1; j < exchangeList.length; j++) {
          const [exchange1, data1] = exchangeList[i];
          const [exchange2, data2] = exchangeList[j];
          
          if (!data1.price || !data2.price) continue;
          
          const price1 = data1.price;
          const price2 = data2.price;
          
          // Calculate spread percentage
          const spreadPct = Math.abs((price2 - price1) / Math.min(price1, price2)) * 100;
          
          // Estimate fees (0.3% per exchange is typical)
          const totalFees = 0.6; // 0.3% x 2 exchanges
          const netProfitPct = spreadPct - totalFees;
          
          if (netProfitPct > 0.1) { // Minimum 0.1% profit after fees
            const buyExchange = price1 < price2 ? exchange1 : exchange2;
            const sellExchange = price1 < price2 ? exchange2 : exchange1;
            const buyPrice = Math.min(price1, price2);
            const sellPrice = Math.max(price1, price2);
            
            // Estimate trade amounts based on volume
            const minVolume = Math.min(data1.volume_24h || 50000, data2.volume_24h || 50000);
            const minTradeAmount = Math.max(100, minVolume * 0.001); // 0.1% of daily volume
            const maxTradeAmount = Math.min(5000, minVolume * 0.01); // 1% of daily volume
            
            newOpportunities.push({
              id: `live-${pair}-${buyExchange}-${sellExchange}-${timestamp.getTime()}`,
              asset_pair: pair,
              dex_1: buyExchange,
              dex_2: sellExchange,
              price_1: buyPrice,
              price_2: sellPrice,
              profit_percentage: netProfitPct,
              min_trade_amount: minTradeAmount,
              max_trade_amount: maxTradeAmount,
              is_active: true,
              expires_at: new Date(timestamp.getTime() + 15000).toISOString(), // 15 seconds
              created_at: timestamp.toISOString(),
              source: 'LIVE_DETECTION',
              confidence: spreadPct > 1.0 ? 'HIGH' : spreadPct > 0.5 ? 'MEDIUM' : 'LOW'
            });
          }
        }
      }
    });
    
    // Update live opportunities, removing expired ones
    setLiveDetectedOpportunities(prev => {
      const now = new Date();
      const validOpportunities = prev.filter(opp => new Date(opp.expires_at) > now);
      return [...validOpportunities, ...newOpportunities]
        .sort((a, b) => b.profit_percentage - a.profit_percentage) // Sort by profit desc
        .slice(0, 20); // Keep only top 20
    });
  }, []);

  useEffect(() => {
    loadStrategies();
    loadOpportunities();
    
    // Initialize AI Engine
    console.log('🤖 Initializing AI Arbitrage Engine...');
    try {
      aiArbitrageEngine.start();
      setAiEngineRunning(true);
      setAiStrategies(aiArbitrageEngine.getAllStrategies());
      console.log('✅ AI Engine started successfully');
    } catch (error) {
      console.error('❌ Failed to start AI Engine:', error);
      setAiEngineRunning(false);
    }
    
    // Set up auto-refresh for opportunities (every 45 seconds)
    const opportunitiesInterval = setInterval(() => {
      if (tabValue === 1) {
        loadOpportunities();
      }
      // Load AI selected opportunities when tab 2 is active or every 60 seconds
      if (tabValue === 2) {
        loadAiSelectedOpportunities();
      }
    }, 45000);

    // Set up AI opportunities refresh (every 30 seconds for faster updates)
    const aiOpportunitiesInterval = setInterval(() => {
      loadAiSelectedOpportunities();
    }, 30000);

    // Set up auto-refresh for strategy P&L (every 90 seconds)
    const strategiesInterval = setInterval(() => {
      if (tabValue === 0) {
        console.log('⏰ Auto-refreshing strategy P&L...');
        simulateActiveStrategiesPerformance();
        // Update AI strategies
        setAiStrategies(aiArbitrageEngine.getAllStrategies());
      }
    }, 90000);

    return () => {
      clearInterval(opportunitiesInterval);
      clearInterval(aiOpportunitiesInterval);
      clearInterval(strategiesInterval);
      // Stop AI Engine on unmount
      aiArbitrageEngine.stop();
    };
  }, [loadStrategies, loadOpportunities, simulateActiveStrategiesPerformance, tabValue]);

  // Separate useEffect for AI selected opportunities
  useEffect(() => {
    if (tabValue === 2) { // AI Seçtikleri tab
      console.log('🤖 AI Seçtikleri tab activated - loading AI opportunities');
      loadAiSelectedOpportunities();
      
      // Set up interval for AI opportunities
      const aiInterval = setInterval(() => {
        loadAiSelectedOpportunities();
      }, 60000); // Refresh AI selections every minute
      
      return () => clearInterval(aiInterval);
    }
  }, [tabValue]); // Only depend on tabValue

  // Start/Stop Live Opportunities price feed based on active tab OR active AI strategies
  useEffect(() => {
    const hasActiveAiStrategies = aiStrategies.some(s => s.status === 'active');
    
    if (tabValue === 1 || hasActiveAiStrategies) {
      if (tabValue === 1) {
        console.log('🎯 Live Opportunities tab activated - starting price feed');
      }
      if (hasActiveAiStrategies) {
        console.log('🤖 Active AI strategies detected - keeping price feed active');
      }
      startLiveOpportunitiesPriceFeed();
    } else {
      console.log('⏸️ No active monitoring needed - stopping price feed');
      stopLiveOpportunitiesPriceFeed();
    }

    return () => {
      if (tabValue !== 1 && !aiStrategies.some(s => s.status === 'active')) {
        stopLiveOpportunitiesPriceFeed();
      }
    };
  }, [tabValue, aiStrategies]);

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

  // AI Strategy Handlers
  const handleCreateAiStrategy = async () => {
    try {
      console.log('🤖 Creating new AI Arbitrage Strategy with 100 ALGO');
      
      const newAiStrategy = await aiArbitrageEngine.createStrategy({
        name: `AI Arbitrage ${new Date().toLocaleDateString()}`,
        initialAmount: 100,
        exchanges: ['coingecko', 'htx', 'tinyman'],
        minProfitThreshold: 0.2, // Lowered from 0.5% to 0.2% to match Live Opportunities
        maxTradeAmount: 20, // Max 20% of capital per trade
        riskLevel: 'moderate'
      });

      console.log('✅ AI Strategy created:', newAiStrategy);
      setAiStrategies(aiArbitrageEngine.getAllStrategies());
      
      // Show success notification
      alert(`🚀 AI Arbitrage Strategy created successfully!\nInitial Amount: 100 ALGO\nStrategy ID: ${newAiStrategy.id}`);
    } catch (error) {
      console.error('❌ Error creating AI strategy:', error);
      alert('Failed to create AI strategy: ' + error.message);
    }
  };

  const handleToggleAiStrategy = async (strategyId) => {
    try {
      const strategy = aiStrategies.find(s => s.id === strategyId);
      if (!strategy) return;

      if (strategy.status === 'active') {
        console.log('⏸️ Pausing AI strategy:', strategyId);
        aiArbitrageEngine.pauseStrategy(strategyId);
      } else {
        console.log('▶️ Activating AI strategy:', strategyId);
        aiArbitrageEngine.activateStrategy(strategyId);
      }

      setAiStrategies(aiArbitrageEngine.getAllStrategies());
    } catch (error) {
      console.error('❌ Error toggling AI strategy:', error);
      alert('Failed to toggle AI strategy: ' + error.message);
    }
  };

  const handleViewAiStrategy = (strategy) => {
    console.log('👁️ Viewing AI strategy details:', strategy);
    
    const details = `
🤖 AI Strategy Details:
• Name: ${strategy.name}
• Status: ${(strategy.status || 'unknown').toUpperCase()}
• Initial Amount: ${strategy.initialAmount} ALGO
• Current Value: ${strategy.currentValue.toFixed(2)} ALGO
• P&L: ${(strategy.currentValue - strategy.initialAmount).toFixed(2)} ALGO
• Total Trades: ${strategy.stats.totalTrades}
• Successful Trades: ${strategy.stats.successfulTrades}
• Win Rate: ${strategy.stats.totalTrades > 0 ? ((strategy.stats.successfulTrades / strategy.stats.totalTrades) * 100).toFixed(1) : 0}%
• Active Trades: ${strategy.activeTrades.length}
• Created: ${strategy.createdAt.toLocaleDateString()}

📊 Current Opportunities: ${realTimeOpportunities.length}
⚡ AI Engine Status: ${aiEngineRunning ? 'RUNNING' : 'STOPPED'}
    `;
    
    alert(details);
  };

  return (
    <>
      {/* Add CSS animations */}
      <style>
        {`
          @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
          }
        `}
      </style>
      
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
              <Badge badgeContent={opportunities.length + liveDetectedOpportunities.length + realTimeOpportunities.length} color="success">
                Live Opportunities
              </Badge>
            }
            icon={<Notifications />} 
            iconPosition="start"
            id="strategy-tab-1"
            aria-controls="strategy-tabpanel-1"
          />
          <Tab 
            label={
              <Badge badgeContent={aiSelectedOpportunities.length} color="secondary">
                AI Selected
              </Badge>
            }
            icon={<SmartToy />} 
            iconPosition="start"
            id="strategy-tab-2"
            aria-controls="strategy-tabpanel-2"
          />
          <Tab 
            label="Real-Time Feeds" 
            icon={<TrendingUp />} 
            iconPosition="start"
            id="strategy-tab-3"
            aria-controls="strategy-tabpanel-3"
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
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Typography variant="h6" fontWeight={600}>
                  Your Strategies ({strategies.length})
                </Typography>
                {Object.keys(currentPrices).length > 0 && (
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <Chip 
                      label="LIVE PRICES" 
                      size="small" 
                      color="success" 
                      variant="filled"
                      icon={<SignalCellularAlt />}
                    />
                    <Typography variant="caption" color="success.main">
                      ALGO: ${(Object.values(currentPrices['ALGO/USD'] || {}).reduce((sum, data) => sum + data.price, 0) / Math.max(1, Object.keys(currentPrices['ALGO/USD'] || {}).length)).toFixed(4)}
                    </Typography>
                  </Box>
                )}
              </Box>
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
                Live Arbitrage Opportunities ({opportunities.length + liveDetectedOpportunities.length + realTimeOpportunities.length})
              </Typography>
              <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
                <Chip 
                  label={`DB: ${opportunities.length}`} 
                  size="small" 
                  color="info" 
                  variant="outlined" 
                />
                <Chip 
                  label={`Live: ${liveDetectedOpportunities.length}`} 
                  size="small" 
                  color="success" 
                  variant="filled" 
                />
                <Chip 
                  label={`Feed: ${realTimeOpportunities.length}`} 
                  size="small" 
                  color="warning" 
                  variant="outlined" 
                />
              </Box>
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
            ) : opportunities.length === 0 && liveDetectedOpportunities.length === 0 && realTimeOpportunities.length === 0 ? (
              <Alert severity="info">
                Live Opportunities monitoring is active. System automatically detects arbitrage opportunities.
                <Typography variant="body2" sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
                  🔍 Price Feed: {liveOpportunitiesFetching ? '🔄 Fetching...' : (Object.keys(currentPrices).length > 0 ? '✅ Active' : '⏸️ Starting...')}
                  {Object.keys(currentPrices).length > 0 && (
                    <>
                      | 📊 Exchanges: {Object.keys(currentPrices['ALGO/USD'] || {}).join(', ')}
                      | ⚡ Last update: {new Date().toLocaleTimeString()}
                    </>
                  )}
                </Typography>
                <Typography variant="body2" sx={{ mt: 1, fontStyle: 'italic' }}>
                  💡 System fetches live prices from CoinGecko, HTX & Tinyman every 5 seconds to detect "Buy from X, Sell to Y" opportunities
                </Typography>
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
                      <TableCell>Recommendation</TableCell>
                      <TableCell align="right">Min Amount</TableCell>
                      <TableCell align="right">Max Amount</TableCell>
                      <TableCell>Expires In</TableCell>
                      <TableCell align="right">Action</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {/* Live detected opportunities (highest priority) */}
                    {liveDetectedOpportunities.map((opp) => {
                      const timeLeft = Math.max(0, (new Date(opp.expires_at) - new Date()) / 1000);
                      const isExpiring = timeLeft < 5;
                      
                      return (
                        <TableRow 
                          key={opp.id} 
                          sx={{ 
                            backgroundColor: isExpiring ? 'error.light' : 'success.light',
                            opacity: isExpiring ? 0.7 : 0.95,
                            animation: isExpiring ? 'pulse 1s infinite' : 'none'
                          }}
                        >
                          <TableCell>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                              <Typography variant="subtitle2" fontWeight={600}>
                                {opp.asset_pair}
                              </Typography>
                              <Chip 
                                label={`LIVE ${opp.confidence}`} 
                                size="small" 
                                color={opp.confidence === 'HIGH' ? 'error' : opp.confidence === 'MEDIUM' ? 'warning' : 'info'}
                                variant="filled"
                              />
                            </Box>
                          </TableCell>
                          <TableCell>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                              <Chip label={opp.dex_1} size="small" color="success" variant="outlined" />
                              <Typography variant="caption" color="success.main">BUY</Typography>
                            </Box>
                          </TableCell>
                          <TableCell>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                              <Chip label={opp.dex_2} size="small" color="error" variant="outlined" />
                              <Typography variant="caption" color="error.main">SELL</Typography>
                            </Box>
                          </TableCell>
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
                              color={opp.profit_percentage > 1 ? 'error' : opp.profit_percentage > 0.5 ? 'warning' : 'success'}
                              size="small"
                              variant="filled"
                            />
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2" sx={{ 
                              fontSize: '0.75rem', 
                              color: 'success.dark', 
                              fontWeight: 'bold',
                              backgroundColor: 'success.light',
                              padding: '4px 8px',
                              borderRadius: '4px',
                              display: 'inline-block'
                            }}>
                              {opp.recommendation || `📈 Buy ${(opp.dex_1 || 'Unknown').toUpperCase()} → Sell ${(opp.dex_2 || 'Unknown').toUpperCase()}`}
                            </Typography>
                          </TableCell>
                          <TableCell align="right">
                            <Typography variant="body2">{Math.round(opp.min_trade_amount)} ALGO</Typography>
                          </TableCell>
                          <TableCell align="right">
                            <Typography variant="body2">{Math.round(opp.max_trade_amount)} ALGO</Typography>
                          </TableCell>
                          <TableCell>
                            <Typography 
                              variant="body2" 
                              color={isExpiring ? 'error.main' : 'success.main'}
                              fontWeight={isExpiring ? 'bold' : 'normal'}
                            >
                              {Math.floor(timeLeft)}s
                            </Typography>
                          </TableCell>
                          <TableCell align="right">
                            <Button
                              variant="contained"
                              size="small"
                              color={isExpiring ? 'error' : 'success'}
                              disabled={timeLeft <= 0}
                              sx={{ 
                                minWidth: 80,
                                animation: opp.confidence === 'HIGH' && !isExpiring ? 'pulse 2s infinite' : 'none'
                              }}
                            >
                              {isExpiring ? 'EXPIRING' : 'EXECUTE'}
                            </Button>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                    {/* Real-time feed opportunities */}
                    {realTimeOpportunities.map((opp) => (
                      <TableRow key={`rt-${opp.id}`} sx={{ backgroundColor: 'success.light', opacity: 0.1 }}>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Typography variant="subtitle2" fontWeight={600}>
                              {opp.pair}
                            </Typography>
                            <Chip label="LIVE" size="small" color="success" />
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Chip label={opp.buyDex} size="small" color="success" variant="outlined" />
                        </TableCell>
                        <TableCell>
                          <Chip label={opp.sellDex} size="small" color="error" variant="outlined" />
                        </TableCell>
                        <TableCell align="right">
                          <Typography color="success.main" fontWeight={600}>
                            ${opp.buyPrice.toFixed(4)}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Typography color="error.main" fontWeight={600}>
                            ${opp.sellPrice.toFixed(4)}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Chip
                            label={`+${opp.netProfitPct.toFixed(2)}%`}
                            color="success"
                            size="small"
                            variant="filled"
                          />
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" sx={{ 
                            fontSize: '0.75rem', 
                            color: 'warning.dark', 
                            fontWeight: 'bold',
                            backgroundColor: 'warning.light',
                            padding: '4px 8px',
                            borderRadius: '4px',
                            display: 'inline-block'
                          }}>
                            📊 Buy {(opp.buyDex || 'Unknown').toUpperCase()} → Sell {(opp.sellDex || 'Unknown').toUpperCase()}
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Typography variant="body2">100-1000 ALGO</Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Typography variant="body2">5000 ALGO</Typography>
                        </TableCell>
                        <TableCell>
                          <Typography 
                            variant="body2" 
                            color={new Date(opp.expiresAt) - new Date() < 10000 ? 'error.main' : 'success.main'}
                          >
                            {Math.max(0, Math.floor((new Date(opp.expiresAt) - new Date()) / 1000))}s
                          </Typography>
                        </TableCell>
                        <TableCell align="right">
                          <Button
                            variant="contained"
                            size="small"
                            color="success"
                            disabled={new Date(opp.expiresAt) <= new Date()}
                          >
                            Execute
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                    {/* Database opportunities */}
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
                        <TableCell>
                          <Typography variant="body2" sx={{ 
                            fontSize: '0.75rem', 
                            color: 'info.dark', 
                            fontWeight: 'bold',
                            backgroundColor: 'info.light',
                            padding: '4px 8px',
                            borderRadius: '4px',
                            display: 'inline-block'
                          }}>
                            🏦 Buy {(opp.dex_1 || 'Unknown').toUpperCase()} → Sell {(opp.dex_2 || 'Unknown').toUpperCase()}
                          </Typography>
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
      <TabPanel value={tabValue} index={3}>
        <RealTimePriceFeed 
          onOpportunityFound={handleRealTimeOpportunity}
          onPriceUpdate={handlePriceUpdate}
        />
      </TabPanel>

      {/* AI Selected Opportunities Tab */}
      <TabPanel value={tabValue} index={2}>
        <Card>
          <CardContent>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <SmartToy color="secondary" />
                <Typography variant="h6" fontWeight={600}>
                  AI Selected ({aiSelectedOpportunities.length})
                </Typography>
              </Box>
              <Button
                variant="outlined"
                size="small"
                startIcon={<Refresh />}
                onClick={loadAiSelectedOpportunities}
                disabled={aiLoading}
              >
                {aiLoading ? 'AI Analyzing...' : 'Refresh AI Analysis'}
              </Button>
            </Box>

            {aiLoading ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                <CircularProgress />
              </Box>
            ) : aiSelectedOpportunities.length === 0 ? (
              <Box sx={{ textAlign: 'center', py: 6 }}>
                <SmartToy sx={{ fontSize: 64, color: 'text.disabled', mb: 2 }} />
                <Typography variant="h6" color="text.secondary" gutterBottom>
                  No AI selections yet
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  AI system is analyzing the best arbitrage opportunities...
                </Typography>
              </Box>
            ) : (
              <TableContainer>
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>AI Score & Asset</TableCell>
                      <TableCell>Buy Exchange</TableCell>
                      <TableCell>Sell Exchange</TableCell>
                      <TableCell align="right">Buy Price</TableCell>
                      <TableCell align="right">Sell Price</TableCell>
                      <TableCell align="right">Profit</TableCell>
                      <TableCell align="right">Risk Level</TableCell>
                      <TableCell align="right">Action</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {aiSelectedOpportunities.map((opp, index) => (
                      <TableRow 
                        key={`ai-${index}`}
                        sx={{ 
                          backgroundColor: 'secondary.light',
                          '&:hover': { backgroundColor: 'secondary.main', opacity: 0.8 }
                        }}
                      >
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Typography variant="subtitle2" fontWeight={600}>
                              {opp.asset_pair}
                            </Typography>
                            <Chip 
                              label={`AI: ${opp.ai_confidence || 'HIGH'}`} 
                              size="small" 
                              color="secondary"
                              variant="filled"
                            />
                            <Chip 
                              label={`Score: ${opp.ai_score || '9.5'}`} 
                              size="small" 
                              color="info"
                              variant="outlined"
                            />
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                            <Chip label={opp.dex_1} size="small" color="success" variant="outlined" />
                            <Typography variant="caption" color="success.main">BUY</Typography>
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                            <Chip label={opp.dex_2} size="small" color="error" variant="outlined" />
                            <Typography variant="caption" color="error.main">SELL</Typography>
                          </Box>
                        </TableCell>
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
                          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
                            <Typography color="success.main" fontWeight={600} variant="body2">
                              {opp.profit_percentage.toFixed(2)}%
                            </Typography>
                            <Typography color="success.main" variant="caption">
                              ${opp.estimated_profit?.toFixed(2) || '0.00'}
                            </Typography>
                          </Box>
                        </TableCell>
                        <TableCell align="right">
                          <Chip 
                            label={opp.risk_level || 'LOW'} 
                            size="small" 
                            color={opp.risk_level === 'HIGH' ? 'error' : opp.risk_level === 'MEDIUM' ? 'warning' : 'success'}
                            variant="outlined"
                          />
                        </TableCell>
                        <TableCell align="right">
                          <IconButton
                            size="small"
                            color="secondary"
                            onClick={() => console.log('Execute AI selected opportunity:', opp)}
                          >
                            <PlayArrow />
                          </IconButton>
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

      {/* Hidden RealTimePriceFeed for AI Engine - Always Running */}
      <Box sx={{ display: 'none' }}>
        <RealTimePriceFeed 
          onOpportunityFound={handleRealTimeOpportunity}
          onPriceUpdate={handlePriceUpdate}
        />
      </Box>

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
    </>
  );
}

export default Strategies;
