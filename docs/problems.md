# Problem types

Every error from the HTTP API is an [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem document with the
media type `application/problem+json`. The `type` member is a URL that ends in one of the slugs below, so a client
can branch on it without parsing prose.

```json
{
  "type": "https://github.com/q6r/brkit/blob/main/docs/problems.md#invalid-parameter",
  "title": "Invalid parameter",
  "status": 400,
  "detail": "count must be between 1 and 100",
  "request_id": "70c4b335-914d-41ec-a9b2-e634eafc7b72",
  "errors": [
    { "code": "out_of_range", "message": "count must be between 1 and 100", "field": "count" }
  ]
}
```

- `request_id` repeats the `x-request-id` response header. Quote it when reporting a bug.
- `errors` is present for field-level problems; each entry has a stable `code`, a human `message` and the `field`.
- `detail` is a sentence for people and may change; `type`, `status` and the error `code`s are the contract.

An invalid *value* is not a problem: `GET /api/v1/cpf/validate?cpf=529.982.247-26` answers `200` with
`"valid": false` and the reasons in `errors`. Problems are for requests the API cannot process at all.

## bad-request

**400.** The request itself is malformed: a malformed HTTP method or `Content-Length`, a path or query string that is
not percent-encoded ASCII, an invalid percent escape, encoded path separators (`%2f`, `%5c`), control characters,
text that is not valid UTF-8 (in the URL or the body), an empty parameter name, a parameter given more than once,
or more than 32 query parameters.

## invalid-parameter

**400.** A query parameter is missing, unknown or has a bad value. `errors[].code` is one of `missing`,
`unknown_parameter`, `invalid_integer`, `invalid_boolean`, `out_of_range`, `not_allowed` (not in the enumeration)
or `too_long`. Every problem found is listed, not just the first.

## invalid-json

**400.** The body of a `POST` is empty, is not valid JSON, is not a JSON object, uses `NaN` or `Infinity`, or
nests deeper than 8 levels.

## not-found

**404.** No such endpoint (paths under `/api/` never fall through to static files) or no such file.

## method-not-allowed

**405.** The path exists but not for this verb. The `allow` response header lists the supported methods.

## not-acceptable

**406.** The `Accept` header excludes `application/json`. The API only produces JSON.

## payload-too-large

**413.** The request body is larger than the limit (16 384 bytes by default, `BRKIT_MAX_BODY_BYTES`). A declared
`Content-Length` above the limit is refused before anything is read, and chunked bodies are cut off while reading.

## uri-too-long

**414.** The path is longer than 2 048 bytes or the query string is longer than 4 096 bytes.

## unsupported-media-type

**415.** A `POST` must send `Content-Type: application/json` in UTF-8.

## validation-error

**422.** The JSON body parsed but its fields are wrong: a missing required field, an unknown field, a value of
the wrong type or length, or a library-level refusal such as a PIX key that is not a CPF, CNPJ, phone, e-mail or
random key. `errors[]` lists every field, with the same codes as `invalid-parameter` plus `invalid_type` and
`unknown_field`.

## rate-limited

**429.** The client has used its token bucket (`BRKIT_RATE_LIMIT` requests per minute sustained, bursts of
`BRKIT_RATE_BURST`). `retry-after` says how many seconds to wait. The `ratelimit-limit`, `ratelimit-remaining`
and `ratelimit-reset` headers accompany every response under `/api/`. Static files (the playground) and `/healthz`
are never limited.

## internal-error

**500.** A bug. The response never contains the exception message or a backtrace; both go to the server log keyed
by the request id.
