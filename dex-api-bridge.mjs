// Algorand DEX API Bridge (Simplified Version)
// This bridge makes direct API calls and exposes HTTP endpoints for Julia backend

import http from 'http';
import url from 'url';
import https from 'https';

// API request helper
function makeHttpsRequest(url, options = {}) {
    return new Promise((resolve, reject) => {
        const req = https.get(url, options, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (error) {
                    resolve({ error: 'Invalid JSON response', rawData: data });
                }
            });
        });
        
        req.on('error', (error) => reject(error));
        req.setTimeout(10000, () => {
            req.abort();
            reject(new Error('Request timeout'));
        });
    });
}

// Mock data fallback functions
function getMockTinymanData() {
    return {
        price: 0.20 + (Math.random() - 0.5) * 0.02, // ±1% variation
        volume_24h: 850000 + Math.random() * 200000,
        change_24h: (Math.random() - 0.5) * 5,
        last_updated: new Date().toISOString()
    };
}

function getMockVestigeData() {
    return {
        price: 0.21 + (Math.random() - 0.5) * 0.02, // ±1% variation
        volume_24h: 650000 + Math.random() * 150000,
        change_24h: (Math.random() - 0.5) * 4,
        last_updated: new Date().toISOString()
    };
}

function getMockUltradeData() {
    return {
        price: 0.205 + (Math.random() - 0.5) * 0.02, // ±1% variation
        volume_24h: 450000 + Math.random() * 100000,
        change_24h: (Math.random() - 0.5) * 3,
        last_updated: new Date().toISOString()
    };
}

// API handlers using real endpoints
async function handleTinymanPrice(req, res) {
    console.log('Handling Tinyman price request...');
    
    try {
        // Use Tinyman Analytics API
        const apiUrl = 'https://mainnet.analytics.tinyman.org/api/v1/pools/?asset_1=0&asset_2=31566704&limit=1';
        console.log(`Fetching from: ${apiUrl}`);
        
        const result = await makeHttpsRequest(apiUrl);
        
        if (result && result.results && result.results.length > 0) {
            const pool = result.results[0];
            const data = {
                price: parseFloat(pool.current_price || pool.price || 0.20),
                volume_24h: parseFloat(pool.volume_24h || 850000),
                change_24h: parseFloat(pool.change_24h || 0),
                last_updated: new Date().toISOString(),
                source: 'tinyman_api'
            };
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true, data }));
            return;
        }
        
        throw new Error('No pool data found');
        
    } catch (error) {
        console.error('Tinyman API error:', error);
        const data = getMockTinymanData();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, data, source: 'mock_fallback' }));
    }
}

async function handleVestigePrice(req, res) {
    console.log('Handling Vestige price request...');
    
    try {
        // Use Vestige API with proper parameters
        const apiUrl = 'https://api.vestigelabs.org/pools?network_id=1&limit=10';
        console.log(`Fetching from: ${apiUrl}`);
        
        const result = await makeHttpsRequest(apiUrl);
        
        if (result && result.results) {
            // Find ALGO/USDC pool
            const algoUsdcPool = result.results.find(pool => {
                const asset1 = pool.asset_1;
                const asset2 = pool.asset_2;
                return (asset1?.id === 0 || asset1?.id === "0") &&
                       (asset2?.id === 31566704 || asset2?.id === "31566704");
            });
            
            if (algoUsdcPool && algoUsdcPool.price) {
                const data = {
                    price: parseFloat(algoUsdcPool.price),
                    volume_24h: parseFloat(algoUsdcPool.volume_24h || 650000),
                    change_24h: parseFloat(algoUsdcPool.change_24h || 0),
                    last_updated: new Date().toISOString(),
                    source: 'vestige_api'
                };
                
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: true, data }));
                return;
            }
        }
        
        throw new Error('ALGO/USDC pool not found in Vestige data');
        
    } catch (error) {
        console.error('Vestige API error:', error);
        const data = getMockVestigeData();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, data, source: 'mock_fallback' }));
    }
}

async function handleUltradePrice(req, res) {
    console.log('Handling Ultrade price request...');
    
    try {
        // Use Ultrade market price API
        const apiUrl = 'https://api.testnet.ultrade.org/market/price?symbol=algo_usdc';
        console.log(`Fetching from: ${apiUrl}`);
        
        const result = await makeHttpsRequest(apiUrl);
        
        if (result && result.lastPrice) {
            // Convert from atomic units if needed
            let price = parseFloat(result.lastPrice);
            if (price > 1000) {
                // Likely in atomic units, convert to USD
                price = price / Math.pow(10, 18);
            }
            
            const data = {
                price: price,
                volume_24h: parseFloat(result.volume_24h || 450000),
                change_24h: parseFloat(result.change_24h || 0),
                last_updated: new Date().toISOString(),
                source: 'ultrade_api'
            };
            
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: true, data }));
            return;
        }
        
        throw new Error('Invalid Ultrade response');
        
    } catch (error) {
        console.error('Ultrade API error:', error);
        const data = getMockUltradeData();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ success: true, data, source: 'mock_fallback' }));
    }
}

// Health check endpoint
function handleHealth(req, res) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
        status: 'ok', 
        timestamp: new Date().toISOString(),
        services: ['tinyman', 'vestige', 'ultrade'],
        endpoints: ['/tinyman/price', '/vestige/price', '/ultrade/price']
    }));
}

// Create HTTP server
const server = http.createServer(async (req, res) => {
    // Enable CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }
    
    const parsedUrl = url.parse(req.url, true);
    const path = parsedUrl.pathname;
    
    console.log(`${req.method} ${path}`);
    
    try {
        switch (path) {
            case '/health':
                handleHealth(req, res);
                break;
            case '/tinyman/price':
                await handleTinymanPrice(req, res);
                break;
            case '/vestige/price':
                await handleVestigePrice(req, res);
                break;
            case '/ultrade/price':
                await handleUltradePrice(req, res);
                break;
            default:
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Not Found' }));
        }
    } catch (error) {
        console.error('Server error:', error);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Internal Server Error' }));
    }
});

const PORT = 3001;
server.listen(PORT, () => {
    console.log(`Algorand DEX API Bridge running on http://localhost:${PORT}`);
    console.log('Available endpoints:');
    console.log('  GET /health - Health check');
    console.log('  GET /tinyman/price - Tinyman ALGO/USDC price');
    console.log('  GET /vestige/price - Vestige ALGO/USDC price');
    console.log('  GET /ultrade/price - Ultrade ALGO/USDC price');
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down server...');
    server.close(() => {
        console.log('Server shutdown complete');
        process.exit(0);
    });
});

export default server;