#!/bin/bash

# 資料庫環境變數預設值
DB_HOST=${DB_HOST:-"cacti-db"}
DB_USER=${DB_USER:-"cactiuser"}
DB_PASS=${DB_PASS:-"cactipassword"}
DB_NAME=${DB_NAME:-"cacti"}
DB_PORT=${DB_PORT:-3306}

# 1. 處理 Cacti 網頁端的 config.php
CONFIG_FILE="/var/www/localhost/htdocs/include/config.php"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating config.php from distribution..."
    cp /var/www/localhost/htdocs/include/config.php.dist "$CONFIG_FILE"
fi

#echo "Updating config.php with environment variables..."
#sed -i "s/\$database_hostname = .*/\$database_hostname = '$DB_HOST';/" "$CONFIG_FILE"
#sed -i "s/\$database_username = .*/\$database_username = '$DB_USER';/" "$CONFIG_FILE"
#sed -i "s/\$database_password = .*/\$database_password = '$DB_PASS';/" "$CONFIG_FILE"
#sed -i "s/\$database_default = .*/\$database_default = '$DB_NAME';/" "$CONFIG_FILE"
#sed -i "s/\$database_port = .*/\$database_port = '$DB_PORT';/" "$CONFIG_FILE"
#sed -i "s|\$url_path = '/cacti/';|\$url_path = '/';|" "$CONFIG_FILE"

echo "Updating config.php with environment variables..."

# 使用 | 作為分隔符，[[:space:]]* 匹配 0 到多個空格
sed -i "s|\$database_hostname[[:space:]]*=[[:space:]]*'[^']*';|\$database_hostname = '$DB_HOST';|g" "$CONFIG_FILE"
sed -i "s|\$database_username[[:space:]]*=[[:space:]]*'[^']*';|\$database_username = '$DB_USER';|g" "$CONFIG_FILE"
sed -i "s|\$database_password[[:space:]]*=[[:space:]]*'[^']*';|\$database_password = '$DB_PASS';|g" "$CONFIG_FILE"
sed -i "s|\$database_default[[:space:]]*=[[:space:]]*'[^']*';|\$database_default = '$DB_NAME';|g" "$CONFIG_FILE"
sed -i "s|\$database_port[[:space:]]*=[[:space:]]*'[^']*';|\$database_port = '$DB_PORT';|g" "$CONFIG_FILE"

# 針對 url_path
sed -i "s|\$url_path[[:space:]]*=[[:space:]]*'[^']*';|\$url_path = '/';|g" "$CONFIG_FILE"



# 2. 處理 Spine 的 spine.conf
echo "Updating Spine Configuration..."
cat <<EOF > /usr/local/spine/etc/spine.conf
DB_Host $DB_HOST
DB_Database $DB_NAME
DB_User $DB_USER
DB_Pass $DB_PASS
DB_Port $DB_PORT
DB_UseSSL 0
EOF

cat <<EOF > /etc/my.cnf
[client]
ssl=0
EOF

ln -s /usr/local/spine/etc/spine.conf /etc/spine.conf

# 3. 修正目錄權限
echo "Fixing Permissions..."
chown -R apache:apache /var/www/localhost/htdocs/

# 獲取環境變數，預設為 1 分鐘
# 可選值: 30s, 1m, 5m
INTERVAL=${POLLER_INTERVAL:-"1m"}

echo "Setting Poller interval to: $INTERVAL"

case $INTERVAL in
  "30s")
    # 每分鐘執行兩次，中間隔 30 秒
    cat <<EOF > /etc/crontabs/apache
* * * * * php /var/www/localhost/htdocs/poller.php > /dev/null 2>&1
* * * * * sleep 30; php /var/www/localhost/htdocs/poller.php > /dev/null 2>&1
EOF
    ;;
  "5m")
    echo "*/5 * * * * php /var/www/localhost/htdocs/poller.php > /dev/null 2>&1" > /etc/crontabs/apache
    ;;
  *)
    echo "* * * * * php /var/www/localhost/htdocs/poller.php > /dev/null 2>&1" > /etc/crontabs/apache
    ;;
esac

# --- 參數預設值 ---
PHP_MEMORY_LIMIT=${PHP_MEMORY_LIMIT:-"800M"}
PHP_MAX_EXECUTION_TIME=${PHP_MAX_EXECUTION_TIME:-"300"}
TZ=${TZ:-"Asia/Taipei"}


# --- 1. 動態修正 PHP 設定 ---
echo "Configuring PHP settings..."
PHP_INI="/etc/php83/php.ini"
sed -i "s/memory_limit = .*/memory_limit = $PHP_MEMORY_LIMIT/" $PHP_INI
sed -i "s/max_execution_time = .*/max_execution_time = $PHP_MAX_EXECUTION_TIME/" $PHP_INI
sed -i "s|;date.timezone =.*|date.timezone = $TZ|" $PHP_INI
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' $PHP_INI
sed -i 's/post_max_size = .*/post_max_size = 64M/' $PHP_INI

# --- 2. 動態修正 Apache 設定 ---
echo "Configuring Apache settings..."
HTTPD_CONF="/etc/apache2/httpd.conf"
sed -i 's/DirectoryIndex index.html/DirectoryIndex index.php index.html/' $HTTPD_CONF

# 修正 AH00558 警告
echo "ServerName localhost" >> $HTTPD_CONF

# 確保預設 index.html 不會擋路
if [ -f /var/www/localhost/htdocs/index.html ]; then
    rm /var/www/localhost/htdocs/index.html
fi

ROOT_PASS=${MYSQL_ROOT_PASSWORD:-"root_password"} # 匯入時區與授權需要 root

echo "Checking Database Status on $DB_HOST..."

# 1. 等待資料庫啟動
until mariadb-admin ping -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" --silent; do
    echo "Waiting for MariaDB..."
    sleep 2
done

# 2. 檢查是否需要初始化 (檢查 cacti 資料庫是否有資料表)
TABLE_COUNT=$(mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES;" | wc -l)

if [ "$TABLE_COUNT" -le 1 ]; then
    echo "Database is empty! Starting initialization..."

    # A. 匯入時區 (必須用 root)
    echo "Importing Timezone data..."
    #mariadb-tzinfo-to-sql /usr/share/zoneinfo | mariadb -h "$DB_HOST" -u root -p"$ROOT_PASS" mysql
    mariadb -h "$DB_HOST" -u root -p"$ROOT_PASS" mysql < /usr/share/cacti/timezone.sql

    # B. 授權時區權限給 cactiuser
    echo "Granting Timezone permissions..."
    mariadb -h "$DB_HOST" -u root -p"$ROOT_PASS" -e "GRANT SELECT ON mysql.time_zone_name TO '$DB_USER'@'%'; FLUSH PRIVILEGES;"

    # C. 匯入 Cacti 結構 (cacti.sql 檔案路徑需正確)
    CACTI_SQL_PATH="/var/www/localhost/htdocs/cacti.sql"
    if [ -f "$CACTI_SQL_PATH" ]; then
        echo "Importing cacti.sql..."
        mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$CACTI_SQL_PATH"
        echo "Importing fix-cacti.sql"
        mariadb -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < /fix-cacti.sql
    else
        echo "Error: $CACTI_SQL_PATH not found!"
    fi
    
    echo "Initialization Complete."
else
    echo "Database already initialized. Skipping."
fi



# 啟動服務
echo "Starting crond..."
crond -l 2
echo "Starting Apache..."
exec httpd -D FOREGROUND

