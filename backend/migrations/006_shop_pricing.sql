-- Shop pricing: per-shop rates and optional double-sided factor.
-- Only applies to users with role = 'shopkeeper'.
-- NULL = use platform env defaults.

ALTER TABLE users ADD COLUMN IF NOT EXISTS price_per_page_bw DECIMAL(10,2);
ALTER TABLE users ADD COLUMN IF NOT EXISTS price_per_page_color DECIMAL(10,2);
ALTER TABLE users ADD COLUMN IF NOT EXISTS double_sided_factor DECIMAL(3,2);

-- Constraint: if set, prices must be non-negative; double_sided_factor in (0, 1]
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_shop_pricing_check;
ALTER TABLE users ADD CONSTRAINT users_shop_pricing_check CHECK (
  (price_per_page_bw IS NULL OR (price_per_page_bw >= 0 AND price_per_page_bw <= 9999.99))
  AND (price_per_page_color IS NULL OR (price_per_page_color >= 0 AND price_per_page_color <= 9999.99))
  AND (double_sided_factor IS NULL OR (double_sided_factor > 0 AND double_sided_factor <= 1))
);

COMMENT ON COLUMN users.price_per_page_bw IS 'Shopkeeper: B&W price per page (NULL = platform default)';
COMMENT ON COLUMN users.price_per_page_color IS 'Shopkeeper: Color price per page (NULL = platform default)';
COMMENT ON COLUMN users.double_sided_factor IS 'Shopkeeper: multiplier for double-sided (e.g. 0.5 = half price); NULL = platform default';
