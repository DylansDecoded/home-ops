#!/usr/bin/env bash

export XSEED_HOST=${XSEED_HOST:-cross-seed.default.svc.cluster.local}
export XSEED_PORT=${XSEED_PORT:-80}
export XSEED_API_KEY=${XSEED_API_KEY:-unset}
export XSEED_SEED_SLEEP_INTERVAL=${XSEED_SEED_SLEEP_INTERVAL:-30}

SEARCH_PATH=$1

# Update permissions on the search path
chmod -R 750 "${SEARCH_PATH}"

# Search for cross-seed
response=$(curl \
    --silent \
    --output /dev/null \
    --write-out "%{http_code}" \
    --request POST \
    --data-urlencode "path=${SEARCH_PATH}" \
    --header "X-Api-Key: ${XSEED_API_KEY}" \
    "http://${XSEED_HOST}:${XSEED_PORT}/api/webhook"
)

if [[ "${response}" != "204" ]]; then
    printf "Failed to search cross-seed for '%s'\n" "${SEARCH_PATH}"
    exit 1
fi

printf "Successfully searched cross-seed for '%s'\n" "${SEARCH_PATH}"

sleep "${XSEED_SEED_SLEEP_INTERVAL}"