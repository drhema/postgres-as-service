import express from 'express';
import * as dotenv from 'dotenv';
import routes from './routes';
import { authMiddleware, errorHandler } from './middleware';
import { controlPool, adminPool } from './db';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 2600;

// Middleware
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} ${req.method} ${req.path}`);
  next();
});

// Public routes
app.get('/health', routes);

// Protected routes (require API key)
app.use('/api', authMiddleware, routes);

// Error handler
app.use(errorHandler);

// Start server
async function startServer() {
  try {
    // Test database connections
    await controlPool.query('SELECT NOW()');
    console.log('✓ Control database connection successful');

    await adminPool.query('SELECT NOW()');
    console.log('✓ Admin database connection successful');

    app.listen(PORT, () => {
      console.log('');
      console.log('═══════════════════════════════════════════════════════');
      console.log('  PostgreSQL SaaS API Server');
      console.log('═══════════════════════════════════════════════════════');
      console.log(`  Server running on: http://localhost:${PORT}`);
      console.log(`  Environment: ${process.env.NODE_ENV || 'development'}`);
      console.log(`  Database: ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
      console.log('');
      console.log('  API Endpoints:');
      console.log(`    GET    /health                              - Health check`);
      console.log(`    POST   /api/databases                       - Create database`);
      console.log(`    GET    /api/databases                       - List databases`);
      console.log(`    GET    /api/databases/:id                   - Get database`);
      console.log(`    GET    /api/databases/:id/stats             - Get database stats`);
      console.log(`    DELETE /api/databases/:id                   - Delete database`);
      console.log(`    POST   /api/databases/:id/whitelist         - Add IP to whitelist`);
      console.log(`    GET    /api/databases/:id/whitelist         - List whitelisted IPs`);
      console.log(`    DELETE /api/databases/:id/whitelist/:wlId   - Remove IP from whitelist`);
      console.log('');
      console.log(`  API Key: ${process.env.API_KEY}`);
      console.log('═══════════════════════════════════════════════════════');
      console.log('');
    });

  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing server...');
  await controlPool.end();
  await adminPool.end();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('\nSIGINT received, closing server...');
  await controlPool.end();
  await adminPool.end();
  process.exit(0);
});

startServer();
