#!/usr/bin/env bash
# Self-signed root CA + server certificate for the central Alloy (alloy.org).
# Clients must trust ca.crt. Run once; existing files are kept (delete them to rotate).
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f ca.key ]]; then
  openssl req -x509 -new -nodes -newkey rsa:4096 -sha256 -days 3650 \
    -keyout ca.key -out ca.crt -subj "/CN=Fish Lab Root CA"
fi

if [[ ! -f alloy.org.key ]]; then
  openssl req -new -nodes -newkey rsa:2048 -keyout alloy.org.key -out alloy.org.csr -subj "/CN=alloy.org"
  openssl x509 -req -in alloy.org.csr -CA ca.crt -CAkey ca.key -CAcreateserial -sha256 -days 825 \
    -out alloy.org.crt -extfile <(printf "subjectAltName=DNS:alloy.org\nextendedKeyUsage=serverAuth\n")
  rm alloy.org.csr
fi

chmod 0644 ca.crt alloy.org.crt
chmod 0600 ca.key alloy.org.key
openssl verify -CAfile ca.crt alloy.org.crt
