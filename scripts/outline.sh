#!/usr/bin/env bash
set -euo pipefail

# ─── Helpers ───────────────────────────────────────────────────────────────────

OUTLINE_URL="${OUTLINE_URL%/}"

api_call() {
  local endpoint="$1"
  local payload="$2"

  local response
  response=$(curl -sf -X POST "${OUTLINE_URL}/api/${endpoint}" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>&1) || {
    echo "::error::API call to ${endpoint} failed"
    echo "::error::Response: ${response}"
    exit 1
  }

  local ok
  ok=$(echo "$response" | jq -r '.ok // false')
  if [[ "$ok" != "true" ]]; then
    local msg
    msg=$(echo "$response" | jq -r '.message // .error // "Unknown error"')
    echo "::error::API error from ${endpoint}: ${msg}"
    exit 1
  fi

  echo "$response"
}

json_escape() {
  python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
}

# ─── Read content ──────────────────────────────────────────────────────────────

CONTENT=""
if [[ -n "${FILE_PATH:-}" ]]; then
  if [[ ! -f "$FILE_PATH" ]]; then
    echo "::error::File not found: ${FILE_PATH}"
    exit 1
  fi
  CONTENT=$(cat "$FILE_PATH")
elif [[ -n "${TEXT:-}" ]]; then
  CONTENT="$TEXT"
fi

ESCAPED_CONTENT=$(echo "$CONTENT" | json_escape)
ESCAPED_TITLE=$(echo -n "${TITLE:-}" | json_escape)

# ─── Validate inputs ──────────────────────────────────────────────────────────

case "${ACTION}" in
  create)
    if [[ -z "${COLLECTION_ID:-}" ]]; then
      echo "::error::collection_id is required for create action"
      exit 1
    fi
    if [[ -z "${TITLE:-}" ]]; then
      echo "::error::title is required for create action"
      exit 1
    fi
    ;;
  update)
    if [[ -z "${DOCUMENT_ID:-}" ]]; then
      echo "::error::document_id is required for update action"
      exit 1
    fi
    ;;
  find)
    if [[ -z "${TITLE:-}" ]]; then
      echo "::error::title is required for find action (used as search query)"
      exit 1
    fi
    ;;
  *)
    echo "::error::Invalid action: ${ACTION}. Must be create, update, or find"
    exit 1
    ;;
esac

# ─── Execute action ───────────────────────────────────────────────────────────

DOC_ID=""
DOC_URL=""

case "${ACTION}" in
  create)
    PUBLISH_BOOL="true"
    if [[ "${PUBLISH:-true}" == "false" ]]; then
      PUBLISH_BOOL="false"
    fi

    PAYLOAD="{\"title\":${ESCAPED_TITLE},\"collectionId\":\"${COLLECTION_ID}\",\"publish\":${PUBLISH_BOOL}"
    if [[ -n "$CONTENT" ]]; then
      PAYLOAD="${PAYLOAD},\"text\":${ESCAPED_CONTENT}"
    fi
    PAYLOAD="${PAYLOAD}}"

    echo "::group::Creating document"
    RESPONSE=$(api_call "documents.create" "$PAYLOAD")
    DOC_ID=$(echo "$RESPONSE" | jq -r '.data.id')
    DOC_URL="${OUTLINE_URL}$(echo "$RESPONSE" | jq -r '.data.url')"
    echo "Document created: ${DOC_ID}"
    echo "URL: ${DOC_URL}"
    echo "::endgroup::"
    ;;

  update)
    PAYLOAD="{\"id\":\"${DOCUMENT_ID}\""
    if [[ -n "${TITLE:-}" ]]; then
      PAYLOAD="${PAYLOAD},\"title\":${ESCAPED_TITLE}"
    fi
    if [[ -n "$CONTENT" ]]; then
      PAYLOAD="${PAYLOAD},\"text\":${ESCAPED_CONTENT}"
    fi
    PAYLOAD="${PAYLOAD}}"

    echo "::group::Updating document"
    RESPONSE=$(api_call "documents.update" "$PAYLOAD")
    DOC_ID=$(echo "$RESPONSE" | jq -r '.data.id')
    DOC_URL="${OUTLINE_URL}$(echo "$RESPONSE" | jq -r '.data.url')"
    echo "Document updated: ${DOC_ID}"
    echo "URL: ${DOC_URL}"
    echo "::endgroup::"
    ;;

  find)
    PAYLOAD="{\"query\":${ESCAPED_TITLE},\"limit\":1}"

    echo "::group::Searching for document"
    RESPONSE=$(api_call "documents.search" "$PAYLOAD")
    DOC_ID=$(echo "$RESPONSE" | jq -r '.data[0].document.id // empty')
    if [[ -z "$DOC_ID" ]]; then
      echo "::warning::No document found matching: ${TITLE}"
    else
      DOC_URL="${OUTLINE_URL}$(echo "$RESPONSE" | jq -r '.data[0].document.url')"
      echo "Document found: ${DOC_ID}"
      echo "URL: ${DOC_URL}"
    fi
    echo "::endgroup::"
    ;;
esac

# ─── Share link ────────────────────────────────────────────────────────────────

SHARE_URL=""
if [[ "${SHARE:-false}" == "true" && -n "$DOC_ID" ]]; then
  echo "::group::Creating share link"
  SHARE_RESPONSE=$(api_call "shares.create" "{\"documentId\":\"${DOC_ID}\"}")
  SHARE_URL=$(echo "$SHARE_RESPONSE" | jq -r '.data.url // empty')
  if [[ -z "$SHARE_URL" ]]; then
    # Some Outline versions return the share differently
    SHARE_ID=$(echo "$SHARE_RESPONSE" | jq -r '.data.id // empty')
    if [[ -n "$SHARE_ID" ]]; then
      SHARE_URL="${OUTLINE_URL}/share/${SHARE_ID}"
    fi
  fi
  echo "Share URL: ${SHARE_URL}"
  echo "::endgroup::"
fi

# ─── Set outputs ───────────────────────────────────────────────────────────────

echo "document_id=${DOC_ID}" >> "$GITHUB_OUTPUT"
echo "document_url=${DOC_URL}" >> "$GITHUB_OUTPUT"
echo "share_url=${SHARE_URL}" >> "$GITHUB_OUTPUT"

# ─── Step summary ─────────────────────────────────────────────────────────────

{
  echo "### Outline Docs Action"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| Action | \`${ACTION}\` |"
  if [[ -n "$DOC_ID" ]]; then
    echo "| Document ID | \`${DOC_ID}\` |"
    echo "| Document URL | [Open in Outline](${DOC_URL}) |"
  fi
  if [[ -n "$SHARE_URL" ]]; then
    echo "| Share URL | [Public Link](${SHARE_URL}) |"
  fi
} >> "$GITHUB_STEP_SUMMARY"
