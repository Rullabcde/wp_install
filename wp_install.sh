#!/bin/bash

# Exit on error
set -e

# Color function 
print_green() {
    echo -e "\e[32m$1\e[0m"
}

print_red() {
    echo -e "\e[31m$1\e[0m"
}

print_yellow() {
    echo -e "\e[33m$1\e[0m"
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    print_red "This script must be run as root."
    exit 1
fi

# Prompt for configuration variables
print_yellow "Please enter the following information:"
while [[ -z "$DOMAIN_NAME" ]]; do
    read -p "Enter domain name (e.g., example.com): " DOMAIN_NAME
done

while [[ -z "$DB_NAME" ]]; do
    read -p "Enter database name for WordPress: " DB_NAME
done

while [[ -z "$DB_USER" ]]; do
    read -p "Enter database user for WordPress: " DB_USER
done

while [[ -z "$DB_PASSWORD" ]]; do
    read -sp "Enter database password for WordPress: " DB_PASSWORD
    echo ""
done

while [[ -z "$MYSQL_ROOT_PASSWORD" ]]; do
    read -sp "Enter MySQL root password: " MYSQL_ROOT_PASSWORD
    echo ""
done

# Update system
print_green "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install required packages
print_green "Installing prerequisites..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 \
    mysql-server \
    php \
    php-mysql \
    php-curl \
    php-gd \
    php-mbstring \
    php-xml \
    php-zip \
    php-xmlrpc \
    php-soap \
    php-intl \
    php-bcmath \
    libapache2-mod-php wget curl

# Configure MySQL
print_green "Configuring MySQL..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Configure Apache
print_green "Configuring Apache..."
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/wordpress

    <Directory /var/www/html/wordpress>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Enable Apache modules
a2enmod rewrite
systemctl restart apache2

# Download and configure WordPress
print_green "Downloading and configuring WordPress..."
cd /tmp
wget https://wordpress.org/latest.tar.gz
if [[ -d /var/www/html/wordpress ]]; then
    rm -rf /var/www/html/wordpress
fi
tar xzvf latest.tar.gz
mv wordpress /var/www/html/
cd /var/www/html/wordpress

# Create and configure wp-config.php
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/$DB_NAME/g" wp-config.php
sed -i "s/username_here/$DB_USER/g" wp-config.php
sed -i "s/password_here/$DB_PASSWORD/g" wp-config.php

# Add security keys
curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php

# Create .htaccess file
cat > /var/www/html/wordpress/.htaccess << EOF
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF

# Set correct permissions
print_green "Setting correct permissions..."
chown -R www-data:www-data /var/www/html/wordpress
find /var/www/html/wordpress/ -type d -exec chmod 755 {} \;
find /var/www/html/wordpress/ -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/wordpress/wp-config.php

# Cleanup
print_green "Cleaning up..."
rm /tmp/latest.tar.gz

# Restart Apache
systemctl restart apache2

print_green "WordPress installation completed!"
print_yellow "
==============================================
Installation Details:
==============================================
WordPress Path: /var/www/html/wordpress
Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASSWORD
==============================================
"
