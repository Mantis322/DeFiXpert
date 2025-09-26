// API client for communicating with Julia backend (PostgreSQL-based)
const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8052';

class AlgoFiAPI {
  constructor() {
    this.baseURL = API_BASE_URL;
    this.walletAddress = null;
  }

  setWalletAddress(address) {
    this.walletAddress = address;
  }

  getAuthHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': this.walletAddress ? `Wallet ${this.walletAddress}` : '',
    };
  }

  async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;
    const config = {
      headers: this.getAuthHeaders(),
      timeout: 5000, // Reduce to 5 seconds for faster feedback
      signal: AbortSignal.timeout(5000), // Modern browsers abort after 5s
      ...options,
    };

    const maxRetries = 2;
    let lastError;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 15000); // 15 second timeout (increased from 5s)
        
        const response = await fetch(url, {
          ...config,
          signal: controller.signal
        });
        
        clearTimeout(timeoutId);
        
        if (!response.ok) {
          const errorData = await response.json().catch(() => ({}));
          throw new Error(errorData.error || `HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.json();
        return data;
      } catch (error) {
        lastError = error;
        console.warn(`API request attempt ${attempt}/${maxRetries} failed for ${endpoint}:`, error.message);
        
        // Don't retry on certain errors
        if (error.name === 'AbortError' || error.message.includes('401') || error.message.includes('403')) {
          break;
        }
        
        // Wait before retry (exponential backoff)
        if (attempt < maxRetries) {
          await new Promise(resolve => setTimeout(resolve, attempt * 1000));
        }
      }
    }
    
    console.error(`API request failed after ${maxRetries} attempts for ${endpoint}:`, lastError);
    throw lastError;
  }

  // Helper function to convert BigInt values to strings for JSON serialization
  serializeBigInt(obj) {
    return JSON.stringify(obj, (key, value) =>
      typeof value === 'bigint' ? value.toString() : value
    );
  }

  // Helper function to convert objects with BigInt values
  convertBigIntToString(obj) {
    if (obj === null || obj === undefined) {
      return obj;
    }
    
    if (typeof obj === 'bigint') {
      return obj.toString();
    }
    
    if (typeof obj !== 'object') {
      return obj;
    }
    
    if (Array.isArray(obj)) {
      return obj.map(item => this.convertBigIntToString(item));
    }
    
    const result = {};
    for (const key in obj) {
      if (obj.hasOwnProperty(key)) {
        const value = obj[key];
        if (typeof value === 'bigint') {
          result[key] = value.toString();
        } else if (typeof value === 'object' && value !== null) {
          result[key] = this.convertBigIntToString(value);
        } else {
          result[key] = value;
        }
      }
    }
    return result;
  }

  // Authentication
  async authenticateWallet(walletAddress, accountInfo, firebaseUid = null) {
    console.log('Original accountInfo:', accountInfo);
    
    // Convert BigInt values to strings to avoid JSON serialization issues
    const serializedAccountInfo = this.convertBigIntToString(accountInfo);
    console.log('Serialized accountInfo:', serializedAccountInfo);
    
    const requestBody = {
      wallet_address: walletAddress,
      account_info: serializedAccountInfo,
      firebase_uid: firebaseUid,
    };

    // Double check for any remaining BigInt values
    console.log('Request body before serialization:', requestBody);
    
    // Test JSON serialization separately
    try {
      const testSerialization = JSON.stringify(requestBody);
      console.log('JSON serialization test successful');
    } catch (err) {
      console.error('JSON serialization test failed:', err);
      console.error('Failed on object:', requestBody);
    }
    
    const response = await this.request('/api/v1/auth/wallet', {
      method: 'POST',
      body: this.serializeBigInt(requestBody),
    });
    
    this.setWalletAddress(walletAddress);
    return response;
  }

  // User Profile
  async getUserProfile() {
    return this.request('/api/v1/user/profile');
  }

  async updateUserProfile(profileData) {
    return this.request('/api/v1/user/profile', {
      method: 'PUT',
      body: JSON.stringify(profileData),
    });
  }

  // Performance Data
  async getUserPerformance(days = 30) {
    const resp = await this.request(`/api/v1/user/performance?days=${days}`);
    const arr = Array.isArray(resp?.performance) ? resp.performance : Array.isArray(resp) ? resp : [];
    if (arr.length === 0) {
      return {
        total_invested_algo: 0,
        current_value_algo: 0,
        total_pnl_algo: 0,
        win_rate: 0,
        total_trades: 0,
        historical_data: [],
      };
    }
    const first = arr[0] || {};
    const last = arr[arr.length - 1] || {};
    return {
      total_invested_algo: Number(first.total_invested_algo ?? 0),
      current_value_algo: Number(last.current_value_algo ?? 0),
      total_pnl_algo: Number(last.total_pnl_algo ?? ((last.current_value_algo ?? 0) - (last.total_invested_algo ?? 0))),
      win_rate: Number(last.win_rate ?? 0),
      total_trades: Number(last.total_trades ?? 0),
      historical_data: arr.map(d => ({
        date: d.date,
        total_value_algo: Number(d.current_value_algo ?? 0),
      })),
    };
  }

  async getUserPortfolio() {
    return this.request('/api/v1/user/portfolio');
  }

  async getUserTransactions(limit = 100) {
    const resp = await this.request(`/api/v1/user/transactions?limit=${limit}`);
    return Array.isArray(resp?.transactions) ? resp.transactions : (Array.isArray(resp) ? resp : []);
  }

  // Strategy Management
  async getUserStrategies() {
    const resp = await this.request('/api/v1/user/strategies');
    return Array.isArray(resp?.strategies) ? resp.strategies : (Array.isArray(resp) ? resp : []);
  }

  async createUserStrategy(strategyData) {
    return this.request('/api/v1/user/strategies', {
      method: 'POST',
      body: JSON.stringify(strategyData),
    });
  }

  async updateUserStrategy(strategyId, strategyData) {
    return this.request(`/api/v1/user/strategies/${strategyId}`, {
      method: 'PUT',
      body: JSON.stringify(strategyData),
    });
  }

  async deleteUserStrategy(strategyId) {
    return this.request(`/api/v1/user/strategies/${strategyId}`, {
      method: 'DELETE',
    });
  }

  // Trading and Opportunities
  async getArbitrageOpportunities() {
    const resp = await this.request('/api/v1/trading/opportunities');
    return Array.isArray(resp?.opportunities) ? resp.opportunities : (Array.isArray(resp) ? resp : []);
  }

  async logTransaction(transactionData) {
    return this.request('/api/v1/trading/transaction', {
      method: 'POST',
      body: JSON.stringify(transactionData),
    });
  }

  async simulateStrategyPerformance(strategyId) {
    return this.request(`/api/v1/strategies/${strategyId}/simulate`);
  }

  async getStrategyTracking(strategyId) {
    return this.request(`/api/v1/strategies/${strategyId}/tracking`);
  }

  // Market Data
  async getMarketData() {
    return this.request('/api/v1/market/data');
  }

  async getCurrentPrices() {
    return this.request('/api/v1/market/prices');
  }

  // Real data methods replacing mock implementations
  async getDashboardData() {
    try {
      const [stats, performance, strategies, protocols] = await Promise.all([
        this.request('/api/v1/dashboard/stats'),
        this.request('/api/v1/dashboard/performance'),
        this.request('/api/v1/dashboard/strategies'),
        this.request('/api/v1/dashboard/protocols')
      ]);
      
      return {
        stats,
        performance,
        strategies,
        protocols
      };
    } catch (error) {
      console.error('Error fetching dashboard data:', error);
      throw new Error('Failed to fetch dashboard data');
    }
  }

  async getSwarmData() {
    try {
      const [agents, parameters, performance] = await Promise.all([
        this.request('/api/v1/swarm/agents'),
        this.request('/api/v1/swarm/parameters'), 
        this.request('/api/v1/swarm/performance')
      ]);
      
      return {
        agents,
        parameters,
        performance
      };
    } catch (error) {
      console.error('Error fetching swarm data:', error);
      throw new Error('Failed to fetch swarm data');
    }
  }

  async getMarketData() {
    try {
      const [priceData, arbitrageOpportunities, predictions] = await Promise.all([
        this.request('/api/v1/market/price-history'),
        this.getArbitrageOpportunities(),
        this.request('/api/v1/market/predictions')
      ]);
      
      return {
        priceData,
        arbitrageOpportunities,
        predictions
      };
    } catch (error) {
      console.error('Error fetching market data:', error);
      throw new Error('Failed to fetch market data');
    }
  }

  async getRealTimePrices() {
    try {
      const response = await this.request('/api/v1/market/prices');
      return response;
    } catch (error) {
      console.error('Error fetching real-time prices:', error);
      throw new Error('Failed to fetch real-time prices');
    }
  }

  async getPerformanceData() {
    try {
      const [overview, historicalData, riskMetrics, strategyBreakdown] = await Promise.all([
        this.request('/api/v1/performance/overview'),
        this.request('/api/v1/performance/historical'),
        this.request('/api/v1/performance/risk'),
        this.request('/api/v1/performance/strategies')
      ]);
      
      return {
        overview,
        historicalData,
        riskMetrics,
        strategyBreakdown
      };
    } catch (error) {
      console.error('Error fetching performance data:', error);
      throw new Error('Failed to fetch performance data');
    }
  }
}

// Create singleton instance
const algofiAPI = new AlgoFiAPI();

export default algofiAPI;