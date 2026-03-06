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
  create_collection)
    if [[ -z "${TITLE:-}" ]]; then
      echo "::error::title is required for create_collection action (used as collection name)"
      exit 1
    fi
    ;;
  delete_collection)
    if [[ -z "${COLLECTION_ID:-}" ]]; then
      echo "::error::collection_id is required for delete_collection action"
      exit 1
    fi
    ;;
  *)
    echo "::error::Invalid action: ${ACTION}. Must be create, update, find, create_collection, or delete_collection"
    exit 1
    ;;
esac

# ─── Execute action ───────────────────────────────────────────────────────────

DOC_ID=""
DOC_URL=""
COL_ID=""

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

  create_collection)
    ESCAPED_DESC=$(echo -n "${DESCRIPTION:-}" | json_escape)
    PAYLOAD="{\"name\":${ESCAPED_TITLE}"
    if [[ -n "${DESCRIPTION:-}" ]]; then
      PAYLOAD="${PAYLOAD},\"description\":${ESCAPED_DESC}"
    fi
    if [[ -n "${COLOR:-}" ]]; then
      PAYLOAD="${PAYLOAD},\"color\":\"${COLOR}\""
    fi
    PAYLOAD="${PAYLOAD}}"

    echo "::group::Creating collection"
    RESPONSE=$(api_call "collections.create" "$PAYLOAD")
    COL_ID=$(echo "$RESPONSE" | jq -r '.data.id')
    echo "Collection created: ${COL_ID}"
    echo "::endgroup::"
    ;;

  delete_collection)
    echo "::group::Deleting collection"
    api_call "collections.delete" "{\"id\":\"${COLLECTION_ID}\"}" > /dev/null
    echo "Collection deleted: ${COLLECTION_ID}"
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
echo "collection_id=${COL_ID}" >> "$GITHUB_OUTPUT"

# ─── Step summary ─────────────────────────────────────────────────────────────

{
  echo "### Outline Docs Action"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| Action | \`${ACTION}\` |"
  if [[ -n "$COL_ID" ]]; then
    echo "| Collection ID | \`${COL_ID}\` |"
  fi
  if [[ -n "$DOC_ID" ]]; then
    echo "| Document ID | \`${DOC_ID}\` |"
    echo "| Document URL | [Open in Outline](${DOC_URL}) |"
  fi
  if [[ -n "$SHARE_URL" ]]; then
    echo "| Share URL | [Public Link](${SHARE_URL}) |"
  fi
} >> "$GITHUB_STEP_SUMMARY"
