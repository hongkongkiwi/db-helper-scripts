-- Test fixture data for database helper script testing
-- This will be automatically loaded into test databases on startup

-- Create test schemas
CREATE SCHEMA IF NOT EXISTS test_schema;
CREATE SCHEMA IF NOT EXISTS public;

-- Create test tables with various data types
CREATE TABLE IF NOT EXISTS public.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS public.orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES public.users(id),
    order_date TIMESTAMP DEFAULT NOW(),
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS public.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category VARCHAR(50),
    in_stock INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS public.order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES public.orders(id),
    product_id INTEGER REFERENCES public.products(id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL
);

-- Create a table in test schema
CREATE TABLE IF NOT EXISTS test_schema.test_table (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    data TEXT
);

-- Create temporary tables for testing exclusion
CREATE TABLE IF NOT EXISTS public.temp_logs (
    id SERIAL PRIMARY KEY,
    message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.cache_data (
    id SERIAL PRIMARY KEY,
    cache_key VARCHAR(255),
    cache_value TEXT,
    expires_at TIMESTAMP
);

-- Create sequences
CREATE SEQUENCE IF NOT EXISTS public.custom_seq START 1000;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_date ON public.orders(order_date);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);

-- Create views
CREATE OR REPLACE VIEW public.active_users AS
SELECT id, username, email, created_at
FROM public.users
WHERE is_active = TRUE;

CREATE OR REPLACE VIEW public.order_summary AS
SELECT 
    o.id as order_id,
    u.username,
    o.order_date,
    o.total_amount,
    o.status
FROM public.orders o
JOIN public.users u ON o.user_id = u.id;

-- Create functions
CREATE OR REPLACE FUNCTION public.get_user_order_count(user_id_param INTEGER)
RETURNS INTEGER AS $$
BEGIN
    RETURN (SELECT COUNT(*) FROM public.orders WHERE user_id = user_id_param);
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE OR REPLACE FUNCTION public.update_modified_time()
RETURNS TRIGGER AS $$
BEGIN
    NEW.created_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Insert test data
INSERT INTO public.users (username, email, metadata) VALUES
('testuser1', 'test1@example.com', '{"role": "admin", "preferences": {"theme": "dark"}}'),
('testuser2', 'test2@example.com', '{"role": "user", "preferences": {"theme": "light"}}'),
('testuser3', 'test3@example.com', '{"role": "user", "preferences": {"theme": "auto"}}'),
('inactive_user', 'inactive@example.com', '{"role": "user"}')
ON CONFLICT (username) DO NOTHING;

-- Update one user to inactive for testing
UPDATE public.users SET is_active = FALSE WHERE username = 'inactive_user';

INSERT INTO public.products (name, description, price, category, in_stock) VALUES
('Test Product 1', 'A test product for testing', 19.99, 'electronics', 100),
('Test Product 2', 'Another test product', 29.99, 'books', 50),
('Test Product 3', 'Third test product', 39.99, 'electronics', 25),
('Out of Stock Product', 'This product is out of stock', 9.99, 'books', 0)
ON CONFLICT DO NOTHING;

INSERT INTO public.orders (user_id, total_amount, status) VALUES
((SELECT id FROM public.users WHERE username = 'testuser1'), 59.97, 'completed'),
((SELECT id FROM public.users WHERE username = 'testuser2'), 29.99, 'pending'),
((SELECT id FROM public.users WHERE username = 'testuser1'), 19.99, 'shipped')
ON CONFLICT DO NOTHING;

INSERT INTO public.order_items (order_id, product_id, quantity, unit_price)
SELECT 
    o.id,
    p.id,
    CASE WHEN p.name = 'Test Product 1' THEN 2 ELSE 1 END,
    p.price
FROM public.orders o
CROSS JOIN public.products p
WHERE o.user_id = (SELECT id FROM public.users WHERE username = 'testuser1')
AND p.name IN ('Test Product 1', 'Test Product 3')
AND o.total_amount = 59.97
ON CONFLICT DO NOTHING;

INSERT INTO test_schema.test_table (name, data) VALUES
('test_record_1', 'Some test data'),
('test_record_2', 'More test data'),
('test_record_3', 'Even more test data')
ON CONFLICT DO NOTHING;

INSERT INTO public.temp_logs (message) VALUES
('Test log entry 1'),
('Test log entry 2'),
('Test log entry 3')
ON CONFLICT DO NOTHING;

INSERT INTO public.cache_data (cache_key, cache_value, expires_at) VALUES
('test_key_1', 'test_value_1', NOW() + INTERVAL '1 hour'),
('test_key_2', 'test_value_2', NOW() + INTERVAL '2 hours'),
('expired_key', 'expired_value', NOW() - INTERVAL '1 hour')
ON CONFLICT DO NOTHING;

-- Create constraints
ALTER TABLE public.orders 
ADD CONSTRAINT chk_total_amount_positive 
CHECK (total_amount > 0);

ALTER TABLE public.products 
ADD CONSTRAINT chk_price_positive 
CHECK (price > 0);

-- Create some additional test users for user management testing
DO $$
BEGIN
    -- Create test roles if they don't exist
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'test_readonly') THEN
        CREATE ROLE test_readonly;
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'test_readwrite') THEN
        CREATE ROLE test_readwrite;
    END IF;
    
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'test_admin') THEN
        CREATE ROLE test_admin CREATEDB CREATEROLE;
    END IF;
END
$$;

-- Grant permissions for testing
GRANT CONNECT ON DATABASE testdb TO test_readonly;
GRANT USAGE ON SCHEMA public TO test_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO test_readonly;

GRANT CONNECT ON DATABASE testdb TO test_readwrite;
GRANT USAGE ON SCHEMA public TO test_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO test_readwrite;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO test_readwrite;

-- Create extension for testing
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Insert some large object data for testing
DO $$
DECLARE
    loid OID;
BEGIN
    SELECT lo_create(0) INTO loid;
    PERFORM lo_put(loid, 0, 'This is test binary data for large object testing');
END
$$;

-- Create statistics for testing
ANALYZE public.users;
ANALYZE public.orders;
ANALYZE public.products;
ANALYZE public.order_items;

-- Create a test trigger
CREATE TRIGGER update_users_modified
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.update_modified_time();

COMMIT; 