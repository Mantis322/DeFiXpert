import React from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Button
} from '@mui/material';
import { Assessment } from '@mui/icons-material';

const PerformanceAnalytics = () => {
  return (
    <Box sx={{ maxWidth: 1200, mx: 'auto', p: 3 }}>
      <Typography variant="h4" component="h1" gutterBottom fontWeight={700}>
        Performance Analytics
      </Typography>
      
      <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '60vh' }}>
        <Card sx={{ maxWidth: 500, textAlign: 'center', p: 3 }}>
          <CardContent>
            <Assessment sx={{ fontSize: 80, color: 'primary.main', mb: 2 }} />
            <Typography variant="h5" component="h2" gutterBottom fontWeight={600}>
              Premium Access Required
            </Typography>
            <Typography variant="body1" color="text.secondary" sx={{ mb: 3 }}>
              This content is only available to Premium members. Please contact the site administrator for Premium membership access.
            </Typography>
            <Button 
              variant="contained" 
              color="primary" 
              size="large"
              sx={{ mt: 2 }}
            >
              Contact Administrator
            </Button>
          </CardContent>
        </Card>
      </Box>
    </Box>
  );
};

export default PerformanceAnalytics;
