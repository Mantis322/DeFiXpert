// AI Arbitrage Engine - Clean Version
export class AIArbitrageEngine {
  constructor() {
    this.strategies = new Map();
    this.opportunities = [];
    this.priceData = {};
    this.isRunning = false;
    this.processedOpportunities = new Set(); // Track processed opportunities
    this.lastTradeTime = new Map(); // Track last trade time per strategy
    this.lastPriceFingerprint = null; // Track significant price changes
  }

  start() {
    this.isRunning = true;
    console.log('🤖 AI Arbitrage Engine started');
    
    // Start periodic opportunity detection and processing
    this.opportunityInterval = setInterval(() => {
      if (this.strategies.size > 0) {
        console.log('🔄 Periodic opportunity check...');
        this.processOpportunitiesForActiveStrategies();
      }
    }, 15000); // Every 15 seconds
  }

  stop() {
    this.isRunning = false;
    if (this.opportunityInterval) {
      clearInterval(this.opportunityInterval);
    }
    console.log('🛑 AI Arbitrage Engine stopped');
  }

  createStrategy(config) {
    const strategy = {
      id: Date.now().toString(),
      name: config.name || `AI Arbitrage ${Date.now()}`,
      initialAmount: config.initialAmount || 100,
      currentValue: config.initialAmount || 100,
      status: 'active',
      createdAt: new Date(),
      lastUpdateAt: new Date(),
      
      // P&L Tracking
      totalReturn: 0,
      totalReturnPct: 0,
      
      // Trading Statistics
      stats: {
        totalTrades: 0,
        successfulTrades: 0,
        failedTrades: 0
      },
      
      // Active and completed trades
      activeTrades: [],
      completedTrades: [],
      
      // Strategy Configuration
      settings: {
        exchanges: config.exchanges || ['coingecko', 'htx', 'tinyman'],
        minProfitThreshold: config.minProfitThreshold || 0.2, // Lowered from 0.5% to 0.2%
        maxTradeAmount: config.maxTradeAmount || 20,
        riskLevel: config.riskLevel || 'moderate'
      }
    };
    
    this.strategies.set(strategy.id, strategy);
    console.log(`✅ AI Strategy created: ${strategy.name} with ${strategy.initialAmount} ALGO`);
    return strategy;
  }

  updatePriceData(priceData) {
    // Create price fingerprint to detect significant changes
    const currentFingerprint = this.createPriceFingerprint(priceData);
    
    // Only process if price data has changed significantly
    if (this.lastPriceFingerprint && this.lastPriceFingerprint === currentFingerprint) {
      console.log('⏭️ Price data unchanged, skipping processing');
      return;
    }
    
    this.priceData = priceData;
    this.lastPriceFingerprint = currentFingerprint;
    console.log('📊 AI Engine price data updated:', Object.keys(priceData));
    
    // Clean up old processed opportunities (older than 60 seconds)
    this.cleanupOldOpportunities();
    
    // Process opportunities for all active strategies
    this.processOpportunitiesForActiveStrategies();
  }

  createPriceFingerprint(priceData) {
    // Create a simple fingerprint of current prices to detect changes
    if (!priceData || Object.keys(priceData).length === 0) return null;
    
    let fingerprint = '';
    Object.entries(priceData).forEach(([pair, exchanges]) => {
      Object.entries(exchanges).forEach(([exchange, data]) => {
        if (data && data.price) {
          // Round to 4 decimal places to avoid minor fluctuation triggers
          fingerprint += `${pair}-${exchange}:${data.price.toFixed(4)};`;
        }
      });
    });
    return fingerprint;
  }

  cleanupOldOpportunities() {
    const cutoffTime = Date.now() - 60000; // 60 seconds ago
    const oldCount = this.processedOpportunities.size;
    
    // Convert Set to Array, filter, then back to Set
    const recentOpportunities = Array.from(this.processedOpportunities)
      .filter(oppId => {
        const timestamp = parseInt(oppId.split('_')[1]);
        return timestamp > cutoffTime;
      });
    
    this.processedOpportunities = new Set(recentOpportunities);
    
    if (oldCount !== this.processedOpportunities.size) {
      console.log(`🧹 Cleaned up ${oldCount - this.processedOpportunities.size} old opportunity records`);
    }
  }

  processOpportunitiesForActiveStrategies() {
    const activeStrategies = Array.from(this.strategies.values()).filter(s => s.status === 'active');
    
    console.log(`🤖 AI ENGINE STATUS CHECK:
    • Total strategies: ${this.strategies.size}
    • Active strategies: ${activeStrategies.length}  
    • Price data available: ${this.priceData ? Object.keys(this.priceData).length : 0} pairs
    • Engine running: ${this.isRunning}`);
    
    if (activeStrategies.length === 0) {
      console.log('⏸️ No active AI strategies to process');
      return;
    }
    
    console.log(`🎯 Processing opportunities for ${activeStrategies.length} active strategies`);
    
    // Detect current opportunities
    const opportunities = this.detectOpportunities();
    console.log(`📈 Found ${opportunities.length} opportunities`);
    
    if (opportunities.length > 0) {
      console.log('📊 Sample opportunities:', opportunities.slice(0, 3).map(o => 
        `${o.pair}: ${o.netProfitPct?.toFixed(2)}% profit`));
    }
    
    // Process each active strategy
    activeStrategies.forEach(strategy => {
      this.processStrategyOpportunities(strategy, opportunities);
    });
  }

  processStrategyOpportunities(strategy, opportunities) {
    console.log(`🤖 Processing opportunities for strategy: ${strategy.name}`);
    
    // Check trade cooldown (minimum 10 seconds between trades)
    const lastTrade = this.lastTradeTime.get(strategy.id);
    const cooldownPeriod = 10000; // 10 seconds
    
    if (lastTrade && (Date.now() - lastTrade) < cooldownPeriod) {
      const remainingCooldown = Math.ceil((cooldownPeriod - (Date.now() - lastTrade)) / 1000);
      console.log(`⏳ Strategy ${strategy.name} in cooldown for ${remainingCooldown}s`);
      return;
    }
    
    // Filter opportunities that meet strategy criteria
    const profitableOpps = opportunities.filter(opp => {
      const profitPct = opp.netProfitPct || 0;
      return profitPct >= strategy.settings.minProfitThreshold;
    });
    
    if (profitableOpps.length === 0) {
      console.log(`❌ No profitable opportunities for ${strategy.name} (min: ${strategy.settings.minProfitThreshold}%)
      • Available opportunities: ${opportunities.length}
      • Sample rates: ${opportunities.slice(0, 3).map(o => `${o.netProfitPct?.toFixed(3)}%`).join(', ')}`);
      return;
    }
    
    console.log(`✅ Found ${profitableOpps.length} profitable opportunities for ${strategy.name}`);
    
    // Select best opportunity that hasn't been processed recently
    const bestOpp = profitableOpps
      .filter(opp => !this.processedOpportunities.has(opp.id))
      .sort((a, b) => (b.netProfitPct || 0) - (a.netProfitPct || 0))[0];
    
    if (!bestOpp) {
      console.log(`🔄 All profitable opportunities already processed for ${strategy.name}`);
      return;
    }
    
    console.log(`🎯 Best opportunity: ${bestOpp.pair} - ${bestOpp.netProfitPct?.toFixed(2)}% profit`);
    
    // Execute theoretical trade
    this.executeTheoreticalTrade(strategy, bestOpp);
  }

  executeTheoreticalTrade(strategy, opportunity) {
    const tradeAmount = Math.min(
      strategy.currentValue * (strategy.settings.maxTradeAmount / 100),
      strategy.currentValue * 0.2 // Max 20% per trade
    );
    
    if (tradeAmount < 1) {
      console.log(`❌ Trade amount too small: ${tradeAmount} ALGO`);
      return;
    }
    
    // Mark this opportunity as processed
    this.processedOpportunities.add(opportunity.id);
    
    // Update last trade time for this strategy
    this.lastTradeTime.set(strategy.id, Date.now());
    
    const profitAmount = tradeAmount * (opportunity.netProfitPct / 100);
    const newValue = strategy.currentValue + profitAmount;
    
    console.log(`� AI Trade: ${strategy.name} - ${tradeAmount.toFixed(2)} ALGO at ${opportunity.netProfitPct?.toFixed(2)}% profit`);
    
    // Update strategy IMMEDIATELY
    strategy.currentValue = newValue;
    strategy.stats.totalTrades += 1;
    if (profitAmount > 0) {
      strategy.stats.successfulTrades += 1;
    }
    
    // Add to completed trades
    strategy.completedTrades.push({
      id: Date.now(),
      timestamp: new Date(),
      pair: opportunity.pair,
      buyExchange: opportunity.buyExchange || opportunity.buyDex,
      sellExchange: opportunity.sellExchange || opportunity.sellDex,
      amount: tradeAmount,
      profit: profitAmount,
      profitPct: opportunity.netProfitPct,
      success: profitAmount > 0
    });
    
    // Emit delayed completion message to show progressive gains
    setTimeout(() => {
      console.log(`� Trade completed: ${strategy.name} +${profitAmount.toFixed(4)} ALGO`);
    }, 1000);
  }

  detectOpportunities() {
    if (!this.priceData || Object.keys(this.priceData).length === 0) {
      return [];
    }

    const opportunities = [];
    
    // Analyze each pair
    Object.entries(this.priceData).forEach(([pair, exchanges]) => {
      const exchangeNames = Object.keys(exchanges);
      
      // Compare all exchange pairs
      for (let i = 0; i < exchangeNames.length; i++) {
        for (let j = i + 1; j < exchangeNames.length; j++) {
          const exchange1 = exchangeNames[i];
          const exchange2 = exchangeNames[j];
          
          const price1 = exchanges[exchange1]?.price;
          const price2 = exchanges[exchange2]?.price;
          
          if (price1 && price2 && price1 > 0 && price2 > 0) {
            // Calculate arbitrage opportunity
            let buyExchange, sellExchange, buyPrice, sellPrice;
            
            if (price1 < price2) {
              buyExchange = exchange1;
              sellExchange = exchange2;
              buyPrice = price1;
              sellPrice = price2;
            } else {
              buyExchange = exchange2;
              sellExchange = exchange1;
              buyPrice = price2;
              sellPrice = price1;
            }
            
            const spread = ((sellPrice - buyPrice) / buyPrice) * 100;
            const netProfitPct = spread - 0.1; // Subtract 0.1% for fees
            
            if (netProfitPct > 0.1) { // Minimum 0.1% profit (much lower threshold)
              opportunities.push({
                id: `opp_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                pair,
                buyExchange,
                sellExchange,
                buyPrice,
                sellPrice,
                spread,
                netProfitPct,
                confidence: Math.min(95, 60 + spread * 10),
                timestamp: new Date(),
                expiresAt: new Date(Date.now() + 30000) // 30 second window
              });
            }
          }
        }
      }
    });

    this.opportunities = opportunities;
    return opportunities;
  }

  // Process opportunities and make automatic trade decisions
  processOpportunities() {
    if (!this.isRunning) return;
    
    // Get current opportunities
    this.detectOpportunities();
    
    console.log(`🤖 Processing ${this.opportunities.length} opportunities for ${this.strategies.size} strategies`);
    
    // Process each active strategy
    for (const [strategyId, strategy] of this.strategies.entries()) {
      if (strategy.status !== 'active') continue;
      
      // Find best opportunity for this strategy
      const bestOpportunity = this.findBestOpportunityForStrategy(strategy);
      
      if (bestOpportunity && this.shouldExecuteTrade(strategy, bestOpportunity)) {
        this.executeTheoreticalTrade(strategy, bestOpportunity);
      }
    }
  }

  findBestOpportunityForStrategy(strategy) {
    if (this.opportunities.length === 0) return null;
    
    // Filter opportunities based on strategy settings
    const validOpportunities = this.opportunities.filter(opp => 
      opp.netProfitPct >= strategy.settings.minProfitThreshold &&
      opp.confidence >= 60 &&
      opp.buyPrice && opp.sellPrice && opp.buyPrice > 0 && opp.sellPrice > 0
    );
    
    if (validOpportunities.length === 0) return null;
    
    // Return the most profitable one
    validOpportunities.sort((a, b) => b.netProfitPct - a.netProfitPct);
    return validOpportunities[0];
  }

  shouldExecuteTrade(strategy, opportunity) {
    // Check cooldown - max 1 trade per minute
    const lastTrade = strategy.activeTrades[strategy.activeTrades.length - 1];
    if (lastTrade && (new Date() - new Date(lastTrade.timestamp)) < 60000) {
      return false;
    }
    
    // Check if profit is worth it
    if (opportunity.netProfitPct < strategy.settings.minProfitThreshold) {
      return false;
    }
    
    // Check if we have enough capital for meaningful trade
    const maxTradeAmount = (strategy.settings.maxTradeAmount / 100) * strategy.currentValue;
    if (maxTradeAmount < 1) {
      return false;
    }
    
    return true;
  }

  executeTheoreticalTrade(strategy, opportunity) {
    const tradeAmount = Math.min(
      (strategy.settings.maxTradeAmount / 100) * strategy.currentValue,
      strategy.currentValue * 0.15 // Max 15% per trade
    );
    
    const trade = {
      id: `trade_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      strategyId: strategy.id,
      pair: opportunity.pair || 'ALGO/USD',
      buyExchange: opportunity.buyExchange,
      sellExchange: opportunity.sellExchange,
      buyPrice: opportunity.buyPrice,
      sellPrice: opportunity.sellPrice,
      amount: tradeAmount,
      expectedProfit: (opportunity.netProfitPct / 100) * tradeAmount,
      expectedProfitPct: opportunity.netProfitPct,
      timestamp: new Date(),
      status: 'active'
    };
    
    // Add to active trades
    strategy.activeTrades.push(trade);
    
    // Simulate trade completion with realistic results
    setTimeout(() => {
      this.completeTrade(strategy, trade);
    }, 3000 + Math.random() * 7000); // 3-10 seconds
    
    console.log(`🚀 AI Trade: ${strategy.name} - ${tradeAmount.toFixed(2)} ALGO at ${opportunity.netProfitPct.toFixed(2)}% profit`);
    
    return trade;
  }

  completeTrade(strategy, trade) {
    // Simulate realistic profit (85-95% of expected due to slippage)
    const successRate = 0.85 + Math.random() * 0.1;
    const actualProfit = trade.expectedProfit * successRate;
    
    // Update trade
    trade.status = 'completed';
    trade.actualProfit = actualProfit;
    trade.completedAt = new Date();
    
    // Update strategy
    strategy.currentValue += actualProfit;
    strategy.totalReturn += actualProfit;
    strategy.totalReturnPct = ((strategy.currentValue - strategy.initialAmount) / strategy.initialAmount) * 100;
    strategy.lastUpdateAt = new Date();
    
    // Update statistics
    strategy.stats.totalTrades++;
    if (actualProfit > 0) {
      strategy.stats.successfulTrades++;
    } else {
      strategy.stats.failedTrades++;
    }
    
    // Move from active to completed
    const index = strategy.activeTrades.findIndex(t => t.id === trade.id);
    if (index !== -1) {
      strategy.activeTrades.splice(index, 1);
      strategy.completedTrades.push(trade);
    }
    
    console.log(`💰 Trade completed: ${strategy.name} +${actualProfit.toFixed(4)} ALGO`);
  }

  // Management methods
  getAllStrategies() {
    return Array.from(this.strategies.values());
  }

  activateStrategy(id) {
    const strategy = this.strategies.get(id);
    if (strategy) {
      strategy.status = 'active';
      console.log(`▶️ Strategy ${strategy.name} activated`);
    }
  }

  pauseStrategy(id) {
    const strategy = this.strategies.get(id);
    if (strategy) {
      strategy.status = 'paused';
      console.log(`⏸️ Strategy ${strategy.name} paused`);
    }
  }

  getCurrentOpportunities() {
    // Filter out expired opportunities
    const now = new Date();
    this.opportunities = this.opportunities.filter(opp => opp.expiresAt > now);
    return this.opportunities;
  }
}

//export singleton instance  
export const aiArbitrageEngine = new AIArbitrageEngine();

// Debug helper - global access for testing
window.debugAI = {
  engine: aiArbitrageEngine,
  testTrade: (strategyId = null) => {
    const strategies = aiArbitrageEngine.getAllStrategies();
    const strategy = strategyId ? strategies.find(s => s.id === strategyId) : strategies[0];
    
    if (!strategy) {
      console.log('❌ No strategy found');
      return;
    }
    
    // Create a mock opportunity for testing
    const mockOpportunity = {
      pair: 'ALGO/USD',
      buyExchange: 'coingecko',
      sellExchange: 'htx', 
      buyPrice: 0.1500,
      sellPrice: 0.1520,
      netProfitPct: 1.2,
      timestamp: new Date()
    };
    
    console.log('🧪 Testing trade execution...');
    aiArbitrageEngine.executeTheoreticalTrade(strategy, mockOpportunity);
  },
  
  getStrategies: () => aiArbitrageEngine.getAllStrategies(),
  
  checkEngine: () => {
    console.log('🔍 AI Engine Status:', {
      isRunning: aiArbitrageEngine.isRunning,
      strategiesCount: aiArbitrageEngine.strategies.size,
      priceDataKeys: aiArbitrageEngine.priceData ? Object.keys(aiArbitrageEngine.priceData) : []
    });
  }
};