#!/bin/bash -xe

SAMPLE_DATA=$1
MAGE_VERSION="1.9.1.0"
DATA_VERSION="1.9.1.0"

# Update Apt
# --------------------
apt-get update

# Install Apache & PHP
# --------------------
apt-get install -y apache2
apt-get install -y php5
apt-get install -y libapache2-mod-php5
apt-get install -y php5-mysqlnd php5-curl php5-xdebug php5-gd php5-intl php-pear php5-imap php5-mcrypt php5-ming php5-ps php5-pspell php5-recode php5-snmp php5-sqlite php5-tidy php5-xmlrpc php5-xsl php-soap

php5enmod mcrypt

# Delete default apache web dir and symlink mounted vagrant dir from host machine
# --------------------
rm -rf /var/www/html
mkdir /vagrant/httpdocs
ln -fs /vagrant/httpdocs /var/www/html

# Replace contents of default Apache vhost
# --------------------
VHOST=$(cat <<EOF
NameVirtualHost *:8080
Listen 8080
<VirtualHost *:80>
  DocumentRoot "/var/www/html"
  ServerName localhost
  <Directory "/var/www/html">
    AllowOverride All
  </Directory>
</VirtualHost>
<VirtualHost *:8080>
  DocumentRoot "/var/www/html"
  ServerName localhost
  <Directory "/var/www/html">
    AllowOverride All
  </Directory>
</VirtualHost>
EOF
)

echo "$VHOST" > /etc/apache2/sites-enabled/000-default.conf

a2enmod rewrite
service apache2 restart

# Mysql
# --------------------
# Ignore the post install questions
export DEBIAN_FRONTEND=noninteractive
# Install MySQL quietly
apt-get -q -y install mysql-server-5.5

mysql -u root -e "CREATE DATABASE IF NOT EXISTS magentodb"
mysql -u root -e "GRANT ALL PRIVILEGES ON magentodb.* TO 'magentouser'@'localhost' IDENTIFIED BY 'password'"
mysql -u root -e "FLUSH PRIVILEGES"


# Magento
# --------------------
# http://www.magentocommerce.com/wiki/1_-_installation_and_configuration/installing_magento_via_shell_ssh

# Download and extract
if [[ ! -f "/vagrant/httpdocs/index.php" ]]; then

  if [[ ! -f "/vagrant/magento-${MAGE_VERSION}.tar.gz" ]]; then
    # Only download Magento if we need to
    cd /vagrant
    wget https://github.com/OpenMage/magento-mirror/archive/${MAGE_VERSION}.tar.gz --progress dot:mega --output-document=magento-${MAGE_VERSION}.tar.gz
    #Magento now want you to register for latest versions
    #wget http://www.magentocommerce.com/downloads/assets/${MAGE_VERSION}/magento-${MAGE_VERSION}.tar.gz --progress dot:mega
  fi

  cd /vagrant/httpdocs
  tar -zxvf ../magento-${MAGE_VERSION}.tar.gz
  mv magento-mirror-${MAGE_VERSION}/* magento-mirror-${MAGE_VERSION}/.htaccess .
  chmod -R o+w media var
  chmod o+w app/etc
  # Clean up downloaded file and extracted dir
  rm -rf magento*
fi


# Sample Data
if [[ $SAMPLE_DATA == "true" ]]; then
  cd /vagrant

  if [[ ! -f "/vagrant/magento-sample-data-${DATA_VERSION}.tar.gz" ]]; then
    # Only download sample data if we need to
    # Magento now want you to register for latest versions & don't offer a direct download
    wget http://www.magentocommerce.com/downloads/assets/${DATA_VERSION}/magento-sample-data-${DATA_VERSION}.tar.gz --progress dot:giga
  fi

  tar -zxvf magento-sample-data-${DATA_VERSION}.tar.gz
  cp -R magento-sample-data-${DATA_VERSION}/media/* httpdocs/media/
  cp -R magento-sample-data-${DATA_VERSION}/skin/*  httpdocs/skin/
  mysql -u root magentodb < magento-sample-data-${DATA_VERSION}/magento_sample_data_for_${DATA_VERSION}.sql
  rm -rf magento-sample-data-${DATA_VERSION}
fi


# Run installer
if [ ! -f "/vagrant/httpdocs/app/etc/local.xml" ]; then
  cd /vagrant/httpdocs
  sudo /usr/bin/php -f install.php -- --license_agreement_accepted yes \
  --locale en_US --timezone "America/Los_Angeles" --default_currency USD \
  --db_host localhost --db_name magentodb --db_user magentouser --db_pass password \
  --url "http://127.0.0.1:8080/" --use_rewrites yes \
  --use_secure no --secure_base_url "http://127.0.0.1:8080/" --use_secure_admin no \
  --skip_url_validation yes \
  --admin_lastname Owner --admin_firstname Store --admin_email "admin@example.com" \
  --admin_username admin --admin_password password123123
  /usr/bin/php -f shell/indexer.php reindexall
fi

# Install n98-magerun
# --------------------
cd /vagrant/httpdocs
wget http://files.magerun.net/n98-magerun-latest.phar -O n98-magerun.phar --progress dot:mega
sudo mv ./n98-magerun.phar /usr/local/bin/
chmod +x /usr/local/bin/n98-magerun.phar

#Install Nexcessnet_Turpentine extension
sudo -u www-data n98-magerun.phar extension:install Nexcessnet_Turpentine --root-dir /vagrant/httpdocs/
#Must cache clean after extension install, otherwise TURPENTINE doesn't appear in Admin Panel - https://github.com/nexcess/magento-turpentine/wiki/FAQ
sudo -u www-data n98-magerun.phar cache:clean --root-dir /vagrant/httpdocs/