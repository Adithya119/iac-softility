#!/bin/bash
sudo apt update
sudo apt install apache2 -y
cat <<EOF > /var/www/html/index.html
<html><body><h1>Hello from $(hostname)</h1></body></html>
EOF