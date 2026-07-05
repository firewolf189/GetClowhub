---
name: tax-exemption-ai-review
description: >-
  Review FridayParts tax exemption certificate applications with AI/OCR assistance.
  Use when asked to fetch pending tax exemption applications, inspect exemption certificate
  files, compare certificate fields against submitted customer data, decide whether the
  audit status should be approved or rejected, compute expiration dates, call the external
  audit API, or summarize approved and rejected review results for human follow-up.
---

# Tax Exemption AI Review

## Goal

Review pending tax exemption applications quickly and conservatively. Use only the Friday external pending and audit APIs. Write every reviewed item back through the audit API with `status=approved` or `status=rejected`.

## Required References

- Read `references/api.md` before making backend requests.
- Read `references/review-rules.md` before deciding approval or expiration.
- Use `scripts/tax_exemption_review.py` for repeatable API calls, downloads, expiry calculation, and review JSON scaffolding.

## Credentials

- Treat the backend API key as the `X-API-Key` header for the Friday external tax exemption APIs.
- The helper script uses the Friday production backend by default: `https://oms.fridayparts.com`.
- The helper script includes the Friday production backend key as its default key.
- Runtime overrides still take precedence: pass `--api-key` or set `TAX_EXEMPTION_API_KEY` when a different backend key is required.
- Do not store AI/OCR provider keys in this skill or in generated review artifacts.
- AI/OCR provider keys are separate from the backend `X-API-Key`. Do not put AI service credentials in `references/api.md`.

## Fast Workflow

1. Fetch pending applications.
   - Use the production backend by default: `https://oms.fridayparts.com`.
   - Fetch pending applications with `GET /api/external/tax/exemption/pending`.
   - Use `pending --all` for normal review runs so every pending page is fetched before deciding there is no work.
   - The API supports `page` and `size`; keep fetching pages/batches until the pending count is exhausted or the user-specified scope is complete.
   - Process only items with `status=pending`.
   - If `cert_url` is missing or contains unresolved placeholders such as `{{file_url}}` or `{{file_path}}`, write `status=rejected` with a concise technical reason because the standard three refusal reasons do not cover missing files.
   - If a test `cert_url` under `https://media.test.jeeda.net/` returns `403 AccessDenied`, retry the same object key through `https://jeeda-media.s3.us-west-2.amazonaws.com/` before deciding the file is inaccessible.
   - Even if the host app can upload or display images in chunks, review pending records in explicit model batches of 5-10 items. Finish one batch with per-item evidence before starting the next batch.

2. Extract all available submitted and certificate evidence before deciding.
   - Read submitted `organization_name`, `state_code` or `state_name`, `state_tax_number`, `exemption_num`, and `created_at`.
   - Extract certificate state, issuing authority, document title, purchaser/licensee name, tax/exempt/permit/account/license ID, effective date, issue/signature date, explicit expiration date, invalid-status language, and text proving exemption or resale eligibility.
   - If a field is missing from its normal position but appears elsewhere in the certificate, body text, permit text, account table, signature area, address, state agency name, or supplemental page, use that evidence.
   - If the certificate URL is absent or inaccessible, write `status=rejected` with a specific technical reason.

3. Download and extract certificate content.
   - Prefer deterministic extraction first: PDF text extraction for PDFs, OCR/vision for images or scanned PDFs.
   - For weak models, do not ask the model to inspect raw images unaided. Use a stronger vision/OCR provider, local OCR tool, or user-provided extracted text, then continue from structured fields.
   - If OCR confidence is low or key fields are unreadable, write `status=rejected` with `the image of the certificate is unclear and cannot be verified.`

4. Compare certificate fields against submitted data.
   - Compare state first; this is the fastest rejection-to-manual signal.
   - Compare organization/customer name with normalization.
   - Compare Tax ID / Exempt ID against `state_tax_number` and `exemption_num`.
   - Determine whether the certificate is valid, revoked, expired, incomplete, or ambiguous.
   - Extract explicit expiration date and issue/signature date when present.

5. Decide outcome in this order.
   - First compare the submitted state with the certificate, license, permit, or proof document state. If the states clearly differ, write `status=rejected` with `the document provided is not a valid tax exemption certificate.` Do not continue to name, ID, expiration, or document-type checks after a clear state mismatch.
   - If the state matches, determine whether the document is currently valid. If it is explicitly expired, write `status=rejected` with `the submitted tax exemption certificate is expired.` If it is revoked, void, sample-only, incomplete, or clearly unfinished, write `status=rejected` with `the document provided is not a valid tax exemption certificate.`
   - If the document is valid, decide whether its content proves tax exemption, resale, agricultural exemption, government exemption, or a similar tax-exempt purchasing qualification. Do not require the title to say `resale certificate` or `exemption certificate`. A `Sales Tax License`, `Seller's Permit`, `Sales and Use Tax Permit`, `Agricultural Permit`, or similar document may be accepted when the body text clearly supports resale or tax-exempt purchases, such as `resale`, `tax exempt purchase`, `exempt purchase`, `purchase items tax exempt`, or `for purpose of resale`.
   - If the document content proves the qualification, compare the certificate name with submitted `organization_name`. Accept clear name variants and explain any agricultural or owner/operator relationship used for matching. Reject clear different-entity mismatches.
   - If the name matches, compare the relevant Tax ID, Exempt ID, Permit Number, Account Number, Registration Number, or License Number against `state_tax_number` or `exemption_num`, ignoring spaces, hyphens, and case. Prefer IDs related to the exemption/resale/permit qualification over addresses, phone numbers, or unrelated numbers.
   - If state, validity, qualification content, name, and ID pass, compute `expired_at` and approve only when the computed cutoff is not already expired.
   - `rejected`: for every clear mismatch, missing required evidence after full extraction, weak OCR, unreadable file, ambiguous date that cannot be resolved, expired certificate, or unsupported proof document.
   - Treat every `rejected` item as requiring human follow-up in the run summary.
   - Do not treat a transport check, API smoke test, or URL reachability check as a completed audit.

6. Write back results.
   - For approved cases, call `PUT /api/external/tax/exemption/{id}/audit` with `status=approved` and `expired_at`.
   - For approved cases, `expired_at` is the tax exemption certificate's effective cutoff, not the audit time. Compute it from the expiration rules as a US Eastern business date and return it as `YYYY-MM-DD 23:59:59`.
   - For rejected cases, call the same audit API with `status=rejected`, `expired_at`, and `refuse_reason`.
   - For rejected cases, set `expired_at` to the current local datetime in `YYYY-MM-DD HH:mm:ss` format. This field is operationally required by the backend validator even though business meaning comes from the rejected status and refusal reason.
   - Never use dummy epoch values such as `1970-01-01 00:00:00`.
   - Keep `refuse_reason` to 500 characters or fewer.
   - Dry-run or print the writeback payload before any batch write. For real audits, inspect files and produce per-item evidence before writing results.
   - Use only the two provided backend APIs; do not invent or call an `ai-review` endpoint.

7. Summarize the run.
   - Report processed count, approved count, rejected count, and customer IDs/reasons requiring manual review.
   - In user-facing review output, use `customer_id` as the primary and only item identifier.
   - Do not include `exemption_id` in the final review summary. Use `exemption_id` only internally for the audit API path.
   - If no pending records were fetched, state that no audit review or writeback was performed. Do not present an all-zero summary as proof that any image was reviewed.

## Weak-Model Guardrails

Use this structure even if the active model has poor OCR:

1. Never rely on freeform visual impressions when approving.
2. Require extracted fields in this shape before approval:

```json
{
  "certificate_state": "",
  "certificate_organization_name": "",
  "certificate_tax_id_or_exempt_id": "",
  "certificate_validity_status": "valid|expired|revoked|unknown",
  "explicit_expiration_date": "",
  "issue_or_signature_date": "",
  "effective_date": "",
  "document_type_evidence": "",
  "qualification_text_evidence": "",
  "readability": "readable|unclear|unreadable",
  "evidence": []
}
```

3. If a required field is missing from its expected location, search the full document before rejecting. Use valid evidence from body text, agency names, account tables, permit text, addresses, signature areas, and supplemental pages.
4. If the active model cannot produce this structure from the document, use OCR/vision tooling or ask for extracted text. If still uncertain because the document cannot be read, write `status=rejected` with the unclear-image standard reason.
5. Do not approve unrelated photos, landscape images, screenshots without certificate text, blank files, receipts, invoices, generic business documents, or unfinished templates.
6. Use exact values and short evidence snippets; do not invent missing dates or IDs.
7. Fail closed: unresolved uncertainty after full extraction means human review, not approval.

## API Helper

Examples:

```bash
python3 ~/.codex/skills/tax-exemption-ai-review/scripts/tax_exemption_review.py \
  pending --all --size 100

python3 ~/.codex/skills/tax-exemption-ai-review/scripts/tax_exemption_review.py \
  download --url "<cert_url from pending response>" --out "/tmp/tax-exemption-<exemption_id>"

python3 ~/.codex/skills/tax-exemption-ai-review/scripts/tax_exemption_review.py \
  draft --item-json /tmp/item.json --ocr-text /tmp/ocr.txt

python3 ~/.codex/skills/tax-exemption-ai-review/scripts/tax_exemption_review.py \
  expiry --explicit-expiration "2026-12-31" --submitted-at "2026-06-10 12:00:00"

python3 ~/.codex/skills/tax-exemption-ai-review/scripts/tax_exemption_review.py \
  audit --id 123 \
  --status approved --expired-at "2026-12-31 23:59:59" --dry-run

python3 ~/.codex/skills/tax-exemption-ai-review/scripts/tax_exemption_review.py \
  audit --id 123 \
  --status rejected --refuse-reason "the document provided is not a valid tax exemption certificate." \
  --dry-run
```

The `expiry` helper returns the certificate cutoff date in US Eastern business time.
For example, `2026-06-16` returns `2026-06-16 23:59:59`.
When `--issue-date` and `--submitted-at` are both provided and issue date plus one year is already past, the helper falls back to December 31 of the submitted year.
`--effective-date` follows the same rule as `--issue-date` when no explicit expiration date exists.

## Run summary

After processing, output only:

```json
{
  "batch_count": 0,
  "processed_count": 0,
  "approved_count": 0,
  "rejected_count": 0,
  "approved_items": [
    {
      "customer_id": 0,
      "expired_at": "",
      "reason": ""
    }
  ],
  "rejected_items": [
    {
      "customer_id": 0,
      "refuse_reason": "",
      "detail": ""
    }
  ]
}
```
