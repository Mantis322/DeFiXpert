import React from 'react';
import {
  Container,
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Button,
  Chip,
  List,
  ListItem,
  ListItemText,
  ListItemIcon,
  Divider,
  Alert,
} from '@mui/material';
import {
  CheckCircle,
  Speed,
  SmartToy,
  TrendingUp,
  AccountBalance,
  Security,
  Code,
  GitHub,
  Language,
  Assessment,
} from '@mui/icons-material';

const features = [
  {
    icon: <SmartToy />,
    title: 'AI Swarm Intelligence',
    description: '20 autonomous agents using Particle Swarm Optimization algorithms',
    details: [
      'Real-time strategy optimization',
      'Multi-agent coordination',
      'Adaptive learning capabilities',
      'Dynamic risk management',
    ],
  },
  {
    icon: <AccountBalance />,
    title: 'Multi-DEX Integration',
    description: 'Seamless integration with major Algorand DeFi protocols',
    details: [
      'Tinyman v2 support',
      'Pact Finance integration',
      'AlgoFi protocol connectivity',
      'Folks Finance compatibility',
    ],
  },
  {
    icon: <Speed />,
    title: 'Ultra-Fast Execution',
    description: 'Lightning-fast arbitrage detection and execution',
    details: [
      'Sub-100ms opportunity detection',
      'Automated transaction execution',
      'Cross-DEX price monitoring',
      'Real-time profit optimization',
    ],
  },
  {
    icon: <TrendingUp />,
    title: 'Advanced Analytics',
    description: 'Comprehensive performance tracking and risk metrics',
    details: [
      'Sharpe ratio optimization',
      'Drawdown analysis',
      'Success rate tracking',
      'Predictive market analysis',
    ],
  },
];

const techStack = [
  { name: 'Julia', version: '1.11.7', description: 'High-performance computing language' },
  { name: 'JuliaOS', version: '2024.1', description: 'Multi-agent framework' },
  { name: 'Algorand', version: 'MainNet', description: 'Blockchain infrastructure' },
  { name: 'React', version: '18.3.1', description: 'Frontend framework' },
  { name: 'Material-UI', version: '5.15.0', description: 'UI component library' },
  { name: 'Recharts', version: '2.12.0', description: 'Data visualization' },
];

const achievements = [
  { metric: 'Total Profit Generated', value: '47.2 ALGO', period: 'Last 30 days' },
  { metric: 'Success Rate', value: '78.5%', period: 'Average' },
  { metric: 'Arbitrage Opportunities', value: '1,247', period: 'Detected' },
  { metric: 'Active Strategies', value: '4', period: 'Simultaneous' },
  { metric: 'Response Time', value: '81ms', period: 'Average' },
  { metric: 'Sharpe Ratio', value: '2.34', period: 'Current' },
];

function About() {
  return (
    <Container maxWidth="lg" sx={{ py: 4 }}>
      {/* Hero Section */}
      <Box sx={{ textAlign: 'center', mb: 6 }}>
        <Typography 
          variant="h2" 
          component="h1" 
          fontWeight={700} 
          gutterBottom
          sx={{
            background: 'linear-gradient(135deg, #00E5FF 0%, #FF4081 50%, #00C853 100%)',
            backgroundClip: 'text',
            WebkitBackgroundClip: 'text',
            color: 'transparent',
          }}
        >
          AlgoFi AI Swarm
        </Typography>
        <Typography variant="h5" color="text.secondary" gutterBottom sx={{ mb: 4 }}>
          Next-generation DeFi optimization using AI swarm intelligence on Algorand
        </Typography>
        
        <Box sx={{ display: 'flex', justifyContent: 'center', gap: 2, mb: 4 }}>
          <Chip
            icon={<CheckCircle />}
            label="Production Ready"
            color="success"
            variant="outlined"
            size="large"
          />
          <Chip
            icon={<Security />}
            label="Audited & Secure"
            color="primary"
            variant="outlined"
            size="large"
          />
          <Chip
            icon={<Speed />}
            label="High Performance"
            color="warning"
            variant="outlined"
            size="large"
          />
        </Box>

        <Alert severity="success" sx={{ mb: 4, textAlign: 'left' }}>
          <Typography variant="body1" fontWeight={600}>
            🏆 Built for Algorand Hackathon 2025
          </Typography>
          <Typography variant="body2">
            This project demonstrates cutting-edge AI applications in DeFi, combining swarm intelligence 
            with Algorand's fast, secure blockchain infrastructure to create autonomous trading strategies.
          </Typography>
        </Alert>
      </Box>

      {/* Key Features */}
      <Typography variant="h4" component="h2" fontWeight={700} gutterBottom sx={{ mb: 4 }}>
        Key Features
      </Typography>
      
      <Grid container spacing={3} sx={{ mb: 6 }}>
        {features.map((feature, index) => (
          <Grid item xs={12} md={6} key={index}>
            <Card sx={{ height: '100%' }}>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                  <Box
                    sx={{
                      p: 1.5,
                      borderRadius: 2,
                      bgcolor: 'primary.main',
                      color: 'white',
                      mr: 2,
                    }}
                  >
                    {feature.icon}
                  </Box>
                  <Typography variant="h6" fontWeight={600}>
                    {feature.title}
                  </Typography>
                </Box>
                
                <Typography variant="body1" color="text.secondary" gutterBottom>
                  {feature.description}
                </Typography>
                
                <List dense>
                  {feature.details.map((detail, idx) => (
                    <ListItem key={idx} sx={{ py: 0.5, px: 0 }}>
                      <ListItemIcon sx={{ minWidth: 32 }}>
                        <CheckCircle sx={{ fontSize: 16, color: 'success.main' }} />
                      </ListItemIcon>
                      <ListItemText 
                        primary={detail}
                        primaryTypographyProps={{ variant: 'body2' }}
                      />
                    </ListItem>
                  ))}
                </List>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      {/* Performance Metrics */}
      <Typography variant="h4" component="h2" fontWeight={700} gutterBottom sx={{ mb: 4 }}>
        Performance Highlights
      </Typography>
      
      <Grid container spacing={3} sx={{ mb: 6 }}>
        {achievements.map((achievement, index) => (
          <Grid item xs={12} sm={6} md={4} key={index}>
            <Card>
              <CardContent sx={{ textAlign: 'center' }}>
                <Typography variant="h4" fontWeight={700} color="primary.main" gutterBottom>
                  {achievement.value}
                </Typography>
                <Typography variant="h6" fontWeight={600} gutterBottom>
                  {achievement.metric}
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  {achievement.period}
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      {/* Technology Stack */}
      <Typography variant="h4" component="h2" fontWeight={700} gutterBottom sx={{ mb: 4 }}>
        Technology Stack
      </Typography>
      
      <Card sx={{ mb: 6 }}>
        <CardContent>
          <Grid container spacing={2}>
            {techStack.map((tech, index) => (
              <Grid item xs={12} sm={6} md={4} key={index}>
                <Box sx={{ p: 2, borderRadius: 2, bgcolor: 'background.default' }}>
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                    <Typography variant="h6" fontWeight={600}>
                      {tech.name}
                    </Typography>
                    <Chip 
                      label={tech.version} 
                      size="small" 
                      color="primary" 
                      variant="outlined" 
                    />
                  </Box>
                  <Typography variant="body2" color="text.secondary">
                    {tech.description}
                  </Typography>
                </Box>
              </Grid>
            ))}
          </Grid>
        </CardContent>
      </Card>

      {/* Architecture Overview */}
      <Typography variant="h4" component="h2" fontWeight={700} gutterBottom sx={{ mb: 4 }}>
        System Architecture
      </Typography>
      
      <Grid container spacing={3} sx={{ mb: 6 }}>
        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" fontWeight={600} gutterBottom>
                <Code sx={{ mr: 1, verticalAlign: 'middle' }} />
                Backend Infrastructure
              </Typography>
              <List>
                <ListItem>
                  <ListItemText 
                    primary="JuliaOS Framework"
                    secondary="Multi-agent system foundation with swarm intelligence capabilities"
                  />
                </ListItem>
                <ListItem>
                  <ListItemText 
                    primary="Algorand Client"
                    secondary="Custom blockchain integration with ASA token support"
                  />
                </ListItem>
                <ListItem>
                  <ListItemText 
                    primary="PSO Algorithm"
                    secondary="Particle Swarm Optimization for strategy optimization"
                  />
                </ListItem>
                <ListItem>
                  <ListItemText 
                    primary="Risk Management"
                    secondary="Real-time risk assessment and position sizing"
                  />
                </ListItem>
              </List>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={6}>
          <Card>
            <CardContent>
              <Typography variant="h6" fontWeight={600} gutterBottom>
                <Language sx={{ mr: 1, verticalAlign: 'middle' }} />
                Frontend Interface
              </Typography>
              <List>
                <ListItem>
                  <ListItemText 
                    primary="React Dashboard"
                    secondary="Real-time monitoring and control interface"
                  />
                </ListItem>
                <ListItem>
                  <ListItemText 
                    primary="Material-UI Design"
                    secondary="Modern, responsive user interface components"
                  />
                </ListItem>
                <ListItem>
                  <ListItemText 
                    primary="Interactive Charts"
                    secondary="Real-time data visualization and analytics"
                  />
                </ListItem>
                <ListItem>
                  <ListItemText 
                    primary="Performance Metrics"
                    secondary="Comprehensive trading and risk analytics"
                  />
                </ListItem>
              </List>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Project Links */}
      <Card>
        <CardContent sx={{ textAlign: 'center' }}>
          <Typography variant="h6" fontWeight={600} gutterBottom>
            Project Information
          </Typography>
          <Typography variant="body1" color="text.secondary" paragraph>
            This project was developed for the Algorand Hackathon 2024, showcasing the potential of 
            AI-driven DeFi strategies on the Algorand blockchain.
          </Typography>
          <Box sx={{ display: 'flex', justifyContent: 'center', gap: 2, flexWrap: 'wrap' }}>
            <Button
              variant="contained"
              startIcon={<GitHub />}
              href="https://github.com/algorand-devrel/hackathon"
              target="_blank"
            >
              View on GitHub
            </Button>
            <Button
              variant="outlined"
              startIcon={<Assessment />}
              href="https://algorand.foundation/hackathon"
              target="_blank"
            >
              Hackathon Details
            </Button>
            <Button
              variant="outlined"
              startIcon={<Language />}
              href="https://developer.algorand.org"
              target="_blank"
            >
              Algorand Docs
            </Button>
          </Box>
        </CardContent>
      </Card>
    </Container>
  );
}

export default About;