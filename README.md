<p align="center">
  <img src="https://raw.githubusercontent.com/DiyRex/outline-docs-action/main/.github/outline.svg" width="80" alt="Outline" />
</p>

<h1 align="center">outline-docs-action</h1>

<p align="center">
  <strong>GitHub Action to create, update, and share documents in Outline wiki via CI/CD pipelines</strong>
</p>

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `outline_url` | **yes** | — | Outline instance URL |
| `api_key` | **yes** | — | Outline API key |
| `action` | **yes** | `create` | `create`, `update`, `find`, `create_collection`, `delete_collection` |
| `collection_id` | no | — | Collection ID (required for `create`, `delete_collection`) |
| `document_id` | no | — | Document ID (required for `update`) |
| `title` | no | — | Document title or collection name |
| `text` | no | — | Markdown content (supports multiline) |
| `file_path` | no | — | Path to markdown file (alternative to `text`) |
| `publish` | no | `true` | Publish immediately or save as draft |
| `share` | no | `false` | Create a public share link |
| `description` | no | — | Collection description (for `create_collection`) |
| `color` | no | — | Collection color hex (for `create_collection`) |

## Outputs

| Output | Description |
|--------|-------------|
| `document_id` | ID of the created/updated/found document |
| `document_url` | URL to the document in Outline |
| `share_url` | Public share URL (only when `share: true`) |
| `collection_id` | ID of the created collection (for `create_collection`) |

---

## Usage

### Create a document

```yaml
- uses: DiyRex/outline-docs-action@v2
  with:
    outline_url: ${{ secrets.OUTLINE_URL }}
    api_key: ${{ secrets.OUTLINE_API_KEY }}
    action: create
    collection_id: 'your-collection-id'
    title: 'Deploy Report'
    text: |
      ## Deployment Summary

      | Service | Status |
      |---------|--------|
      | API     | Healthy |
      | Web     | Healthy |

      Deployed by **${{ github.actor }}** via GitHub Actions.
```

### Create from a markdown file

```yaml
- uses: DiyRex/outline-docs-action@v2
  with:
    outline_url: ${{ secrets.OUTLINE_URL }}
    api_key: ${{ secrets.OUTLINE_API_KEY }}
    action: create
    collection_id: 'your-collection-id'
    title: 'Release Notes ${{ github.ref_name }}'
    file_path: 'CHANGELOG.md'
    share: true
```

### Update an existing document

```yaml
- uses: DiyRex/outline-docs-action@v2
  with:
    outline_url: ${{ secrets.OUTLINE_URL }}
    api_key: ${{ secrets.OUTLINE_API_KEY }}
    action: update
    document_id: 'your-document-id'
    text: 'Updated content here'
```

### Find a document by title

```yaml
- uses: DiyRex/outline-docs-action@v2
  id: find
  with:
    outline_url: ${{ secrets.OUTLINE_URL }}
    api_key: ${{ secrets.OUTLINE_API_KEY }}
    action: find
    title: 'Deploy Report'

- run: echo "Found: ${{ steps.find.outputs.document_url }}"
```

### Create a collection

```yaml
- uses: DiyRex/outline-docs-action@v2
  id: collection
  with:
    outline_url: ${{ secrets.OUTLINE_URL }}
    api_key: ${{ secrets.OUTLINE_API_KEY }}
    action: create_collection
    title: 'Release Notes'
    description: 'Auto-generated release documentation'
    color: '#0366D6'

- run: echo "Collection: ${{ steps.collection.outputs.collection_id }}"
```

### Delete a collection

```yaml
- uses: DiyRex/outline-docs-action@v2
  with:
    outline_url: ${{ secrets.OUTLINE_URL }}
    api_key: ${{ secrets.OUTLINE_API_KEY }}
    action: delete_collection
    collection_id: 'your-collection-id'
```

### Create + share + post link as PR comment

```yaml
- uses: DiyRex/outline-docs-action@v2
  id: outline
  with:
    outline_url: ${{ secrets.OUTLINE_URL }}
    api_key: ${{ secrets.OUTLINE_API_KEY }}
    action: create
    collection_id: 'your-collection-id'
    title: 'PR #${{ github.event.pull_request.number }} Review Notes'
    file_path: 'docs/review.md'
    share: true

- uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: `Wiki doc created: ${{ steps.outline.outputs.share_url }}`
      })
```

---

## Secrets Setup

1. In your Outline instance, go to **Settings > API**
2. Create a new API key
3. Add these secrets to your GitHub repo (**Settings > Secrets and variables > Actions**):
   - `OUTLINE_URL` — your Outline instance URL (e.g., `https://wiki.example.com`)
   - `OUTLINE_API_KEY` — the API key from step 2

---

## Requirements

- `jq` (pre-installed on GitHub-hosted runners)
- `python3` (pre-installed on GitHub-hosted runners)
- `curl` (pre-installed on GitHub-hosted runners)

---

## License

MIT
