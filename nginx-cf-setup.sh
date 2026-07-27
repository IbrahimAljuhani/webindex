#!/bin/bash

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run this script with sudo privileges.${NC}"
  echo "Example: sudo ./webindex.sh"
  exit 1
fi

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}       Secure Multi-Domain Web Setup (Cloudflare)       ${NC}"
echo -e "${GREEN}========================================================${NC}"

# 1. Collect user inputs
read -p "Enter domain name (e.g., example.com): " DOMAIN
if [[ ! "$DOMAIN" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}Error: Domain format is invalid. Please re-run the script with a valid domain (e.g., example.com).${NC}"
    exit 1
fi

read -p "Also include www.$DOMAIN in the certificate and site config? (y/n): " INCLUDE_WWW
if [[ "$INCLUDE_WWW" == "y" || "$INCLUDE_WWW" == "Y" ]]; then
    SERVER_NAMES="$DOMAIN www.$DOMAIN"
    CERTBOT_DOMAIN_ARGS=(-d "$DOMAIN" -d "www.$DOMAIN")
    echo -e "${YELLOW}Note: make sure www.$DOMAIN also has a DNS Only (grey cloud) A/CNAME record pointing to this server before continuing.${NC}"
else
    SERVER_NAMES="$DOMAIN"
    CERTBOT_DOMAIN_ARGS=(-d "$DOMAIN")
fi

# Check if domain config already exists
if [ -f "/etc/nginx/sites-available/$DOMAIN" ]; then
    echo -e "${YELLOW}⚠️ Warning: Configuration for '$DOMAIN' already exists.${NC}"
    read -p "Do you want to overwrite it? This will reset the site config. (y/n): " OVERWRITE
    if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
        echo -e "${RED}Operation cancelled.${NC}"
        exit 1
    fi
fi

read -p "Enter your email for Let's Encrypt certificate: " EMAIL
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo -e "${RED}Error: Email format is invalid. Please re-run the script with a valid email.${NC}"
    exit 1
fi

# Fallback in case the script wasn't invoked via 'sudo' (SUDO_USER unset)
DEFAULT_WEB_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
read -p "Enter username to own website files (default: ${DEFAULT_WEB_USER:-none}): " WEB_USER
WEB_USER=${WEB_USER:-$DEFAULT_WEB_USER}

if [ -z "$WEB_USER" ]; then
    echo -e "${RED}Error: No username provided and no default could be determined. Please run via 'sudo ./webindex.sh' or enter a username manually.${NC}"
    exit 1
fi

# Check if user exists, if not, offer to create
if ! id -u "$WEB_USER" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️ User '$WEB_USER' does not exist on this system.${NC}"
    read -p "Do you want to create this user now? (y/n): " CREATE_USER
    if [[ "$CREATE_USER" == "y" || "$CREATE_USER" == "Y" ]]; then
        # Security: no login shell by default since this user only needs to own files.
        # If you need this user to log in via SSH/SFTP to upload files, change
        # /usr/sbin/nologin to /bin/bash afterwards with: usermod -s /bin/bash "$WEB_USER"
        useradd -m -s /usr/sbin/nologin "$WEB_USER"
        echo -e "${GREEN}✅ User '$WEB_USER' created successfully (no login shell).${NC}"
    else
        echo -e "${RED}Operation cancelled. User must exist to proceed.${NC}"
        exit 1
    fi
fi

WEB_ROOT="/var/www/$DOMAIN/html"

echo -e "\n${YELLOW}⚠️ Important warning before proceeding:${NC}"
echo "1. Make sure the A record in Cloudflare for $DOMAIN is set to DNS Only (grey cloud)."
echo "2. Make sure the domain points to this server's IP."
read -p "Have you done this and want to continue? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${RED}Operation cancelled.${NC}"
    exit 1
fi

# 2. Install required packages
echo -e "\n${GREEN}Installing required packages (Nginx, Certbot, ssl-cert, UFW, curl)...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -q
apt install nginx certbot python3-certbot-nginx ssl-cert ufw curl -y
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to install required packages.${NC}"
    exit 1
fi

# Hard-stop if ufw isn't actually available: the whole "Cloudflare-only" security
# model of this script depends on it, and every ufw call below is silenced
# (>/dev/null 2>&1), so a missing ufw would otherwise fail invisibly and leave
# the server with NO firewall at all while the script reports success.
if ! command -v ufw >/dev/null 2>&1; then
    echo -e "${RED}Error: 'ufw' is not available even after installation. Aborting — cannot guarantee firewall protection.${NC}"
    exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}Error: 'curl' is not available even after installation. Aborting — cannot fetch Cloudflare IP ranges.${NC}"
    exit 1
fi

# 2b. Hide Nginx version number (security hardening)
echo -e "\n${GREEN}Hiding Nginx version banner (server_tokens off)...${NC}"
# Try uncommenting the line Ubuntu ships commented-out by default (cleanest option)
sed -i 's/^\s*#\s*server_tokens\s\+off;/server_tokens off;/' /etc/nginx/nginx.conf
# If nginx.conf still doesn't have an active "server_tokens off;" line
# (custom/non-Ubuntu config), fall back to inserting one into the http block.
if ! grep -qE '^\s*server_tokens\s+off;' /etc/nginx/nginx.conf; then
    sed -i '/http {/a \\tserver_tokens off;' /etc/nginx/nginx.conf
fi
# Verify it actually took effect instead of assuming so
if grep -qE '^\s*server_tokens\s+off;' /etc/nginx/nginx.conf; then
    echo -e "${GREEN}✅ server_tokens off is active.${NC}"
else
    echo -e "${YELLOW}⚠️ Warning: Could not confirm server_tokens off in nginx.conf. Please set it manually.${NC}"
fi

# 3. Configure UFW firewall for Cloudflare only
echo -e "\n${GREEN}Configuring firewall (UFW) to allow Cloudflare only...${NC}"
ufw allow OpenSSH > /dev/null 2>&1

CF_V4=$(curl -s https://www.cloudflare.com/ips-v4)
CF_V6=$(curl -s https://www.cloudflare.com/ips-v6)

if [ -z "$CF_V4" ] && [ -z "$CF_V6" ]; then
    echo -e "${RED}Error: Failed to fetch Cloudflare IP ranges. Firewall/real-IP setup depends on this. Aborting.${NC}"
    exit 1
fi

if [ -n "$CF_V4" ]; then
    for ip in $CF_V4; do
        ufw delete allow from "$ip" to any port 80,443 proto tcp > /dev/null 2>&1
        ufw allow from "$ip" to any port 80,443 proto tcp > /dev/null 2>&1
    done
fi
if [ -n "$CF_V6" ]; then
    for ip in $CF_V6; do
        ufw delete allow from "$ip" to any port 80,443 proto tcp > /dev/null 2>&1
        ufw allow from "$ip" to any port 80,443 proto tcp > /dev/null 2>&1
    done
fi

if ! ufw status | grep -q "Status: active"; then
    echo "y" | ufw enable > /dev/null 2>&1
fi

# 4. Create website directory with STRICT ISOLATION
echo -e "\n${GREEN}Creating isolated website directory: $WEB_ROOT${NC}"
mkdir -p "$WEB_ROOT"

# Security: Owner is the user, Group is www-data (so Nginx can read)
chown -R "$WEB_USER":www-data "$WEB_ROOT"

# Security: Directories 750 (Owner: rwx, Group: r-x, Others: ---)
find "$WEB_ROOT" -type d -exec chmod 750 {} \;
# Security: Files 640 (Owner: rw-, Group: r--, Others: ---)
find "$WEB_ROOT" -type f -exec chmod 640 {} \;

# Ensure parent directories are traversable by Nginx
chmod 755 /var/www
chmod 751 "/var/www/$DOMAIN"

echo "<h1>Welcome to $DOMAIN</h1><p>Server is configured securely with isolated permissions.</p>" > "$WEB_ROOT/index.html"
chmod 640 "$WEB_ROOT/index.html"

# 5. Initial Nginx configuration
echo -e "\n${GREEN}Writing initial Nginx configuration...${NC}"
rm -f /etc/nginx/sites-enabled/default

# Shared catch-all block for direct-IP access (created ONCE, shared by all domains).
# This avoids a "duplicate default_server" error when this script is run again
# for a second/third domain.
CATCHALL_FILE="/etc/nginx/sites-available/00-catchall"
if [ ! -f "$CATCHALL_FILE" ]; then
    cat <<'EOF' > "$CATCHALL_FILE"
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    return 444;
}
EOF
    ln -sf "$CATCHALL_FILE" /etc/nginx/sites-enabled/
    echo -e "${GREEN}Created shared catch-all config for direct-IP access.${NC}"
fi

cat <<EOF > /etc/nginx/sites-available/$DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAMES;
    
    root $WEB_ROOT;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
nginx -t > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}Error in initial Nginx configuration test.${NC}"
    exit 1
else
    systemctl reload nginx
fi

# 6. Open port 80 temporarily for Let's Encrypt
echo -e "\n${YELLOW}Opening port 80 temporarily for SSL verification...${NC}"
ufw allow 80/tcp > /dev/null 2>&1

# 7. Extract SSL certificate
echo -e "\n${GREEN}Extracting SSL certificate via Certbot...${NC}"
certbot --nginx "${CERTBOT_DOMAIN_ARGS[@]}" --email "$EMAIL" --agree-tos --no-eff-email --redirect

CERTBOT_STATUS=$?
if [ $CERTBOT_STATUS -ne 0 ]; then
    echo -e "${RED}Failed to extract certificate. Check Cloudflare DNS (must be grey cloud).${NC}"
    ufw delete allow 80/tcp > /dev/null 2>&1
    exit 1
fi

# 8. Apply final advanced Nginx configuration
echo -e "\n${GREEN}Applying final Nginx configuration (block IP + real IP retrieval + HSTS)...${NC}"

# Dynamically generate Cloudflare IP lines for Nginx (built with real newlines)
CF_NGINX_IPS=""
for ip in $CF_V4 $CF_V6; do
    CF_NGINX_IPS="${CF_NGINX_IPS}    set_real_ip_from ${ip};
"
done

cat <<EOF > /etc/nginx/sites-available/$DOMAIN
# Note: direct-IP access on ports 80/443 is blocked by the shared
# /etc/nginx/sites-available/00-catchall config, not repeated here.

# 1. Redirect HTTP to HTTPS + retrieve real IP
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAMES;
    
${CF_NGINX_IPS}
    real_ip_header CF-Connecting-IP;
    
    return 301 https://\$host\$request_uri;
}

# 2. HTTPS configuration + real IP retrieval + HSTS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $SERVER_NAMES;
    
${CF_NGINX_IPS}
    real_ip_header CF-Connecting-IP;
    
    root $WEB_ROOT;
    index index.html index.htm;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# 9. Cleanup and restart Nginx
echo -e "\n${GREEN}Closing temporary port 80 and restarting Nginx...${NC}"
ufw delete allow 80/tcp > /dev/null 2>&1
nginx -t > /dev/null 2>&1
if [ $? -eq 0 ]; then
    systemctl reload nginx
else
    echo -e "${RED}Error in final Nginx configuration test.${NC}"
    exit 1
fi

# 10. Final success message
echo -e "\n${GREEN}========================================================${NC}"
echo -e "${GREEN} ✅ Website setup completed successfully! ${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "📁 Website files path: ${YELLOW}$WEB_ROOT${NC}"
echo -e "👤 Owner: ${YELLOW}$WEB_USER${NC} | Group: ${YELLOW}www-data${NC}"
echo -e "🔒 SSL certificate installed for: ${YELLOW}$DOMAIN${NC}"
echo -e "🛡️  Isolation: Enabled (Others have NO access to these files)"
echo -e "\n${YELLOW}⚠️ Post-setup steps (very important):${NC}"
echo "1. Go to Cloudflare dashboard."
echo "2. Change the cloud icon for the domain from grey to orange (Proxied)."
echo "3. Go to SSL/TLS > Overview and make sure the mode is Full (Strict)."
echo -e "${GREEN}========================================================${NC}"