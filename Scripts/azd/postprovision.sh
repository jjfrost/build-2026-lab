#!/usr/bin/env sh
set -eu

get_azd_value() {
  key="$1"
  value="$(azd env get-value "$key" 2>/dev/null || true)"
  value="$(printf '%s' "$value" | sed 's/^"//; s/"$//')"
  printf '%s' "$value"
}

require_value() {
  key="$1"
  fallback="${2-}"
  value="$(get_azd_value "$key")"
  if [ -z "$value" ]; then
    value="$fallback"
  fi
  if [ -z "$value" ]; then
    echo "Missing required value: $key" >&2
    exit 1
  fi
  printf '%s' "$value"
}

echo "Resolving azd environment values..."
resource_group="$(require_value AZURE_RESOURCE_GROUP "${AZURE_RESOURCE_GROUP-}")"

pg_host="$(require_value AZURE_PG_HOST)"
pg_name="$(require_value AZURE_PG_NAME postgres)"
pg_user="$(require_value AZURE_PG_USER)"
pg_password="$(require_value AZURE_PG_PASSWORD)"
pg_port="$(require_value AZURE_PG_PORT 5432)"
pg_sslmode="$(require_value AZURE_PG_SSLMODE require)"

openai_service_name="$(require_value AZURE_OPENAI_SERVICE_NAME)"
openai_endpoint="$(require_value AZURE_OPENAI_ENDPOINT)"
openai_deployment="$(require_value AZURE_OPENAI_DEPLOYMENT gpt-5)"
embed_deployment="$(require_value AZURE_EMBED_DEPLOYMENT text-embedding-3-small)"
api_version="$(require_value AZURE_API_VERSION 2025-03-01-preview)"

echo "Fetching Azure OpenAI key..."
openai_key="$(az cognitiveservices account keys list --name "$openai_service_name" --resource-group "$resource_group" --query key1 -o tsv)"
if [ -z "$openai_key" ]; then
  echo "Failed to fetch AZURE_OPENAI_KEY from Cognitive Services." >&2
  exit 1
fi

echo "Writing local .env file..."
cat > .env <<EOF
AZURE_OPENAI_ENDPOINT=$openai_endpoint
AZURE_OPENAI_KEY=$openai_key
AZURE_OPENAI_DEPLOYMENT=$openai_deployment
AZURE_EMBED_DEPLOYMENT=$embed_deployment
AZURE_API_VERSION=$api_version

AZURE_PG_HOST=$pg_host
AZURE_PG_NAME=$pg_name
AZURE_PG_USER=$pg_user
AZURE_PG_PASSWORD=$pg_password
AZURE_PG_PORT=$pg_port
AZURE_PG_SSLMODE=$pg_sslmode
EOF

echo "Created/updated .env"
echo "postprovision completed successfully."
