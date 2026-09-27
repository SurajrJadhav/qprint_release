-- Migration: Add Payment System with Shopkeeper Tracking
-- This allows tracking which payment belongs to which shopkeeper
-- All payments go through single Razorpay account, but we track shopkeeper association

-- Payment Orders Table
CREATE TABLE IF NOT EXISTS payment_orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id) NOT NULL,           -- Customer who is paying
    order_id TEXT UNIQUE NOT NULL,                        -- Razorpay order_id
    payment_id TEXT,                                      -- Razorpay payment_id (after payment)
    amount DECIMAL(10,2) NOT NULL,                        -- Total amount paid
    status TEXT DEFAULT 'pending',                        -- 'pending', 'paid', 'failed', 'refunded', 'expired'
    payment_gateway TEXT DEFAULT 'razorpay',              -- 'razorpay'
    
    -- Shopkeeper Association (CRITICAL for tracking)
    shopkeeper_id INT REFERENCES users(id),               -- NULL for private prints, shopkeeper_id for queue prints
    platform_commission DECIMAL(10,2) DEFAULT 0,          -- Platform commission (optional, e.g., 10% = 0.10)
    shopkeeper_amount DECIMAL(10,2),                      -- Amount to be paid to shopkeeper (calculated)
    
    -- Print Configuration (stored before payment)
    copies INT DEFAULT 1,
    print_mode TEXT DEFAULT 'single',
    color_mode TEXT DEFAULT 'bw',
    paper_size TEXT DEFAULT 'A4',
    print_type TEXT DEFAULT 'private',                   -- 'private' or 'queue'
    comment TEXT,
    
    -- Metadata
    created_at TIMESTAMP DEFAULT NOW(),
    paid_at TIMESTAMP,
    expires_at TIMESTAMP,                                 -- Payment link expiry (default 30 min)
    
    -- File reference (after upload)
    file_id INT REFERENCES files(id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_payment_orders_user_id ON payment_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_order_id ON payment_orders(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_status ON payment_orders(status);
CREATE INDEX IF NOT EXISTS idx_payment_orders_shopkeeper_id ON payment_orders(shopkeeper_id);
CREATE INDEX IF NOT EXISTS idx_payment_orders_created_at ON payment_orders(created_at);

-- Shopkeeper Payouts Table (for tracking payouts to shopkeepers)
CREATE TABLE IF NOT EXISTS shopkeeper_payouts (
    id SERIAL PRIMARY KEY,
    shopkeeper_id INT REFERENCES users(id) NOT NULL,
    payment_order_id INT REFERENCES payment_orders(id) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,                        -- Amount paid to shopkeeper
    status TEXT DEFAULT 'pending',                        -- 'pending', 'paid', 'failed'
    payout_method TEXT,                                   -- 'razorpay_transfer', 'manual', 'bank_transfer'
    payout_reference TEXT,                                -- Transaction ID or reference
    paid_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(shopkeeper_id, payment_order_id)              -- Prevent duplicate payouts
);

CREATE INDEX IF NOT EXISTS idx_shopkeeper_payouts_shopkeeper_id ON shopkeeper_payouts(shopkeeper_id);
CREATE INDEX IF NOT EXISTS idx_shopkeeper_payouts_status ON shopkeeper_payouts(status);

-- Add payment reference to files table
ALTER TABLE files ADD COLUMN IF NOT EXISTS payment_order_id INT REFERENCES payment_orders(id);
ALTER TABLE files ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid'; -- 'unpaid', 'paid', 'refunded'

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_files_payment_order_id ON files(payment_order_id);
CREATE INDEX IF NOT EXISTS idx_files_payment_status ON files(payment_status);
