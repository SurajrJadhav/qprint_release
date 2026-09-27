package database

import (
	"context"
	"log"
)

func InitSchema() {
	// Initial schema creation for users and files tables
	initialQuery := `
	CREATE TABLE IF NOT EXISTS users (
		id SERIAL PRIMARY KEY,
		username TEXT UNIQUE NOT NULL,
		password_hash TEXT NOT NULL,
		role TEXT NOT NULL,
		lat DOUBLE PRECISION,
		long DOUBLE PRECISION,
		address TEXT,
		-- Shopkeeper availability (default closed; opened via heartbeat/toggle)
		is_open BOOLEAN DEFAULT FALSE
	);

	CREATE TABLE IF NOT EXISTS files (
		id SERIAL PRIMARY KEY,
		user_id INT REFERENCES users(id),
		file_path TEXT NOT NULL,
		unique_code TEXT UNIQUE NOT NULL,
		status TEXT DEFAULT 'uploaded', -- Initially TEXT, will be converted to ENUM
		created_at TIMESTAMP DEFAULT NOW(),
		print_type TEXT DEFAULT 'private',
		copies INT DEFAULT 1,
		print_mode TEXT DEFAULT 'single',
		color_mode TEXT DEFAULT 'bw',
		paper_size TEXT DEFAULT 'A4',
		num_pages INT DEFAULT 0,
		total_cost DECIMAL(10,2) DEFAULT 0,
		shop_id INT REFERENCES users(id),
		queue_position INT
	);
	`

	_, err := DB.Exec(context.Background(), initialQuery)
	if err != nil {
		log.Fatalf("Failed to initialize database schema: %v", err)
	}

	// Migration for existing tables - add is_open column to users if not exists (default closed)
	_, err = DB.Exec(context.Background(), "ALTER TABLE users ADD COLUMN IF NOT EXISTS is_open BOOLEAN DEFAULT FALSE;")
	if err != nil {
		log.Printf("Migration warning (is_open): %v", err)
	}
	// Enforce default closed for new rows and normalize existing shopkeepers to closed
	_, _ = DB.Exec(context.Background(), "ALTER TABLE users ALTER COLUMN is_open SET DEFAULT FALSE;")
	_, _ = DB.Exec(context.Background(), "UPDATE users SET is_open = FALSE WHERE role = 'shopkeeper';")

	// Heartbeat/activity tracking for auto open/close
	_, _ = DB.Exec(context.Background(), "ALTER TABLE users ADD COLUMN IF NOT EXISTS last_app_heartbeat_at TIMESTAMP;")
	_, _ = DB.Exec(context.Background(), "ALTER TABLE users ADD COLUMN IF NOT EXISTS last_web_activity_at TIMESTAMP;")

	// Migration for existing tables - add comment column to files if not exists
	_, err = DB.Exec(context.Background(), "ALTER TABLE files ADD COLUMN IF NOT EXISTS comment TEXT;")
	if err != nil {
		log.Printf("Migration warning (comment): %v", err)
	}

	// Robust migration for file_status ENUM and 'status' column
	_, err = DB.Exec(context.Background(), `
	DO $$
	BEGIN
		-- Create the ENUM type if it doesn't exist
		IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'file_status') THEN
			CREATE TYPE file_status AS ENUM ('uploaded', 'downloaded', 'withdrawn', 'printing');
		ELSE
			-- Add 'withdrawn' value if the type exists but the value does not
			IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'file_status') AND enumlabel = 'withdrawn') THEN
				ALTER TYPE file_status ADD VALUE 'withdrawn';
			END IF;
			-- Add 'printing' value (shopkeeper started print; withdraw disabled until confirm or print-failed)
			IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'file_status') AND enumlabel = 'printing') THEN
				ALTER TYPE file_status ADD VALUE 'printing';
			END IF;
			-- Add 'cancelled' value (shopkeeper cancelled order before printing)
			IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'file_status') AND enumlabel = 'cancelled') THEN
				ALTER TYPE file_status ADD VALUE 'cancelled';
			END IF;
		END IF;

		-- Alter the 'status' column to use the new ENUM type if it's currently TEXT
		IF (SELECT data_type FROM information_schema.columns WHERE table_name = 'files' AND column_name = 'status') = 'text' THEN
			-- Normalize empty/NULL to 'uploaded' before casting, so USING status::file_status never sees ''
			UPDATE files SET status = 'uploaded' WHERE status IS NULL OR status = '';
			ALTER TABLE files ALTER COLUMN status DROP DEFAULT;
			ALTER TABLE files ALTER COLUMN status TYPE file_status USING status::text::file_status;
			ALTER TABLE files ALTER COLUMN status SET DEFAULT 'uploaded';
		END IF;

		-- Ensure default is set (idempotent for already-migrated columns)
		ALTER TABLE files ALTER COLUMN status SET DEFAULT 'uploaded';
	END
	$$;`)

	// Shopkeeper cancel: reason and who cancelled
	_, _ = DB.Exec(context.Background(), `ALTER TABLE files ADD COLUMN IF NOT EXISTS cancel_reason TEXT;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE files ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMP;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE files ADD COLUMN IF NOT EXISTS cancelled_by INT REFERENCES users(id) ON DELETE SET NULL;`)

	if err != nil {
		log.Printf("Migration warning (file_status enum management): %v", err)
	}

	// Payment system migration
	_, err = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS payment_orders (
		id SERIAL PRIMARY KEY,
		user_id INT REFERENCES users(id) NOT NULL,
		order_id TEXT UNIQUE NOT NULL,
		payment_id TEXT,
		amount DECIMAL(10,2) NOT NULL,
		status TEXT DEFAULT 'pending',
		payment_gateway TEXT DEFAULT 'razorpay',
		shopkeeper_id INT REFERENCES users(id),
		platform_commission DECIMAL(10,2) DEFAULT 0,
		shopkeeper_amount DECIMAL(10,2),
		copies INT DEFAULT 1,
		print_mode TEXT DEFAULT 'single',
		color_mode TEXT DEFAULT 'bw',
		paper_size TEXT DEFAULT 'A4',
		print_type TEXT DEFAULT 'private',
		comment TEXT,
		created_at TIMESTAMP DEFAULT NOW(),
		paid_at TIMESTAMP,
		expires_at TIMESTAMP,
		file_id INT REFERENCES files(id)
	);

	CREATE TABLE IF NOT EXISTS shopkeeper_payouts (
		id SERIAL PRIMARY KEY,
		shopkeeper_id INT REFERENCES users(id) NOT NULL,
		payment_order_id INT REFERENCES payment_orders(id) NOT NULL,
		amount DECIMAL(10,2) NOT NULL,
		status TEXT DEFAULT 'pending',
		payout_method TEXT,
		payout_reference TEXT,
		paid_at TIMESTAMP,
		created_at TIMESTAMP DEFAULT NOW(),
		UNIQUE(shopkeeper_id, payment_order_id)
	);

	CREATE INDEX IF NOT EXISTS idx_payment_orders_user_id ON payment_orders(user_id);
	CREATE INDEX IF NOT EXISTS idx_payment_orders_order_id ON payment_orders(order_id);
	CREATE INDEX IF NOT EXISTS idx_payment_orders_status ON payment_orders(status);
	CREATE INDEX IF NOT EXISTS idx_payment_orders_shopkeeper_id ON payment_orders(shopkeeper_id);
	CREATE INDEX IF NOT EXISTS idx_shopkeeper_payouts_shopkeeper_id ON shopkeeper_payouts(shopkeeper_id);
	CREATE INDEX IF NOT EXISTS idx_shopkeeper_payouts_status ON shopkeeper_payouts(status);
	`)

	// Store failed payout attempts (so admin can later mark as paid)
	_, _ = DB.Exec(context.Background(), `
	ALTER TABLE shopkeeper_payouts ADD COLUMN IF NOT EXISTS failed_at TIMESTAMP;
	ALTER TABLE shopkeeper_payouts ADD COLUMN IF NOT EXISTS failure_reason TEXT;
	`)

	if err != nil {
		log.Printf("Migration warning (payment system): %v", err)
	}

	// Add payment columns to files table
	_, err = DB.Exec(context.Background(), `
	ALTER TABLE files ADD COLUMN IF NOT EXISTS payment_order_id INT REFERENCES payment_orders(id);
	ALTER TABLE files ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid';
	CREATE INDEX IF NOT EXISTS idx_files_payment_order_id ON files(payment_order_id);
	CREATE INDEX IF NOT EXISTS idx_files_payment_status ON files(payment_status);
	`)

	if err != nil {
		log.Printf("Migration warning (files payment columns): %v", err)
	}

	// Phase 1: Add new user fields (full_name, email, phone, shop_name)
	_, err = DB.Exec(context.Background(), `
	ALTER TABLE users ADD COLUMN IF NOT EXISTS full_name TEXT;
	ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;
	ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
	ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_name TEXT;
	ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT NOW();
	ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();
	CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
	CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
	`)

	if err != nil {
		log.Printf("Migration warning (user fields): %v", err)
	}

	// Phase 2: Make phone unique for login-by-phone (drop non-unique index, create unique)
	_, _ = DB.Exec(context.Background(), `
	DROP INDEX IF EXISTS idx_users_phone;
	CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL AND phone != '';
	`)

	// Create password reset tokens table
	_, err = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS password_reset_tokens (
		id SERIAL PRIMARY KEY,
		user_id INT REFERENCES users(id) ON DELETE CASCADE,
		token TEXT UNIQUE NOT NULL,
		expires_at TIMESTAMP NOT NULL,
		used BOOLEAN DEFAULT FALSE,
		created_at TIMESTAMP DEFAULT NOW()
	);
	CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_token ON password_reset_tokens(token);
	CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_user_id ON password_reset_tokens(user_id);
	`)

	if err != nil {
		log.Printf("Migration warning (password_reset_tokens): %v", err)
	}

	// Migration: add token_selector for hashed-token lookup (security)
	_, _ = DB.Exec(context.Background(), `
	ALTER TABLE password_reset_tokens ADD COLUMN IF NOT EXISTS token_selector VARCHAR(8);
	CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_selector ON password_reset_tokens(token_selector);
	`)

	// Update role constraint to include 'admin'
	_, err = DB.Exec(context.Background(), `
	DO $$
	BEGIN
		-- Check if constraint exists and drop it
		IF EXISTS (
			SELECT 1 FROM pg_constraint 
			WHERE conname = 'users_role_check'
		) THEN
			ALTER TABLE users DROP CONSTRAINT users_role_check;
		END IF;
	END $$;
	`)

	if err != nil {
		log.Printf("Migration warning (role constraint): %v", err)
	}

	// Wallet: user balance and transactions
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS wallet_balance DECIMAL(10,2) DEFAULT 0.00;`)
	_, err = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS wallet_transactions (
		id SERIAL PRIMARY KEY,
		user_id INT REFERENCES users(id) NOT NULL,
		transaction_type TEXT NOT NULL,
		amount DECIMAL(10,2) NOT NULL,
		balance_before DECIMAL(10,2) NOT NULL,
		balance_after DECIMAL(10,2) NOT NULL,
		payment_order_id INT REFERENCES payment_orders(id),
		razorpay_payment_id TEXT,
		razorpay_refund_id TEXT,
		status TEXT DEFAULT 'completed',
		description TEXT,
		created_at TIMESTAMP DEFAULT NOW()
	);
	CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_id ON wallet_transactions(user_id);
	CREATE INDEX IF NOT EXISTS idx_wallet_transactions_type ON wallet_transactions(transaction_type);
	CREATE INDEX IF NOT EXISTS idx_wallet_transactions_payment_order_id ON wallet_transactions(payment_order_id);
	`)
	if err != nil {
		log.Printf("Migration warning (wallet_transactions): %v", err)
	}
	_, err = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS wallet_topup_orders (
		id SERIAL PRIMARY KEY,
		user_id INT REFERENCES users(id) NOT NULL,
		order_id TEXT UNIQUE NOT NULL,
		payment_id TEXT,
		amount DECIMAL(10,2) NOT NULL,
		status TEXT DEFAULT 'pending',
		created_at TIMESTAMP DEFAULT NOW()
	);
	CREATE INDEX IF NOT EXISTS idx_wallet_topup_orders_user_id ON wallet_topup_orders(user_id);
	CREATE INDEX IF NOT EXISTS idx_wallet_topup_orders_order_id ON wallet_topup_orders(order_id);
	`)
	if err != nil {
		log.Printf("Migration warning (wallet_topup_orders): %v", err)
	}
	_, _ = DB.Exec(context.Background(), `ALTER TABLE payment_orders ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'razorpay';`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE payment_orders ADD COLUMN IF NOT EXISTS wallet_amount DECIMAL(10,2) DEFAULT 0.00;`)
	// Allow NULL on user_id so account deletion can SET user_id = NULL and preserve order records for audit
	_, _ = DB.Exec(context.Background(), `
	DO $$ BEGIN
		IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'payment_orders' AND column_name = 'user_id' AND is_nullable = 'NO') THEN
			ALTER TABLE payment_orders ALTER COLUMN user_id DROP NOT NULL;
		END IF;
	END $$;`)

	// App download links (one row: Windows shopkeeper, Android customer, iOS customer). Managed from admin.
	_, _ = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS app_download_links (
		id SERIAL PRIMARY KEY,
		windows_shopkeeper_url TEXT DEFAULT '',
		android_customer_url TEXT DEFAULT '',
		ios_customer_url TEXT DEFAULT '',
		updated_at TIMESTAMP DEFAULT NOW()
	);
	`)
	_, _ = DB.Exec(context.Background(), `INSERT INTO app_download_links (id, windows_shopkeeper_url, android_customer_url, ios_customer_url)
		SELECT 1, '', '', '' WHERE NOT EXISTS (SELECT 1 FROM app_download_links WHERE id = 1);`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE app_download_links ADD COLUMN IF NOT EXISTS windows_shopkeeper_url TEXT DEFAULT '';`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE app_download_links ADD COLUMN IF NOT EXISTS android_customer_url TEXT DEFAULT '';`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE app_download_links ADD COLUMN IF NOT EXISTS ios_customer_url TEXT DEFAULT '';`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE app_download_links ADD COLUMN IF NOT EXISTS windows_coming_soon BOOLEAN DEFAULT true;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE app_download_links ADD COLUMN IF NOT EXISTS android_coming_soon BOOLEAN DEFAULT true;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE app_download_links ADD COLUMN IF NOT EXISTS ios_coming_soon BOOLEAN DEFAULT true;`)

	// 2FA: email OTP (password + code sent to email). TOTP columns kept for possible future use but not used in login flow.
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS email_2fa_enabled BOOLEAN DEFAULT false;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_secret TEXT;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN DEFAULT false;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_pending_secret TEXT;`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_pending_expires_at TIMESTAMP;`)

	// Pending email OTP for login 2FA step (one per user; code hashed, short-lived)
	_, _ = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS login_2fa_otps (
		user_id INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
		code_hash TEXT NOT NULL,
		expires_at TIMESTAMP NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_login_2fa_otps_expires_at ON login_2fa_otps(expires_at);
	`)

	// Admin login by email OTP (one active OTP per email; code hashed, short-lived)
	_, _ = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS admin_login_otps (
		email_lower TEXT PRIMARY KEY,
		code_hash TEXT NOT NULL,
		expires_at TIMESTAMP NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_admin_login_otps_expires_at ON admin_login_otps(expires_at);
	`)

	// Sign-up email OTP (one active OTP per email; code hashed, short-lived). Used before account creation.
	_, _ = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS signup_otps (
		email_lower TEXT PRIMARY KEY,
		code_hash TEXT NOT NULL,
		expires_at TIMESTAMP NOT NULL
	);
	CREATE INDEX IF NOT EXISTS idx_signup_otps_expires_at ON signup_otps(expires_at);
	`)

	// Login OTP (email only): request-otp stores here; verify-otp validates and issues JWT.
	_, _ = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS login_otps (
		contact_type TEXT NOT NULL,
		contact_value TEXT NOT NULL,
		code_hash TEXT NOT NULL,
		expires_at TIMESTAMP NOT NULL,
		attempts INT DEFAULT 0,
		created_at TIMESTAMP DEFAULT NOW(),
		PRIMARY KEY (contact_type, contact_value)
	);
	CREATE INDEX IF NOT EXISTS idx_login_otps_expires_at ON login_otps(expires_at);
	`)

	// Refer and Earn: referral_code on users (unique per customer), referrals table
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code TEXT;`)
	_, _ = DB.Exec(context.Background(), `CREATE UNIQUE INDEX IF NOT EXISTS idx_users_referral_code ON users(referral_code) WHERE referral_code IS NOT NULL AND referral_code != '';`)
	_, err = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS referrals (
		id SERIAL PRIMARY KEY,
		referrer_id INT REFERENCES users(id) ON DELETE SET NULL,
		referee_id INT REFERENCES users(id) ON DELETE SET NULL,
		referral_code_used TEXT NOT NULL,
		status TEXT NOT NULL DEFAULT 'signed_up',
		referee_email TEXT,
		referee_phone TEXT,
		amount_credited_referrer DECIMAL(10,2) DEFAULT 0,
		amount_credited_referee DECIMAL(10,2) DEFAULT 0,
		credited_at TIMESTAMP,
		created_at TIMESTAMP DEFAULT NOW()
	);
	CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id ON referrals(referrer_id);
	CREATE INDEX IF NOT EXISTS idx_referrals_referee_id ON referrals(referee_id);
	CREATE INDEX IF NOT EXISTS idx_referrals_status ON referrals(status);
	`)
	if err != nil {
		log.Printf("Migration warning (referrals table): %v", err)
	}
	// Rate limit for referral invite-by-email (per referrer per 24h)
	_, _ = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS referral_invite_log (
		id SERIAL PRIMARY KEY,
		referrer_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		invited_email VARCHAR(255) NOT NULL,
		created_at TIMESTAMP DEFAULT NOW()
	);
	CREATE INDEX IF NOT EXISTS idx_referral_invite_log_referrer_created ON referral_invite_log(referrer_id, created_at);
	`)

	// Shop pricing: per-shop rates and optional double-sided factor (shopkeepers only; NULL = platform default)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS price_per_page_bw DECIMAL(10,2);`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS price_per_page_color DECIMAL(10,2);`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS double_sided_factor DECIMAL(3,2);`)
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users DROP CONSTRAINT IF EXISTS users_shop_pricing_check;`)
	_, _ = DB.Exec(context.Background(), `
	ALTER TABLE users ADD CONSTRAINT users_shop_pricing_check CHECK (
		(price_per_page_bw IS NULL OR (price_per_page_bw >= 0 AND price_per_page_bw <= 9999.99))
		AND (price_per_page_color IS NULL OR (price_per_page_color >= 0 AND price_per_page_color <= 9999.99))
		AND (double_sided_factor IS NULL OR (double_sided_factor > 0 AND double_sided_factor <= 1))
	);`)

	// Shop code: 6-digit numeric, unique per shopkeeper (for "enter code" when QR fails). Optional until backfilled.
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_code INT;`)
	_, _ = DB.Exec(context.Background(), `CREATE UNIQUE INDEX IF NOT EXISTS idx_users_shop_code ON users(shop_code) WHERE shop_code IS NOT NULL;`)
	_, _ = DB.Exec(context.Background(), `
	DO $$ BEGIN
		IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_shop_code_range') THEN
			ALTER TABLE users ADD CONSTRAINT users_shop_code_range CHECK (shop_code IS NULL OR (shop_code >= 100000 AND shop_code <= 999999));
		END IF;
	END $$;`)

	// FCM device tokens for push notifications (customer app). One token per user per platform.
	_, err = DB.Exec(context.Background(), `
	CREATE TABLE IF NOT EXISTS fcm_tokens (
		user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		platform VARCHAR(20) NOT NULL DEFAULT 'android',
		fcm_token TEXT NOT NULL,
		updated_at TIMESTAMP DEFAULT NOW(),
		PRIMARY KEY (user_id, platform)
	);
	CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_id ON fcm_tokens(user_id);
	`)
	if err != nil {
		log.Printf("Migration warning (fcm_tokens): %v", err)
	}

	// Google Sign-In: stable subject id linked to user (password/email OTP remain available).
	_, _ = DB.Exec(context.Background(), `ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub TEXT;`)
	_, _ = DB.Exec(context.Background(), `CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_sub ON users(google_sub) WHERE google_sub IS NOT NULL AND google_sub != '';`)
}
