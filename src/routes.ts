import { Router, Request, Response } from 'express';
import { DatabaseService } from './database.service';
import { WhitelistService } from './whitelist.service';

const router = Router();
const dbService = new DatabaseService();
const whitelistService = new WhitelistService();

// Health check
router.get('/health', async (req: Request, res: Response) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Create database
router.post('/databases', async (req: Request, res: Response) => {
  try {
    const { friendlyName, ownerEmail, maxConnections } = req.body;

    if (!friendlyName || !ownerEmail) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'friendlyName and ownerEmail are required'
      });
    }

    const database = await dbService.createDatabase({
      friendlyName,
      ownerEmail,
      maxConnections: maxConnections || 20
    });

    res.status(201).json({
      success: true,
      message: 'Database created successfully',
      data: database
    });
  } catch (error: any) {
    console.error('Error creating database:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// List databases
router.get('/databases', async (req: Request, res: Response) => {
  try {
    const databases = await dbService.listDatabases();

    res.json({
      success: true,
      count: databases.length,
      data: databases
    });
  } catch (error: any) {
    console.error('Error listing databases:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// Get database by ID
router.get('/databases/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const database = await dbService.getDatabase(id);

    if (!database) {
      return res.status(404).json({
        error: 'Not Found',
        message: 'Database not found'
      });
    }

    res.json({
      success: true,
      data: database
    });
  } catch (error: any) {
    console.error('Error getting database:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// Get database statistics
router.get('/databases/:id/stats', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const stats = await dbService.getDatabaseStats(id);

    res.json({
      success: true,
      data: stats
    });
  } catch (error: any) {
    console.error('Error getting database stats:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// Delete database
router.delete('/databases/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    await dbService.deleteDatabase(id);

    res.json({
      success: true,
      message: 'Database deleted successfully'
    });
  } catch (error: any) {
    console.error('Error deleting database:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// ===================================================================
// IP Whitelist Routes
// ===================================================================

// Add IP to whitelist
router.post('/databases/:id/whitelist', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { ipAddress, description } = req.body;

    if (!ipAddress) {
      return res.status(400).json({
        error: 'Bad Request',
        message: 'ipAddress is required'
      });
    }

    const whitelist = await whitelistService.addIP(id, { ipAddress, description });

    res.status(201).json({
      success: true,
      message: 'IP added to whitelist successfully',
      data: whitelist
    });
  } catch (error: any) {
    console.error('Error adding IP to whitelist:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// List IPs for database
router.get('/databases/:id/whitelist', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const whitelist = await whitelistService.listIPs(id);

    res.json({
      success: true,
      count: whitelist.length,
      data: whitelist
    });
  } catch (error: any) {
    console.error('Error listing whitelist:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// Remove IP from whitelist
router.delete('/databases/:id/whitelist/:whitelistId', async (req: Request, res: Response) => {
  try {
    const { id, whitelistId } = req.params;
    await whitelistService.removeIP(id, parseInt(whitelistId));

    res.json({
      success: true,
      message: 'IP removed from whitelist successfully'
    });
  } catch (error: any) {
    console.error('Error removing IP from whitelist:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

// ===================================================================
// Connection Strings Route (Neon-style)
// ===================================================================

// Get all connection string variants for a database
// Returns direct, pooled, and shadow URLs - all using the same database
router.get('/databases/:id/connection-strings', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const connectionStrings = await dbService.getConnectionStrings(id);

    res.json({
      success: true,
      data: connectionStrings
    });
  } catch (error: any) {
    console.error('Error getting connection strings:', error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
});

export default router;
