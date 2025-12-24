-- Initialize PostgreSQL with separate schemas for each app
-- This allows multiple apps to share one database instance

-- Create schemas
CREATE SCHEMA IF NOT EXISTS rapidphoto;
CREATE SCHEMA IF NOT EXISTS basedsecurity;

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA rapidphoto TO portfolio;
GRANT ALL PRIVILEGES ON SCHEMA basedsecurity TO portfolio;

-- Set default search paths (apps should also set this in their config)
ALTER DATABASE portfolio SET search_path TO public, rapidphoto, basedsecurity;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'Database initialized with schemas: rapidphoto, basedsecurity';
END $$;
