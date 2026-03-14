#!/bin/bash
# Manage Cloudflare Tunnel for Codeman web access.
#
# Uses remotely-managed tunnels via the Cloudflare API.
# No cloudflared login or cert.pem needed — only an API token.
#
# Required environment variables (passed via --remote-env from dcu):
#   CF_TUNNEL_API_TOKEN   — API token with Account:Cloudflare Tunnel:Edit + Zone:DNS:Edit + Zone:Zone:Read
#   CF_TUNNEL_ACCOUNT_ID  — Cloudflare account ID
#   CF_TUNNEL_DOMAIN      — Domain name (e.g. vm7.ai)
#
# Usage:
#   cloudflared-codeman.sh provision [name] [--domain vm7.ai] [--port 3000]
#   cloudflared-codeman.sh run [name] [--domain vm7.ai]
#   cloudflared-codeman.sh deprovision [name] [--domain vm7.ai]
#   cloudflared-codeman.sh token [name] [--domain vm7.ai]
#
# Name is optional — auto-detected from hostname.
# e.g. hostname "abc123" → codeman-abc123.vm7.ai
#
# Examples:
#   cloudflared-codeman.sh provision           # auto: codeman-abc123.vm7.ai
#   cloudflared-codeman.sh provision myname    # explicit: codeman-myname.vm7.ai
#   cloudflared-codeman.sh run                 # starts cloudflared tunnel
#   cloudflared-codeman.sh deprovision         # removes tunnel + DNS

set -euo pipefail

DEFAULT_PORT="3000"

log() { echo -e "\033[1;34m[cloudflared-codeman]\033[0m $1" >&2; }
err() { echo -e "\033[1;31m[cloudflared-codeman]\033[0m $1" >&2; }

# --- Validate required environment variables ---
require_env() {
  for var in CF_TUNNEL_API_TOKEN CF_TUNNEL_ACCOUNT_ID CF_TUNNEL_DOMAIN; do
    if [[ -z "${!var:-}" ]]; then
      err "Required env var ${var} is not set"
      exit 1
    fi
  done
}

# --- Cloudflare API helper ---
cf_api() {
  local method="$1" endpoint="$2" data="${3:-}"
  local args=(-sSL -X "$method"
    -H "Authorization: Bearer ${CF_TUNNEL_API_TOKEN}"
    -H "Content-Type: application/json"
    "https://api.cloudflare.com/client/v4${endpoint}")
  [[ -n "$data" ]] && args+=(-d "$data")
  curl "${args[@]}"
}

# --- Resolve zone ID from domain name ---
get_zone_id() {
  local domain="$1"
  local zone_id
  zone_id=$(cf_api GET "/zones?name=${domain}" | jq -r '.result[0].id // empty')
  if [[ -z "$zone_id" ]]; then
    err "Could not find zone ID for domain '${domain}'. Check API token permissions."
    exit 1
  fi
  echo "$zone_id"
}

# --- Get tunnel ID by name (empty if not found) ---
get_tunnel_id() {
  local name="$1"
  cf_api GET "/accounts/${CF_TUNNEL_ACCOUNT_ID}/cfd_tunnel?name=${name}&is_deleted=false" \
    | jq -r '.result[0].id // empty'
}

# --- Get tunnel token ---
get_tunnel_token() {
  local tunnel_id="$1"
  cf_api GET "/accounts/${CF_TUNNEL_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/token" \
    | jq -r '.result // empty'
}

# --- Derive tunnel name and FQDN ---
# Auto-generates from hostname if name not provided.
# e.g. hostname "abc123" → codeman-abc123.vm7.ai
parse_name() {
  local name="$1" domain="$2"
  if [[ -z "$name" ]]; then
    name=$(hostname -s)
  fi
  # Sanitize: lowercase, only alphanumeric and hyphens
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')
  if [[ -z "$name" ]]; then
    err "Invalid name: must contain at least one alphanumeric character"
    exit 1
  fi
  TUNNEL_NAME="codeman-${name}"
  TUNNEL_FQDN="${TUNNEL_NAME}.${domain}"
}

# ==========================================
# Provision
# ==========================================
do_provision() {
  local name="" domain="$CF_TUNNEL_DOMAIN" port="$DEFAULT_PORT"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;;
      --port)   port="$2"; shift 2 ;;
      -*)       err "Unknown option: $1"; exit 1 ;;
      *)        name="$1"; shift ;;
    esac
  done
  # name is optional — auto-detected from hostname

  require_env
  parse_name "$name" "$domain"
  local zone_id
  zone_id=$(get_zone_id "$domain")
  log "Provisioning tunnel ${TUNNEL_FQDN}"

  # Step 1: Create or reuse tunnel
  local tunnel_id
  tunnel_id=$(get_tunnel_id "$TUNNEL_NAME")

  if [[ -n "$tunnel_id" ]]; then
    log "Reusing existing tunnel: ${TUNNEL_NAME} (${tunnel_id})"
  else
    log "Creating tunnel: ${TUNNEL_NAME}"
    local create_resp
    create_resp=$(cf_api POST "/accounts/${CF_TUNNEL_ACCOUNT_ID}/cfd_tunnel" \
      "{\"name\":\"${TUNNEL_NAME}\",\"config_src\":\"cloudflare\",\"tunnel_secret\":\"$(openssl rand -base64 32)\"}")
    tunnel_id=$(echo "$create_resp" | jq -r '.result.id // empty')
    if [[ -z "$tunnel_id" ]]; then
      err "Failed to create tunnel: $(echo "$create_resp" | jq -r '.errors')"
      exit 1
    fi
    log "Created tunnel: ${tunnel_id}"
  fi

  # Step 2: Configure ingress rules
  log "Configuring ingress: ${TUNNEL_FQDN} -> http://localhost:${port}"
  local config_resp
  config_resp=$(cf_api PUT "/accounts/${CF_TUNNEL_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/configurations" \
    "{\"config\":{\"ingress\":[{\"hostname\":\"${TUNNEL_FQDN}\",\"service\":\"http://localhost:${port}\",\"originRequest\":{\"disableChunkedEncoding\":true}},{\"service\":\"http_status:404\"}]}}")
  if [[ "$(echo "$config_resp" | jq -r '.success')" != "true" ]]; then
    err "Failed to configure ingress: $(echo "$config_resp" | jq -r '.errors')"
    exit 1
  fi

  # Step 3: Create or update DNS CNAME record
  log "Configuring DNS: ${TUNNEL_FQDN} -> ${tunnel_id}.cfargotunnel.com"
  local existing_record_id
  existing_record_id=$(cf_api GET "/zones/${zone_id}/dns_records?type=CNAME&name=${TUNNEL_FQDN}" \
    | jq -r '.result[0].id // empty')

  local dns_data="{\"type\":\"CNAME\",\"name\":\"${TUNNEL_FQDN}\",\"content\":\"${tunnel_id}.cfargotunnel.com\",\"proxied\":true}"
  local dns_resp
  if [[ -n "$existing_record_id" ]]; then
    dns_resp=$(cf_api PUT "/zones/${zone_id}/dns_records/${existing_record_id}" "$dns_data")
  else
    dns_resp=$(cf_api POST "/zones/${zone_id}/dns_records" "$dns_data")
  fi
  if [[ "$(echo "$dns_resp" | jq -r '.success')" != "true" ]]; then
    err "Failed to configure DNS: $(echo "$dns_resp" | jq -r '.errors')"
    exit 1
  fi
  log "DNS record configured"

  log "Done! Tunnel provisioned"
  echo ""
  echo "  URL:   https://${TUNNEL_FQDN}"
  echo "  Run:   $0 run"
  echo ""
}

# ==========================================
# Run
# ==========================================
do_run() {
  local name="" domain="$CF_TUNNEL_DOMAIN"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;;
      -*)       err "Unknown option: $1"; exit 1 ;;
      *)        name="$1"; shift ;;
    esac
  done
  # name is optional — auto-detected from hostname

  require_env
  parse_name "$name" "$domain"

  local tunnel_id
  tunnel_id=$(get_tunnel_id "$TUNNEL_NAME")
  if [[ -z "$tunnel_id" ]]; then
    err "Tunnel '${TUNNEL_NAME}' not found. Run 'provision' first."
    exit 1
  fi

  local tunnel_token
  tunnel_token=$(get_tunnel_token "$tunnel_id")
  if [[ -z "$tunnel_token" ]]; then
    err "Failed to retrieve tunnel token"
    exit 1
  fi

  log "Starting tunnel: https://${TUNNEL_FQDN}"
  exec cloudflared tunnel --protocol http2 run --token "$tunnel_token"
}

# ==========================================
# Token (print token for external use)
# ==========================================
do_token() {
  local name="" domain="$CF_TUNNEL_DOMAIN"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;;
      -*)       err "Unknown option: $1"; exit 1 ;;
      *)        name="$1"; shift ;;
    esac
  done
  # name is optional — auto-detected from hostname

  require_env
  parse_name "$name" "$domain"

  local tunnel_id
  tunnel_id=$(get_tunnel_id "$TUNNEL_NAME")
  if [[ -z "$tunnel_id" ]]; then
    err "Tunnel '${TUNNEL_NAME}' not found. Run 'provision' first."
    exit 1
  fi

  get_tunnel_token "$tunnel_id"
}

# ==========================================
# Deprovision
# ==========================================
do_deprovision() {
  local name="" domain="$CF_TUNNEL_DOMAIN"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) domain="$2"; shift 2 ;;
      -*)       err "Unknown option: $1"; exit 1 ;;
      *)        name="$1"; shift ;;
    esac
  done
  # name is optional — auto-detected from hostname

  require_env
  parse_name "$name" "$domain"
  local zone_id
  zone_id=$(get_zone_id "$domain")
  log "Deprovisioning tunnel ${TUNNEL_FQDN}"

  local tunnel_id
  tunnel_id=$(get_tunnel_id "$TUNNEL_NAME")

  if [[ -z "$tunnel_id" ]]; then
    log "No tunnel found for ${TUNNEL_NAME}, nothing to do"
    return
  fi

  # Step 1: Delete tunnel (cascade forces disconnect)
  log "Deleting tunnel ${TUNNEL_NAME} (${tunnel_id})..."
  local del_resp
  del_resp=$(cf_api DELETE "/accounts/${CF_TUNNEL_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}?cascade=true")
  if [[ "$(echo "$del_resp" | jq -r '.success')" != "true" ]]; then
    err "Failed to delete tunnel: $(echo "$del_resp" | jq -r '.errors')"
    exit 1
  fi

  # Step 2: Delete DNS record
  local record_id
  record_id=$(cf_api GET "/zones/${zone_id}/dns_records?type=CNAME&name=${TUNNEL_FQDN}" \
    | jq -r '.result[0].id // empty')
  if [[ -n "$record_id" ]]; then
    local dns_del_resp
    dns_del_resp=$(cf_api DELETE "/zones/${zone_id}/dns_records/${record_id}")
    if [[ "$(echo "$dns_del_resp" | jq -r '.success')" != "true" ]]; then
      err "Warning: failed to delete DNS record: $(echo "$dns_del_resp" | jq -r '.errors')"
    else
      log "Deleted DNS record for ${TUNNEL_FQDN}"
    fi
  fi

  log "Done! Tunnel ${TUNNEL_NAME} removed"
}

# ==========================================
# Main
# ==========================================
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <provision|run|deprovision|token> [name] [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  provision [name]    Create tunnel + DNS (auto-detects name if omitted)" >&2
  echo "  run [name]          Start cloudflared tunnel connector" >&2
  echo "  deprovision [name]  Remove tunnel + DNS" >&2
  echo "  token [name]        Print tunnel token" >&2
  exit 1
fi

ACTION="$1"
shift

case "$ACTION" in
  provision)   do_provision "$@" ;;
  run)         do_run "$@" ;;
  deprovision) do_deprovision "$@" ;;
  token)       do_token "$@" ;;
  *)
    err "Unknown action: ${ACTION}"
    echo "Usage: $0 <provision|run|deprovision|token> [name] [options]" >&2
    exit 1
    ;;
esac
