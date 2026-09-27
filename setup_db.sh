#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Initializing QPrint Database...${NC}"

# Check if postgres is running
if ! systemctl is-active --quiet postgresql; then
    echo -e "${RED}PostgreSQL is not running. Attempting to start...${NC}"
    sudo systemctl start postgresql
fi

# Create user if not exists
echo "Configuring user 'xerox'..."
sudo -u postgres psql -c "DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'xerox') THEN
        CREATE ROLE xerox LOGIN PASSWORD 'xerox123';
    ELSE
        ALTER ROLE xerox WITH PASSWORD 'xerox123';
    END IF;
END
\$\$;"

# Create database if not exists
echo "Configuring database 'filesharing'..."
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw filesharing; then
    sudo -u postgres psql -c "CREATE DATABASE filesharing OWNER xerox;"
    echo -e "${GREEN}Database 'filesharing' created.${NC}"
else
    echo "Database 'filesharing' already exists."
fi

# Grant privileges
echo "Granting privileges..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE filesharing TO xerox;"
sudo -u postgres psql -d filesharing -c "GRANT ALL ON SCHEMA public TO xerox;"

echo -e "${GREEN}Database setup complete!${NC}"
echo "You can now run ./manage.sh start"
