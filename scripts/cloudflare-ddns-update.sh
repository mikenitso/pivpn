#!/usr/bin/env bash
set -euo pipefail

log() {
  local level="$1"
  shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

fail() {
  log ERROR "$*"
  exit 1
}

need_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
}

validate_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=.
  local part
  for part in $ip; do
    ((part >= 0 && part <= 255)) || return 1
  done
}

fetch_ip_cloudflare_trace() {
  local trace ip
  trace="$(curl -fsS --max-time 10 https://cloudflare.com/cdn-cgi/trace)" || return 1
  ip="$(printf '%s\n' "$trace" | sed -n 's/^ip=//p' | head -n 1)"
  [[ -n "$ip" ]] || return 1
  validate_ipv4 "$ip" || return 1
  printf '%s\n' "$ip"
}

fetch_ip_ipify() {
  local ip
  ip="$(curl -fsS --max-time 10 https://api.ipify.org)" || return 1
  validate_ipv4 "$ip" || return 1
  printf '%s\n' "$ip"
}

fetch_ip_ifconfig_co() {
  local ip
  ip="$(curl -fsS --max-time 10 https://ifconfig.co/ip)" || return 1
  ip="$(echo "$ip" | tr -d '[:space:]')"
  validate_ipv4 "$ip" || return 1
  printf '%s\n' "$ip"
}

resolve_public_ipv4() {
  local sources source ip
  sources="${CF_IP_SOURCES:-cloudflare_trace ipify ifconfig_co}"

  for source in $sources; do
    case "$source" in
      cloudflare_trace)
        ip="$(fetch_ip_cloudflare_trace || true)"
        ;;
      ipify)
        ip="$(fetch_ip_ipify || true)"
        ;;
      ifconfig_co)
        ip="$(fetch_ip_ifconfig_co || true)"
        ;;
      *)
        log WARN "Unknown IP source token '$source'; skipping"
        ip=""
        ;;
    esac
    if [[ -n "$ip" ]]; then
      log INFO "Public IPv4 resolved via $source: $ip"
      printf '%s\n' "$ip"
      return 0
    fi
  done

  return 1
}

cf_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local body_file response
  body_file="$(mktemp)"

  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4${endpoint}" \
      --data "$data" >"$body_file" || {
      rm -f "$body_file"
      fail "Cloudflare API request failed: ${method} ${endpoint}"
    }
  else
    curl -fsS -X "$method" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4${endpoint}" >"$body_file" || {
      rm -f "$body_file"
      fail "Cloudflare API request failed: ${method} ${endpoint}"
    }
  fi

  response="$(cat "$body_file")"
  rm -f "$body_file"

  if [[ "$(printf '%s' "$response" | jq -r '.success // false')" != "true" ]]; then
    fail "Cloudflare API returned unsuccessful response for ${method} ${endpoint}: $(printf '%s' "$response" | jq -c '.errors // []')"
  fi

  printf '%s\n' "$response"
}

validate_inputs() {
  [[ -n "${CF_API_TOKEN:-}" ]] || fail "CF_API_TOKEN is required"
  [[ -n "${CF_ZONE_NAME:-}" ]] || fail "CF_ZONE_NAME is required"
  [[ -n "${CF_SUBDOMAIN:-}" ]] || fail "CF_SUBDOMAIN is required"

  [[ "${CF_ZONE_NAME}" =~ ^[A-Za-z0-9.-]+$ ]] || fail "CF_ZONE_NAME format is invalid"
  [[ "${CF_SUBDOMAIN}" =~ ^[A-Za-z0-9-]+$ ]] || fail "CF_SUBDOMAIN format is invalid"

  CF_PROXIED="${CF_PROXIED:-false}"
  CF_TTL="${CF_TTL:-1}"
}

main() {
  need_cmd curl
  need_cmd jq

  validate_inputs

  local record_name current_ip zone_json zone_id records_json record_count record_id record_ip
  record_name="${CF_SUBDOMAIN}.${CF_ZONE_NAME}"

  current_ip="$(resolve_public_ipv4 || true)"
  [[ -n "$current_ip" ]] || fail "Could not resolve public IPv4 from configured sources"

  zone_id="${CF_ZONE_ID:-}"
  if [[ -z "$zone_id" ]]; then
    zone_json="$(cf_api GET "/zones?name=${CF_ZONE_NAME}&status=active&per_page=1")"
    zone_id="$(printf '%s' "$zone_json" | jq -r '.result[0].id // empty')"
    [[ -n "$zone_id" ]] || fail "Zone not found or API token lacks access: ${CF_ZONE_NAME}"
  fi

  records_json="$(cf_api GET "/zones/${zone_id}/dns_records?type=A&name=${record_name}&per_page=1")"
  record_count="$(printf '%s' "$records_json" | jq -r '.result_info.count // 0')"

  if [[ "$record_count" == "0" ]]; then
    local create_payload
    create_payload="$(jq -cn \
      --arg type "A" \
      --arg name "$record_name" \
      --arg content "$current_ip" \
      --argjson ttl "$CF_TTL" \
      --argjson proxied "$( [[ "$CF_PROXIED" == "true" ]] && echo true || echo false )" \
      '{type:$type, name:$name, content:$content, ttl:$ttl, proxied:$proxied}')"
    cf_api POST "/zones/${zone_id}/dns_records" "$create_payload" >/dev/null
    log INFO "Created A record ${record_name} -> ${current_ip}"
    exit 0
  fi

  record_id="$(printf '%s' "$records_json" | jq -r '.result[0].id')"
  record_ip="$(printf '%s' "$records_json" | jq -r '.result[0].content')"

  if [[ "$record_ip" == "$current_ip" ]]; then
    log INFO "No change for ${record_name}; already ${current_ip}"
    exit 0
  fi

  local update_payload
  update_payload="$(jq -cn \
    --arg type "A" \
    --arg name "$record_name" \
    --arg content "$current_ip" \
    --argjson ttl "$CF_TTL" \
    --argjson proxied "$( [[ "$CF_PROXIED" == "true" ]] && echo true || echo false )" \
    '{type:$type, name:$name, content:$content, ttl:$ttl, proxied:$proxied}')"

  cf_api PUT "/zones/${zone_id}/dns_records/${record_id}" "$update_payload" >/dev/null
  log INFO "Updated A record ${record_name}: ${record_ip} -> ${current_ip}"
}

main "$@"
