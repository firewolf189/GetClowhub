# Tax Exemption Review Rules

## Decision Policy

Extract all available evidence first, then decide in order. Do not reject only because a field is missing from its usual location if the same evidence appears elsewhere in the certificate, license, permit, body text, address, account table, issuing agency, signature area, or supplemental page.

Approve only when this ordered review reaches the end:

1. State matches.
   - Compare submitted `state_code` or `state_name` with the certificate, license, permit, or proof document state.
   - If the document does not directly state a two-letter state, use state government names, document title, issuing authority, address, or state code as state evidence.
   - If the states clearly differ, return `status=rejected` with `the document provided is not a valid tax exemption certificate.` Stop the automatic approval review.

2. Document is currently valid.
   - If the document explicitly expired, return `status=rejected` with `the submitted tax exemption certificate is expired.`
   - If the document is revoked, void, sample-only, incomplete, clearly unfinished, or not applicable, return `status=rejected` with `the document provided is not a valid tax exemption certificate.`

3. Document content proves tax-exempt or resale purchasing qualification.
   - Do not require the title to say `resale certificate` or `exemption certificate`.
   - Accept documents such as `Sales Tax License`, `Seller's Permit`, `Sales and Use Tax Permit`, `Agricultural Permit`, or similar proof when the body text clearly supports resale or tax-exempt purchases.
   - Supporting text includes `resale`, `tax exempt purchase`, `exempt purchase`, `purchase items tax exempt`, `for purpose of resale`, agricultural exemption, government exemption, or equivalent wording.
   - Reject ordinary business licenses, receipts, invoices, unrelated photos, landscape images, blank files, screenshots without certificate text, generic business documents, and unfinished templates that cannot prove exemption or resale qualification.

4. Name matches.
   - Certificate organization, purchaser, customer, licensee, owner, or permit holder name must reasonably match submitted `organization_name`.
   - Normalize case, punctuation, legal suffixes, and repeated spaces. Accept clear variants such as `Inc` vs `Incorporated` and `LLC` vs `L.L.C.`.
   - For agricultural or owner/operator documents, accept a personal name, farm name, company name, or operating entity relationship only when the relationship is clear enough to explain in the audit reason.
   - Reject when the certificate and submitted application appear to be different entities.

5. ID matches.
   - Compare relevant certificate IDs with submitted `state_tax_number` or `exemption_num`.
   - Accept Tax ID, Exempt ID, Permit Number, Account Number, Registration Number, License Number, or equivalent state-issued identifier.
   - Ignore spaces, hyphens, and case for comparison.
   - Prefer IDs related to the exemption, resale, permit, account, or license qualification over addresses, phone numbers, and unrelated numbers.
   - Reject when the relevant ID clearly differs or cannot be found after full extraction.

6. Expiration can be computed and is not already expired.
   - Compute `expired_at` by the rules below.
   - If the final computed cutoff is already in the past, return `status=rejected` with `the submitted tax exemption certificate is expired.`

Return `status=approved` only if all six ordered checks pass.

## Speed Rules

1. State mismatch is an early stop.
   - If certificate state is confidently extracted and differs from submitted state, stop and return `status=rejected`.
   - If certificate state cannot be extracted, continue only if other OCR evidence is strong enough; otherwise return `status=rejected`.

2. Avoid full document reasoning until needed.
   - Use metadata and submitted state first.
   - Use deterministic PDF text extraction before image OCR.
   - OCR only certificate pages or images that contain text.

3. Batch cautiously.
   - Fetch all pending pages first when the user asks to review current pending applications.
   - Then process records in model batches of 5-10 items, even if the host application already supports chunked image upload.
   - Never put more than 10 pending records into a single model reasoning batch.
   - Approve one item at a time after producing evidence.
   - Do not bulk approve without per-item evidence.
   - Count every reviewed item as `approved` or `rejected`.

## Field Normalization

- State: compare both two-letter code and full name when available. Normalize case, spaces, and punctuation.
- Organization name: normalize case, punctuation, legal suffixes, and repeated spaces. Accept clear variants such as `Inc` vs `Incorporated`; reject when the entity appears different.
- Tax ID / Exempt ID: ignore spaces, hyphens, and casing for comparison. Do not approve if all IDs are missing.
- Dates: parse common US date formats. If only a year/month is present, return `status=rejected` unless the certificate explicitly states a policy that resolves the date.

## Expiration Rules

Return `expired_at` as `YYYY-MM-DD 23:59:59` in US Eastern business time unless the certificate provides a more precise end time. This value is the certificate effective cutoff date, not the audit time.

1. Explicit expiration date exists:
   - Use the certificate expiration date.

2. No explicit expiration date, but issue/signature date exists:
   - Use issue/signature date plus one year.
   - If that computed date is already in the past and submitted `created_at` is available, use December 31 of the submitted year.

3. No explicit expiration date, but effective date exists:
   - Use effective date plus one year.
   - If that computed date is already in the past and submitted `created_at` is available, use December 31 of the submitted year.

4. Document states `valid until revoked` or `valid until cancelled` without an explicit expiration date:
   - Use issue/signature/effective date plus one year when available.
   - If that computed date is already in the past and submitted `created_at` is available, use December 31 of the submitted year.

5. No explicit expiration date and no issue/signature/effective date:
   - Use submitted `created_at` plus one year.

The fallback to December 31 of the submitted year applies only when the document has no explicit expiration date. Never override an explicit expiration date with the submitted-year fallback.
If the final computed expiration date is already in the past, return `status=rejected`.

## Refuse Reason Mapping

Use one of the three standard `refuse_reason` strings whenever possible:

1. Expired certificate:
   - Use `the submitted tax exemption certificate is expired.`
   - Applies when the certificate explicitly expired or the computed expiration date is already in the past.

2. Invalid tax exemption certificate:
   - Use `the document provided is not a valid tax exemption certificate.`
   - Applies when the document is not a tax exemption certificate, is an unrelated photo/landscape/screenshot without certificate text, state mismatches, organization mismatches, Tax ID / Exempt ID mismatches, required certificate fields are missing, the certificate is revoked/void/sample-only, or the document cannot prove exemption validity.

3. Unclear certificate image:
   - Use `the image of the certificate is unclear and cannot be verified.`
   - Applies when the image/PDF scan is blurry, OCR confidence is low, or key fields cannot be read.

Use a specific non-standard reason only for technical cases not covered by the three standard reasons, such as a missing or inaccessible certificate file. For example, `certificate file is missing or inaccessible.`

Keep detailed internal analysis in the run summary, not in `refuse_reason`.

## Required Summary

After processing a batch, report:

- Total pending records processed.
- Approved count.
- Rejected count.
- Skipped/error count.
- Approved customer IDs, approved expiration dates, and concise approval reasons.
- Rejected customer IDs, standard refuse reasons, and concise internal details requiring human follow-up.
- Use `customer_id` as the only user-facing item identifier in the final summary.
- Do not include `exemption_id` in the final summary. Use `exemption_id` only internally when calling the audit API.
