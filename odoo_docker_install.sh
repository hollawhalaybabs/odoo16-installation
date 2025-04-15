#!/bin/bash

# This script installs Odoo 16 and PostgreSQL in Docker, configures SSL for Nginx, and deploys everything.

# Exit on error
set -e

# Variables
ODOO_VERSION=16.0
ODOO_IMAGE=odoo:$ODOO_VERSION
ODOO_CONTAINER_NAME=odoo_instance
ODOO_PORT=8069
NGINX_CONF_DIR=/etc/nginx/sites-available
NGINX_SITES_ENABLED=/etc/nginx/sites-enabled
SSL_CERT_DIR=/etc/ssl/certs
SSL_KEY_DIR=/etc/ssl/private
DOMAIN="yourdomain.com"
SSL_CERT_PATH="$SSL_CERT_DIR/$DOMAIN.crt"
SSL_KEY_PATH="$SSL_KEY_DIR/$DOMAIN.key"
POSTGRES_DB="postgres"
POSTGRES_USER="odoo"
POSTGRES_PASSWORD="openpgpwd"
PGDATA="/var/lib/pgsql/data/pgdata"
REPO_URL="https://github.com/your-org/your-custom-odoo-modules.git" # === CLONE CUSTOM MODULES (Optional) ===

# Update the system and install dependencies
echo "Updating system packages..."
apt-get update -y
apt-get install -y \
    docker.io \
    docker-compose \
    nginx \
    openssl \
    curl \
    sudo

# Start Docker and enable it to run at boot
echo "Starting Docker..."
systemctl start docker
systemctl enable docker

# Create Docker network if not already present
echo "Creating Docker network..."
docker network create odoo-net || echo "Network 'odoo-net' already exists."

# Create directories for Odoo data, configuration, and custom addons
echo "Creating directories for Odoo configuration and custom addons..."
mkdir -p ~/docker/odoo/config
mkdir -p ~/docker/odoo/custom_addons
mkdir -p ~/odoo_data
chmod 777 ~/odoo_data

# Clone custom modules repository (Optional)
echo "Cloning custom Odoo modules from repository..."
git clone $REPO_URL ~/docker/odoo/custom_addons || echo "Skipping Git clone..."

# Create environment variable file for PostgreSQL and Odoo
echo "Creating environment variables file..."
cat <<EOF > ~/docker/odoo/myenvfile.env
# PostgreSQL environment variables
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
PGDATA=$PGDATA

# Odoo environment variables
HOST=psql
USER=$POSTGRES_USER
PASSWORD=$POSTGRES_PASSWORD
EOF

# Create Docker Compose file for Odoo and PostgreSQL
echo "Creating Docker Compose file..."
cat <<EOF > ~/docker/odoo/docker-compose.yml
version: '3.8'

services:
  odoo:
    image: $ODOO_IMAGE
    container_name: $ODOO_CONTAINER_NAME
    env_file: myenvfile.env
    depends_on:
      - psql
    ports:
      - "$ODOO_PORT:$ODOO_PORT"
    volumes:
      - ~/odoo_data:/var/lib/odoo
      - ./config:/etc/odoo
      - ~/docker/odoo/custom_addons: # Mapped the cloned custom addons here

  psql:
    image: postgres:13
    container_name: psql_instance
    env_file: myenvfile.env
    volumes:
      - db:/var/lib/pgsql/data/pgdata

volumes:
  db:
EOF

# Create Odoo configuration file
echo "Creating Odoo configuration file..."
cat <<EOF > ~/docker/odoo/config/odoo.conf
[options]
admin_passwd = strong_admin_password
db_host = psql
db_user = $POSTGRES_USER
db_password = $POSTGRES_PASSWORD
db_port = 5432
addons_path = /custom_addons
EOF

# Start Odoo and PostgreSQL containers using Docker Compose
echo "Starting Odoo and PostgreSQL containers..."
cd ~/docker/odoo
docker-compose up -d

# Configure Nginx with SSL for Odoo
echo "Configuring Nginx with SSL..."
mkdir -p $SSL_CERT_DIR
mkdir -p $SSL_KEY_DIR

# Generate SSL certificates using OpenSSL (replace with your own certificate if needed)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $SSL_KEY_PATH -out $SSL_CERT_PATH -subj "/CN=$DOMAIN"

# Create Nginx configuration for Odoo
cat <<EOF > $NGINX_CONF_DIR/odoo.conf
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_CERT_PATH;
    ssl_certificate_key $SSL_KEY_PATH;

    location / {
        proxy_pass http://localhost:$ODOO_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable the Nginx configuration and restart Nginx
ln -s $NGINX_CONF_DIR/odoo.conf $NGINX_SITES_ENABLED/
systemctl restart nginx

# Print success message
echo "Odoo 16 is now running on Docker with PostgreSQL and SSL enabled via Nginx at https://$DOMAIN."
