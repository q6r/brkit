# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The playground moved to the bundled Aurora 2.0 UI kit: an IDE-style layout (a navigation rail, a top bar with
  breadcrumbs, search, the API state and the PT/EN switch, one pill per tool, a status bar) in a near-black palette
  with silver text and one indigo accent (Prism Classic), with Prism Daylight as the light theme. Flat cards on one
  ground, a composer for the value of each tool, no gradients, glass or animated background. Every tool, text and API
  call is unchanged; the tool is now part of the URL (`#cnpj`, `#pix`, ...) and works with the back button.
- Without an API (the page opened from disk, or from a static server) the playground loads and says that the API is
  unavailable instead of failing call by call.

## [0.1.0] - 2026-11-10

First release.

### Added

- Library with zero runtime dependencies (Ruby 3.1+): CPF, CNPJ (classic numeric and the alphanumeric format),
  PIS/PASEP/NIS/NIT, Luhn-valid test cards with brand detection, Brazilian phone numbers (ANATEL area codes,
  E.164 normalisation), CEP with state ranges, licence plates (legacy and Mercosul, with conversion) and
  seeded fictitious people. Every validator returns an immutable `Result`; every generator takes `seed:` or `rng:`.
- PIX: BR Code builder, decoder (TLV tree, structure checks against the BR Code manual, CRC verdict) and
  CRC-16/CCITT-FALSE with a per-byte trace.
- "Show your work": validators take `explain: true` and return the checksum steps (digits, weights, products,
  sum, remainder; the Luhn doubling; the CRC register after every byte).
- Command line `brkit`: `validate`, `generate`, `format`, `plate convert`, `pix payload`, `pix decode`,
  `fake person`, `serve`, `completion` (bash and PowerShell); JSON output, stdin input, colour that honours `NO_COLOR`
  and documented exit codes.
- Rack JSON API (`config.ru`, no gem needed at runtime): validate and generate endpoints for every document,
  plate conversion, PIX payload and decode, fake people, `GET /healthz` and a generated OpenAPI 3.1 document.
  Problem details (RFC 9457) for errors, per-client token-bucket rate limiting of `/api/` (the playground's own files
  are not counted), opt-in CORS, request ids, a request body limit and security headers.
- Interactive playground served from `public/`: one tab per document, generate and validate as you type, the
  checksum animated step by step, a PIX builder and decoder with a TLV tree, Brazilian Portuguese and English,
  dark and light themes, and a command palette.
- Documentation: architecture, algorithms, API reference and problem types; runnable examples.

[Unreleased]: https://github.com/q6r/brkit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/q6r/brkit/releases/tag/v0.1.0
