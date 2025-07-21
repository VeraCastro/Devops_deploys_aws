#!/bin/bash
# Script de instalación de phpMyFAQ para User Data de EC2 (Amazon Linux 2023)

# Actualizar el sistema
echo "Actualizando el sistema..."
dnf update -y

# Instalar repositorio EPEL (puede ser útil para algunas dependencias)
echo "Instalando repositorio EPEL..."
dnf install -y dnf-utils
dnf install -y https://dl.fedoraproject.com/pub/epel/epel-release-latest-9.noarch.rpm || echo "EPEL installation for EL9 failed, continuing..."

# Instalar Apache
echo "Instalando Apache..."
dnf install -y httpd
systemctl start httpd
systemctl enable httpd

# Instalar PHP 8.2 y extensiones requeridas
# Nota: Amazon Linux 2023 might default to a PHP version. This will install the default 'php' package and its modules.
# If a specific PHP 8.2 stream is needed and available, 'dnf module enable php:remi-8.2' or similar might be used after setting up Remi.
# For now, relying on AL2023's default PHP and available modules.
echo "Instalando PHP y extensiones requeridas..."
dnf install -y php php-cli php-common php-curl php-gd php-xml php-mbstring php-mysqlnd php-sodium php-intl php-zip php-opcache php-json php-fileinfo
php -v # Verificar la versión de PHP instalada

# Instalar MariaDB (usando el paquete específico mariadb105-server del ejemplo)
echo "Instalando MariaDB..."
dnf install -y mariadb105-server
if [ $? -ne 0 ]; then
    echo "Falló la instalación de mariadb105-server, intentando con mariadb-server..."
    dnf install -y mariadb-server
fi
systemctl start mariadb
systemctl enable mariadb

# Instalar Node.js 22 usando nvm (método recomendado por AWS)
echo "Instalando Node.js 22 vía nvm..."
dnf install -y curl git
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Configurar entorno NVM para la sesión actual del script
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    \. "$NVM_DIR/nvm.sh"
    echo "NVM script sourced."
else
    echo "NVM script no encontrado en $NVM_DIR/nvm.sh"
    # Intentar ruta alternativa si $HOME no es lo esperado en user-data (e.g. /root)
    export NVM_DIR="/root/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        \. "$NVM_DIR/nvm.sh"
        echo "NVM script sourced from /root/.nvm."
    else
        echo "NVM script no encontrado en /root/.nvm tampoco. La instalación de Node.js podría fallar."
    fi
fi

if [ -s "$NVM_DIR/bash_completion" ]; then
    \. "$NVM_DIR/bash_completion"
fi

nvm install 22
nvm use 22
nvm alias default 22

# Verificar versión de Node.js
echo "Versión de Node.js instalada:"
node -v || echo "Node.js no se instaló correctamente."

# Instalar pnpm globalmente
echo "Instalando pnpm globalmente..."
npm install -g pnpm || echo "Falló la instalación de pnpm."

# Configurar MariaDB - crear base de datos y usuario
echo "Configurando MariaDB..."
DB_NAME="phpmyfaq"
DB_USER="phpmyfaquser"
DB_PASS="PhpMyFAQ$(date +%s | sha256sum | base64 | head -c 12)" # Genera contraseña aleatoria

# Guardar credenciales para referencia
echo "Guardando credenciales de la base de datos en /root/phpmyfaq_credentials.txt..."
echo "Base de datos: $DB_NAME" > /root/phpmyfaq_credentials.txt
echo "Usuario: $DB_USER" >> /root/phpmyfaq_credentials.txt
echo "Contraseña: $DB_PASS" >> /root/phpmyfaq_credentials.txt
chmod 600 /root/phpmyfaq_credentials.txt

# Comandos SQL para configurar la base de datos
echo "Creando base de datos y usuario para phpMyFAQ..."
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" || echo "No se pudo eliminar la base de datos (puede que no existiera)."
mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';" || echo "No se pudo eliminar el usuario (puede que no existiera)."
# La siguiente línea es redundante si DROP USER funciona, pero se mantiene del ejemplo
mysql -e "DELETE FROM mysql.user WHERE User='$DB_USER' AND Host='localhost';" || true
mysql -e "FLUSH PRIVILEGES;" || echo "Falló FLUSH PRIVILEGES inicial."

mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"
echo "Base de datos y usuario creados."

# Eliminar directorio phpMyFAQ si ya existe
if [ -d "/var/www/html/phpmyfaq" ]; then
    echo "Eliminando directorio phpMyFAQ existente..."
    rm -rf /var/www/html/phpmyfaq
fi

# Descargar e instalar phpMyFAQ
echo "Descargando e instalando phpMyFAQ 4.0.7..."
cd /var/www/html
wget https://download.phpmyfaq.de/phpMyFAQ-4.0.7.tar.gz
tar -xzf phpMyFAQ-4.0.7.tar.gz
mv phpMyFAQ-4.0.7 phpmyfaq
rm phpMyFAQ-4.0.7.tar.gz

# Entrar al directorio de phpMyFAQ
# Las líneas de pnpm install y build están comentadas como en tu ejemplo,
# ya que el tar.gz usualmente viene pre-compilado.
# cd /var/www/html/phpmyfaq
# export NVM_DIR="$HOME/.nvm" # Asegurar que NVM está disponible si se descomentan
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# pnpm install
# pnpm build

# Configurar permisos
echo "Configurando permisos para phpMyFAQ..."
cd /var/www/html # Asegurarse de estar en el directorio correcto antes de chown
chown -R apache:apache /var/www/html/phpmyfaq
chmod -R 755 /var/www/html/phpmyfaq

# Crear directorios necesarios si no existen y establecer permisos
mkdir -p /var/www/html/phpmyfaq/images
mkdir -p /var/www/html/phpmyfaq/data
mkdir -p /var/www/html/phpmyfaq/config

chmod -R 777 /var/www/html/phpmyfaq/images
chmod -R 777 /var/www/html/phpmyfaq/data
chmod -R 777 /var/www/html/phpmyfaq/config
echo "Permisos de directorios data, images, config establecidos a 777."

# Crear archivo de configuración de Apache para phpMyFAQ
echo "Creando configuración de Apache para phpMyFAQ..."
cat > /etc/httpd/conf.d/phpmyfaq.conf << 'EOL'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/phpmyfaq
    ErrorLog /var/log/httpd/phpmyfaq-error.log
    CustomLog /var/log/httpd/phpmyfaq-access.log combined
    <Directory /var/www/html/phpmyfaq>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL

# Configurar SELinux si está habilitado
echo "Configurando SELinux si está habilitado..."
if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
    dnf install -y policycoreutils-python-utils
    semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/phpmyfaq/data(/.*)?" || echo "semanage data failed"
    semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/phpmyfaq/images(/.*)?" || echo "semanage images failed"
    semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/html/phpmyfaq/config(/.*)?" || echo "semanage config failed"
    restorecon -Rv /var/www/html/phpmyfaq || echo "restorecon failed"
    setsebool -P httpd_can_network_connect_db 1 || echo "setsebool httpd_can_network_connect_db failed"
    echo "SELinux configurado."
else
    echo "SELinux no está habilitado o getenforce no está disponible."
fi

# Reiniciar Apache para aplicar cambios
echo "Reiniciando Apache..."
systemctl restart httpd

# Mostrar información de instalación
echo "Obteniendo IP pública de la instancia..."
INSTANCE_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "tu-ip-publica")
echo "Instalación de phpMyFAQ completada" >> /root/phpmyfaq_credentials.txt
echo "Accede a http://$INSTANCE_IP/setup/index.php para completar la configuración de phpMyFAQ" >> /root/phpmyfaq_credentials.txt
echo "Información guardada en /root/phpmyfaq_credentials.txt" >> /root/phpmyfaq_credentials.txt
echo "--------------------------------------------------------------------"
echo "INSTALACIÓN COMPLETADA"
echo "Accede a phpMyFAQ para finalizar la configuración en:"
echo "http://$INSTANCE_IP/setup/index.php"
echo "Credenciales de la base de datos (para el asistente de phpMyFAQ):"
echo "  Base de datos: $DB_NAME"
echo "  Usuario: $DB_USER"
echo "  Contraseña: $DB_PASS"
echo "Esta información también está en /root/phpmyfaq_credentials.txt"
echo "--------------------------------------------------------------------"
