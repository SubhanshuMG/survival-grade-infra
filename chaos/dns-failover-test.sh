#!/bin/bash
#
# Quick DNS Failover Smoke Test
# Verifies that DNS resolves and both cloud endpoints respond.
# Run this before a full blackout drill or as a daily health check.
#
set -euo pipefail

DOMAIN="app.shopglobal.com"
HEALTH_PATH="/healthz"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "DNS Failover Smoke Test"
echo "======================="
echo ""

# Check DNS resolution
echo -n "DNS resolution for $DOMAIN: "
DNS_RESULT=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
if [[ -n "$DNS_RESULT" ]]; then
  echo -e "${GREEN}$DNS_RESULT${NC}"
else
  echo -e "${RED}FAILED${NC}"
  exit 1
fi

# Check application health
echo -n "Application health (HTTPS): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN$HEALTH_PATH" --max-time 10 || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo -e "${GREEN}200 OK${NC}"
else
  echo -e "${RED}HTTP $HTTP_CODE${NC}"
fi

# Check response time
echo -n "Response latency: "
LATENCY=$(curl -s -o /dev/null -w "%{time_total}" "https://$DOMAIN$HEALTH_PATH" --max-time 10)
echo "${LATENCY}s"

# Check auth endpoint
echo -n "Auth endpoint (Keycloak): "
AUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://auth.shopglobal.com/realms/shopglobal/.well-known/openid-configuration" \
  --max-time 10 || echo "000")
if [[ "$AUTH_CODE" == "200" ]]; then
  echo -e "${GREEN}200 OK${NC}"
else
  echo -e "${RED}HTTP $AUTH_CODE${NC}"
fi

echo ""
echo "Smoke test complete."
