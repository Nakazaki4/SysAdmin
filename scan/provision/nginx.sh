#!/usr/bin/env bash
# nginx.sh - reverse proxy in front of Juice Shop that strips the two
# information-disclosure paths called out in F3. Juice Shop itself is
# bound to 127.0.0.1 (see juiceshop.sh), so clients can only reach it
# through this proxy.
apt-get update -q
apt-get install -y -q nginx

# The directory listing (/ftp) and the version banner are returned by Juice
# Shop on the same port as the rest of the app, so we cannot block them at
# the firewall. The next layer of containment is an L7 filter that refuses
# those paths before they reach the upstream.
cat > /etc/nginx/sites-available/juiceshop <<'EOF'
upstream juiceshop { server 127.0.0.1:3000; }

server {
    listen 10.10.20.20:3000 default_server;

    # F3 remediation: block the training-content directory listing.
    # 404 rather than 403 so we do not even confirm the path exists.
    location ~ ^/ftp(/|$) { return 404; }

    # F3 remediation: block the unauthenticated version banner.
    location = /rest/admin/application-version { return 404; }

    # Everything else proxied through.
    location / {
        proxy_pass http://juiceshop;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Default server listens on 0.0.0.0:80 — turn it off so nginx only answers
# on the lab IP:3000.
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/juiceshop /etc/nginx/sites-enabled/juiceshop

nginx -t
systemctl enable --now nginx
systemctl reload nginx
