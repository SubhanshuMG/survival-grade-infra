#!/bin/bash
#
# BLACKOUT DRILL: Survival-Grade Architecture Test
# Simulates complete primary cloud failure and measures recovery.
# Run this quarterly. Make it policy, not optional.
#
# Prerequisites:
#   - CLOUDFLARE_API_TOKEN env var set
#   - CLOUDFLARE_ACCOUNT_ID env var set
#   - AWS_POOL_ID env var set (from terraform output)
#   - SLACK_WEBHOOK_URL env var set (optional)
#
# Usage:
#   chmod +x blackout-test.sh
#   ./blackout-test.sh
#
set -euo pipefail

# === Configuration ===
PRIMARY_CLOUD="aws"
SECONDARY_CLOUD="gcp"
APP_ENDPOINT="https://app.shopglobal.com"
HEALTH_ENDPOINT="$APP_ENDPOINT/healthz"
CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}"
AWS_POOL_ID="${AWS_POOL_ID}"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL:-}"

# === Utilities ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="blackout-drill-${TIMESTAMP}.log"

log() { echo -e "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
notify_slack() {
  if [[ -n "$SLACK_WEBHOOK" ]]; then
    curl -s -X POST "$SLACK_WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\": \"🚨 BLACKOUT DRILL: $1\"}" > /dev/null
  fi
}

# === Pre-Flight Checks ===
log "${YELLOW}═══════════════════════════════════════════${NC}"
log "${YELLOW}  BLACKOUT DRILL: $(date)${NC}"
log "${YELLOW}═══════════════════════════════════════════${NC}"
log ""

notify_slack "Blackout drill starting, simulating $PRIMARY_CLOUD failure"

log "Pre-flight: Checking both clouds are healthy..."

AWS_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_ENDPOINT" \
  -H "X-Force-Cloud: aws" --max-time 5 || echo "000")
GCP_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_ENDPOINT" \
  -H "X-Force-Cloud: gcp" --max-time 5 || echo "000")

log "  AWS health: $AWS_HEALTH"
log "  GCP health: $GCP_HEALTH"

if [[ "$AWS_HEALTH" != "200" ]] || [[ "$GCP_HEALTH" != "200" ]]; then
  log "${RED}ABORT: Both clouds must be healthy before drill${NC}"
  exit 1
fi

log "${GREEN}Pre-flight passed. Both clouds healthy.${NC}"
log ""

# === Phase 1: Baseline Measurement ===
log "${YELLOW}Phase 1: Measuring baseline performance...${NC}"

BASELINE_LATENCY=$(curl -s -o /dev/null -w "%{time_total}" "$HEALTH_ENDPOINT")
log "  Baseline latency: ${BASELINE_LATENCY}s"

TEST_ID="drill-$(uuidgen | head -c 8)"
WRITE_RESULT=$(curl -s -w "\n%{http_code}" -X POST "$APP_ENDPOINT/api/test-write" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$TEST_ID\", \"data\": \"blackout-drill-baseline\"}")
log "  Baseline write test: $(echo "$WRITE_RESULT" | tail -1)"

# === Phase 2: Simulate Primary Cloud Failure ===
log ""
log "${RED}Phase 2: SIMULATING PRIMARY CLOUD ($PRIMARY_CLOUD) FAILURE${NC}"
log "  Disabling $PRIMARY_CLOUD pool in Cloudflare..."

FAILOVER_START=$(date +%s%N)

curl -s -X PATCH \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/load_balancers/pools/${AWS_POOL_ID}" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}' > /dev/null

log "  ${RED}Primary cloud pool disabled.${NC}"
log "  Monitoring failover..."

# === Phase 3: Measure Failover ===
log ""
log "${YELLOW}Phase 3: Measuring failover time...${NC}"

ATTEMPTS=0
MAX_ATTEMPTS=60
FAILOVER_COMPLETE=false

while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_ENDPOINT" --max-time 5 || echo "000")
  ATTEMPTS=$((ATTEMPTS + 1))

  if [[ "$HTTP_CODE" == "200" ]]; then
    FAILOVER_END=$(date +%s%N)
    RTO_NS=$((FAILOVER_END - FAILOVER_START))
    RTO_SECONDS=$(echo "scale=2; $RTO_NS / 1000000000" | bc)
    log "  ${GREEN}Service recovered after $RTO_SECONDS seconds (attempt #$ATTEMPTS)${NC}"
    FAILOVER_COMPLETE=true
    break
  else
    log "  Attempt $ATTEMPTS: HTTP $HTTP_CODE (not yet recovered)"
    sleep 1
  fi
done

if [[ "$FAILOVER_COMPLETE" == "false" ]]; then
  log "${RED}CRITICAL: Failover did not complete within $MAX_ATTEMPTS seconds!${NC}"
  notify_slack "❌ FAILED: Failover did not complete within ${MAX_ATTEMPTS}s"
fi

# === Phase 4: Data Integrity Check ===
log ""
log "${YELLOW}Phase 4: Verifying data integrity on secondary cloud...${NC}"

READ_RESULT=$(curl -s "$APP_ENDPOINT/api/test-read/$TEST_ID" --max-time 10)
if echo "$READ_RESULT" | grep -q "blackout-drill-baseline"; then
  log "  ${GREEN}✓ Pre-failover data is accessible on secondary cloud${NC}"
  RPO_STATUS="PASS"
else
  log "  ${RED}✗ Pre-failover data NOT found, possible data loss${NC}"
  RPO_STATUS="FAIL"
fi

TEST_ID_2="drill-post-$(uuidgen | head -c 8)"
curl -s -X POST "$APP_ENDPOINT/api/test-write" \
  -H "Content-Type: application/json" \
  -d "{\"id\": \"$TEST_ID_2\", \"data\": \"blackout-drill-secondary\"}" > /dev/null
READ_RESULT_2=$(curl -s "$APP_ENDPOINT/api/test-read/$TEST_ID_2" --max-time 10)
if echo "$READ_RESULT_2" | grep -q "blackout-drill-secondary"; then
  log "  ${GREEN}✓ New writes on secondary cloud are working${NC}"
else
  log "  ${RED}✗ New writes on secondary cloud FAILED${NC}"
fi

# === Phase 5: Verify Auth Flow ===
log ""
log "${YELLOW}Phase 5: Verifying authentication on secondary...${NC}"

AUTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://auth.shopglobal.com/realms/shopglobal/.well-known/openid-configuration" \
  --max-time 10)
if [[ "$AUTH_RESPONSE" == "200" ]]; then
  log "  ${GREEN}✓ Keycloak OIDC discovery is accessible${NC}"
else
  log "  ${RED}✗ Keycloak is not responding (HTTP $AUTH_RESPONSE)${NC}"
fi

# === Phase 6: Restore Primary ===
log ""
log "${YELLOW}Phase 6: Restoring primary cloud...${NC}"

curl -s -X PATCH \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/load_balancers/pools/${AWS_POOL_ID}" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}' > /dev/null

log "  Primary pool re-enabled. Waiting for health check..."
sleep 30

AWS_POST_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_ENDPOINT" \
  -H "X-Force-Cloud: aws" --max-time 5 || echo "000")
log "  AWS post-restore health: $AWS_POST_HEALTH"

# === Results Summary ===
log ""
log "${YELLOW}═══════════════════════════════════════════${NC}"
log "${YELLOW}  BLACKOUT DRILL RESULTS${NC}"
log "${YELLOW}═══════════════════════════════════════════${NC}"
log ""
log "  RTO (Recovery Time):    ${RTO_SECONDS:-FAILED}s"
log "  RPO (Data Integrity):   ${RPO_STATUS}"
log "  Auth Continuity:        $([ "$AUTH_RESPONSE" == "200" ] && echo "PASS" || echo "FAIL")"
log "  Post-Restore Health:    $([ "$AWS_POST_HEALTH" == "200" ] && echo "PASS" || echo "FAIL")"
log ""

# Grade
if [[ "${RTO_SECONDS:-999}" < "60" ]] && [[ "$RPO_STATUS" == "PASS" ]]; then
  log "  ${GREEN}GRADE: A. Survival-grade resilience confirmed${NC}"
  notify_slack "✅ PASSED | RTO: ${RTO_SECONDS}s | RPO: PASS | Grade: A"
elif [[ "${RTO_SECONDS:-999}" < "300" ]]; then
  log "  ${YELLOW}GRADE: B. Acceptable but needs improvement${NC}"
  notify_slack "⚠️ PARTIAL | RTO: ${RTO_SECONDS}s | RPO: ${RPO_STATUS} | Grade: B"
else
  log "  ${RED}GRADE: F. Architecture is not survival-grade${NC}"
  notify_slack "❌ FAILED | RTO: ${RTO_SECONDS:-FAILED}s | RPO: ${RPO_STATUS} | Grade: F"
fi

log ""
log "Full log saved to: $LOG_FILE"
