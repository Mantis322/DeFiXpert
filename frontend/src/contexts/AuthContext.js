import React, { createContext, useContext, useState, useEffect } from 'react';
import { 
  connectWallet, 
  disconnectWallet, 
  getAccountInfo,
  isWalletConnected,
  getConnectedAccounts,
  clearWalletSession,
  peraWallet
} from '../utils/algorand';
import algofiAPI from '../services/algofiAPI';

const AuthContext = createContext();

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [walletAddress, setWalletAddress] = useState(null);
  const [accountInfo, setAccountInfo] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Check for existing wallet connection on load
  useEffect(() => {
    const initializeWallet = async () => {
      await checkWalletConnection();
      
      // Listen for disconnect events
      peraWallet.connector?.on('disconnect', handleWalletDisconnect);
    };
    
    initializeWallet();
    
    return () => {
      peraWallet.connector?.off('disconnect', handleWalletDisconnect);
    };
  }, []); // Empty dependency array - only run once on mount

  const checkWalletConnection = async () => {
    try {
      setLoading(true);
      console.log('🔍 Checking existing wallet connection...');
      
      // First try to reconnect Pera Wallet session
      try {
        await peraWallet.reconnectSession();
        console.log('✅ Pera Wallet session reconnected');
      } catch (e) {
        console.log('ℹ️ No existing Pera Wallet session to restore');
      }
      
      if (isWalletConnected()) {
        const accounts = getConnectedAccounts();
        console.log('🔗 Found existing wallet connection:', accounts);
        if (accounts.length > 0) {
          const address = accounts[0];
          console.log('🚀 Restoring wallet connection for:', address);
          await handleWalletConnect(address);
        }
      } else {
        console.log('❌ No existing wallet connection found');
      }
    } catch (error) {
      console.error('Wallet connection check error:', error);
      setError(error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleWalletConnect = async (address) => {
    try {
      setLoading(true);
      setError(null);

      // Get account info from Algorand
      const info = await getAccountInfo(address);
      setAccountInfo(info);
      setWalletAddress(address);

      // Set wallet address in API client
      algofiAPI.setWalletAddress(address);

      // Authenticate with backend (PostgreSQL)
      const authResponse = await algofiAPI.authenticateWallet(address, info);
      
      setUser({
        wallet_address: address,
        created_at: authResponse.user.created_at,
        last_login: authResponse.user.last_login,
        settings: authResponse.user.settings,
        account_info: info,
      });

    } catch (error) {
      console.error('Wallet connect error:', error);
      setError(error.message);
      throw error;
    } finally {
      setLoading(false);
    }
  };

  const handleWalletDisconnect = async () => {
    try {
      setUser(null);
      setWalletAddress(null);
      setAccountInfo(null);
      setError(null);
      algofiAPI.setWalletAddress(null);
    } catch (error) {
      console.error('Wallet disconnect error:', error);
      setError(error.message);
    }
  };

  const connectUserWallet = async () => {
    try {
      setError(null);
      
      // Check if already connected but showing error
      if (isWalletConnected()) {
        const accounts = getConnectedAccounts();
        if (accounts.length > 0) {
          console.log('Using existing wallet connection:', accounts[0]);
          await handleWalletConnect(accounts[0]);
          return accounts[0];
        }
      }
      
      // Clear any stale sessions before connecting
      console.log('Clearing stale sessions...');
      await clearWalletSession();
      
      // Fresh connection
      const accounts = await connectWallet();
      if (accounts.length > 0) {
        await handleWalletConnect(accounts[0]);
        return accounts[0];
      } else {
        throw new Error('No accounts returned from wallet');
      }
    } catch (error) {
      console.error('Connect wallet error:', error);
      
      // If connection failed, try clearing session and retry once
      if (error.message.includes('Session currently connected')) {
        console.log('Session conflict detected, clearing and retrying...');
        await clearWalletSession();
        
        try {
          const accounts = await connectWallet();
          if (accounts.length > 0) {
            await handleWalletConnect(accounts[0]);
            return accounts[0];
          }
        } catch (retryError) {
          console.error('Retry failed:', retryError);
          setError(retryError.message);
          throw retryError;
        }
      }
      
      setError(error.message);
      throw error;
    }
  };

  const disconnectUserWallet = async () => {
    disconnectWallet();
    await handleWalletDisconnect();
  };

  const refreshAccountInfo = async () => {
    if (walletAddress) {
      try {
        const info = await getAccountInfo(walletAddress);
        setAccountInfo(info);
        
        // Update in backend
        await algofiAPI.updateUserProfile({ account_info: info });
      } catch (error) {
        console.error('Account refresh error:', error);
        setError(error.message);
      }
    }
  };

  const value = {
    user,
    walletAddress,
    accountInfo,
    loading,
    error,
    connectWallet: connectUserWallet,
    disconnectWallet: disconnectUserWallet,
    refreshAccountInfo,
    isConnected: !!walletAddress,
    api: algofiAPI, // Expose API client
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};