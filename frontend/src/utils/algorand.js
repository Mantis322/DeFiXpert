// Algorand wallet integration using Pera Wallet
import { PeraWalletConnect } from '@perawallet/connect';
import algosdk from 'algosdk';

// Initialize Pera Wallet
export const peraWallet = new PeraWalletConnect({
  deep_link: {
    name: 'AlgoFi',
    url: 'https://algofi.ai'
  }
});

// Algorand client configuration for TestNet
export const algodClient = new algosdk.Algodv2(
  '',
  'https://testnet-api.algonode.cloud',
  ''
);

// Indexer client for TestNet
export const indexerClient = new algosdk.Indexer(
  '',
  'https://testnet-idx.algonode.cloud',
  ''
);

// Wallet connection utilities
export const connectWallet = async () => {
  try {
    const newAccounts = await peraWallet.connect();
    return newAccounts;
  } catch (error) {
    console.error('Wallet connection error:', error);
    throw error;
  }
};

export const disconnectWallet = async () => {
  try {
    console.log('Disconnecting wallet...');
    
    // First clear the session completely
    await clearWalletSession();
    
    // Then disconnect from Pera Wallet (if still connected)
    if (peraWallet.isConnected) {
      await peraWallet.disconnect();
    }
    
    console.log('Wallet disconnected successfully');
  } catch (error) {
    console.error('Wallet disconnect error:', error);
    // Force clear anyway
    await clearWalletSession();
    throw error;
  }
};

export const getAccountInfo = async (address) => {
  try {
    const accountInfo = await algodClient.accountInformation(address).do();
    return accountInfo;
  } catch (error) {
    console.error('Account info error:', error);
    throw error;
  }
};

// Check if wallet is connected with session validation
export const isWalletConnected = () => {
  try {
    // First try to reconnect existing session
    peraWallet.reconnectSession().catch(() => {
      // Silent fail - no existing session
    });
    
    // Check both Pera Wallet state and local storage
    const peraConnected = peraWallet.isConnected;
    const hasAccounts = peraWallet.connector?.accounts?.length > 0;
    
    // Also check localStorage for backup
    const storedAccounts = localStorage.getItem('PeraWallet.Wallet');
    const hasStoredSession = storedAccounts && storedAccounts !== 'null';
    
    return (peraConnected && hasAccounts) || hasStoredSession;
  } catch (error) {
    console.error('Wallet connection check error:', error);
    return false;
  }
};

// Get connected accounts with validation
export const getConnectedAccounts = () => {
  try {
    // First try to reconnect existing session
    peraWallet.reconnectSession().catch(() => {
      // Silent fail - no existing session
    });
    
    if (!peraWallet.isConnected) {
      // Try to get from localStorage as backup
      const storedAccounts = localStorage.getItem('PeraWallet.Wallet');
      if (storedAccounts && storedAccounts !== 'null') {
        try {
          const parsed = JSON.parse(storedAccounts);
          return Array.isArray(parsed) ? parsed : [parsed];
        } catch (e) {
          console.warn('Failed to parse stored accounts:', e);
        }
      }
      return [];
    }
    return peraWallet.connector?.accounts || [];
  } catch (error) {
    console.error('Get accounts error:', error);
    return [];
  }
};

// Force clear wallet session (for troubleshooting)
export const clearWalletSession = async () => {
  try {
    console.log('Clearing wallet session...');
    
    // Disconnect from Pera Wallet
    if (peraWallet.isConnected) {
      await peraWallet.disconnect();
    }
    
    // Clear local storage data
    const keysToRemove = [
      'walletconnect',
      'pera-wallet',
      'wc@2:client:0.3//session',
      'wc@2:core:0.3//keychain',
      'wc@2:core:0.3//messages'
    ];
    
    keysToRemove.forEach(key => {
      localStorage.removeItem(key);
    });
    
    // Clear session storage
    sessionStorage.clear();
    
    console.log('Wallet session cleared successfully');
    return true;
  } catch (error) {
    console.error('Session clear error:', error);
    return false;
  }
};

// Sign transaction with wallet
export const signTransaction = async (txn) => {
  try {
    const signedTxn = await peraWallet.signTransaction([txn]);
    return signedTxn;
  } catch (error) {
    console.error('Transaction signing error:', error);
    throw error;
  }
};

// Send transaction
export const sendTransaction = async (signedTxn) => {
  try {
    const txId = await algodClient.sendRawTransaction(signedTxn).do();
    return txId;
  } catch (error) {
    console.error('Transaction send error:', error);
    throw error;
  }
};

// Wait for transaction confirmation
export const waitForConfirmation = async (txId) => {
  try {
    const confirmedTxn = await algosdk.waitForConfirmation(algodClient, txId, 4);
    return confirmedTxn;
  } catch (error) {
    console.error('Transaction confirmation error:', error);
    throw error;
  }
};