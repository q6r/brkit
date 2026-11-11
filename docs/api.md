# HTTP API

A JSON API over the whole library, written as a plain Rack 3 application (`Brkit::API::App`) with no gem needed at
runtime. The same process also serves the playground from `public/`.

```sh
bundle config set --local with server
bundle install
bundle exec rackup config.ru --host 127.0.0.1 --port 9292    # or: brkit serve
```

Everything below can be tried with `curl`. The machine-readable version of this page is generated from the route
table and always matches what the server accepts: `GET /api/v1/openapi.json` (OpenAPI 3.1).

## Conventions

- Successful responses are `application/json`; errors are [problem documents](problems.md).
- An invalid *value* is a normal answer (`200`, `"valid": false`); a request the API cannot process is a problem.
- Every response carries `x-request-id`. Send your own `X-Request-Id` (8 to 64 letters, digits, `.`, `_`, `-`)
  and it is kept.
- Query parameters are strict: an unknown or repeated parameter is a `400`. Request bodies are strict too: unknown
  fields are a `422`.
- Generators take `count` (1 to 100, default 1) and `seed` (an integer from 0 to 4294967295). The response always
  echoes the seed used, so any result can be reproduced by sending it back.

## Endpoints

| Method | Path | What it does |
|---|---|---|
| GET | `/healthz` | Liveness probe: `{"status":"ok","version":"0.1.0"}`. Never rate limited. |
| GET | `/api/v1/openapi.json` | The OpenAPI 3.1 description of this API |
| GET | `/api/v1/<document>/validate` | Validate one value. Documents: `cpf` (`cpf=`), `cnpj` (`cnpj=`), `pis` (`pis=`), `card` (`number=`), `plate` (`plate=`), `phone` (`phone=`), `cep` (`cep=`) |
| GET | `/api/v1/<document>/generate` | Generate values: `cpf`, `cnpj`, `pis`, `card`, `plate`, `phone`, `cep` |
| GET | `/api/v1/plate/convert` | Legacy plate to Mercosul (`plate=`) |
| POST | `/api/v1/pix/payload` | Build a static PIX BR Code |
| POST | `/api/v1/pix/decode` | Decode a BR Code and check its structure and CRC |
| GET | `/api/v1/fake/person` | Fictitious people |
| GET | `/`, `/*` | The playground (static files from `public/`) |

### Validate

`GET /api/v1/<document>/validate?<param>=<value>` returns a result:

| Member | Meaning |
|---|---|
| `kind` | The document type |
| `input` | The value as received |
| `valid` | `true` when it passed every check |
| `normalized` | Canonical form (digits or characters only); present whenever the shape allows it, even when a checksum fails |
| `formatted` | Display form with the usual mask |
| `errors` | Empty when valid; otherwise `{code, message}` entries (`blank`, `invalid_length`, `invalid_characters`, `repeated_digits`, `checksum`, `luhn`, `invalid_area_code`, ...) |
| `details` | Facts about the value: the CPF's fiscal region and states, the card brand and BIN, the phone's area code and type, ... |

```sh
curl "http://127.0.0.1:9292/api/v1/cpf/validate?cpf=529.982.247-25"
```

```json
{"kind":"cpf","input":"529.982.247-25","valid":true,"normalized":"52998224725","formatted":"529.982.247-25","errors":[],"details":{"region_digit":7,"ufs":["ES","RJ"]}}
```

```sh
curl "http://127.0.0.1:9292/api/v1/cpf/validate?cpf=529.982.247-26"
```

```json
{"kind":"cpf","input":"529.982.247-26","valid":false,"normalized":"52998224726","formatted":"529.982.247-26","errors":[{"code":"checksum","message":"second check digit does not match (expected 5, got 6)"}],"details":{"region_digit":7,"ufs":["ES","RJ"]}}
```

**`explain=true`** (CPF, CNPJ, PIS and card) adds the computation to `details.steps`: one entry per check digit with
the characters, their numeric values, the weights, the products, the sum, the remainder and the digit it implies;
for cards, the Luhn doubling from the right. This is what the playground animates.

```sh
curl "http://127.0.0.1:9292/api/v1/cnpj/validate?cnpj=12.ABC.345/01DE-35&explain=true"
```

```json
{"kind":"cnpj","input":"12.ABC.345/01DE-35","valid":true,"normalized":"12ABC34501DE35","formatted":"12.ABC.345/01DE-35","errors":[],"details":{"root":"12ABC345","branch":"01DE","check_digits":"35","alphanumeric":true,"headquarters":false,"steps":[{"label":"first check digit","chars":["1","2","A","B","C","3","4","5","0","1","D","E"],"values":[1,2,17,18,19,3,4,5,0,1,20,21],"weights":[5,4,3,2,9,8,7,6,5,4,3,2],"products":[5,8,51,36,171,24,28,30,0,4,60,42],"sum":459,"modulus":11,"remainder":8,"check_digit":3,"actual":3,"match":true},{"label":"second check digit","...":"abridged"}]}}
```

Values longer than 512 characters are refused as a `400`; between 257 and 512 the validator itself answers
`valid: false` with a `too_long` error.

### Generate

`GET /api/v1/<document>/generate` returns `{kind, seed, count, items}`.

| Document | Options (besides `count` and `seed`) |
|---|---|
| `cpf` | `uf` (state of the fiscal-region digit), `formatted` |
| `cnpj` | `alphanumeric` (letters in the root), `branch` (four characters, default `0001`), `formatted` |
| `pis` | `formatted` |
| `card` | `brand` (`visa`, `mastercard`, `elo`, ...; items are objects with `number`, `formatted`, `brand`, `brand_name`) |
| `plate` | `layout` (`mercosul` by default, or `legacy`), `formatted` |
| `phone` | `ddd`, `uf`, `type` (`mobile` or `landline`), `formatted` |
| `cep` | `uf`, `formatted` |

```sh
curl "http://127.0.0.1:9292/api/v1/cpf/generate?uf=SP&count=3&seed=7&formatted=true"
```

```json
{"kind":"cpf","seed":7,"count":3,"items":["496.337.798-55","898.764.078-72","763.588.758-09"]}
```

```sh
curl "http://127.0.0.1:9292/api/v1/cnpj/generate?alphanumeric=true&count=2&seed=42&formatted=true"
```

```json
{"kind":"cnpj","seed":42,"count":2,"items":["SE.7KI.MAA/0001-91","NZ.N2L.1NT/0001-02"]}
```

Generated card numbers are Luhn-valid test numbers, random and not tied to any account. Generated phone numbers are
syntactically valid and may belong to real subscribers: do not call them.

### Plate conversion

```sh
curl "http://127.0.0.1:9292/api/v1/plate/convert?plate=ABC-1234"
```

```json
{"kind":"plate","input":"ABC-1234","valid":true,"normalized":"ABC1C34","formatted":"ABC1C34","errors":[],"details":{"from":"legacy","layout":"mercosul","conversion":{"position":5,"digit":"2","letter":"C"}}}
```

### PIX payload

`POST /api/v1/pix/payload` with a JSON body builds a static BR Code (the "copia e cola" text).

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | CPF, CNPJ, mobile phone (`+55...`), e-mail or random key (UUID) |
| `name` | yes | Merchant name, at most 25 characters once accents are removed |
| `city` | yes | Merchant city, at most 15 characters |
| `amount` | no | Value in reais with at most two decimals (a number or a string); omit for an open amount |
| `txid` | no | Reconciliation id, 1 to 25 letters or digits; `***` when omitted |
| `message` | no | Text shown to the payer; shares 99 characters with the key |
| `key_type` | no | Force `cpf`, `cnpj`, `phone`, `email` or `evp` instead of detecting it |

```sh
curl -X POST http://127.0.0.1:9292/api/v1/pix/payload -H "content-type: application/json" \
  -d '{"key":"123e4567-e12b-12d1-a456-426655440000","name":"Fulano de Tal","city":"BRASILIA","amount":12.5,"txid":"PED123","message":"Pedido 42"}'
```

```json
{"payload":"00020126710014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400000209Pedido 42520400005303986540512.505802BR5913Fulano de Tal6008BRASILIA62100506PED12363047885","crc":"7885","key_type":"evp","fields":[{"id":"00","name":"Payload Format Indicator","length":2,"value":"01"},"...abridged: the whole TLV tree"]}
```

Render `payload` as a QR code with any QR encoder; none is bundled.

### PIX decode

`POST /api/v1/pix/decode` takes `{"payload": "...", "explain": false}`. It always answers `200` for a well-formed
request: a bad payload is `valid: false` with `errors` such as `crc_mismatch`, `missing_field`, `unexpected_value`
or `malformed_tlv`. `details` carries `length`, `crc` (`expected`, `actual`, `valid`), `fields` (the TLV tree) and
`pix` (the key, its type, the merchant, the amount and the txid). With `"explain": true`, `details.crc.steps` lists
the CRC register after every byte of the payload (`byte`, `index`, `table`, `crc`).

```sh
curl -X POST http://127.0.0.1:9292/api/v1/pix/decode -H "content-type: application/json" \
  -d '{"payload":"00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D"}'
```

```json
{"kind":"pix","input":"0002012658...","valid":true,"normalized":"0002012658...","formatted":null,"errors":[],"details":{"length":137,"crc":{"expected":"1D3D","actual":"1D3D","valid":true},"fields":["...abridged"],"pix":{"template":"26","key":"123e4567-e12b-12d1-a456-426655440000","key_type":"evp","message":null,"url":null,"fss":null,"dynamic":false,"single_use":false,"amount":null,"merchant_name":"Fulano de Tal","merchant_city":"BRASILIA","txid":"***"}}}
```

### Fictitious people

```sh
curl "http://127.0.0.1:9292/api/v1/fake/person?count=1&seed=7"
```

```json
{"kind":"person","seed":7,"count":1,"items":[{"name":"Carlos Souza Rocha","gender":"M","cpf":"407.076.356-24","email":"carlos.rocha34@example.org","phone":"(38) 99978-9876","phone_e164":"+5538999789876","birthdate":"1994-09-17","address":{"street":"Rua XV de Novembro","number":"8505","complement":null,"neighborhood":"Jardim Botânico","city":"Montes Claros","uf":"MG","cep":"38964-494"}}]}
```

Everything is synthetic: the CPF passes the checksum but belongs to nobody in particular, e-mail addresses use the
reserved `example.com`, `.org` and `.net` domains, and the birthdate is computed from a fixed reference date, so the
same seed gives the same person forever.

## Errors

See [problems.md](problems.md). Two examples:

```sh
curl "http://127.0.0.1:9292/api/v1/cpf/generate?count=500"
```

```json
{"type":"https://github.com/q6r/brkit/blob/main/docs/problems.md#invalid-parameter","title":"Invalid parameter","status":400,"detail":"count must be between 1 and 100","request_id":"70c4b335-914d-41ec-a9b2-e634eafc7b72","errors":[{"code":"out_of_range","message":"count must be between 1 and 100","field":"count"}]}
```

## Configuration

Read from the environment when the application is built. A bad value stops the boot with a message that names the
variable.

| Variable | Meaning | Default |
|---|---|---|
| `BRKIT_CORS_ORIGIN` | Comma-separated origins allowed to call the API from a browser, or `*`. Credentials are never allowed. | none (CORS off) |
| `BRKIT_MAX_BODY_BYTES` | Largest accepted request body (1 to 1 048 576) | `16384` |
| `BRKIT_RATE_LIMIT` | Sustained requests per minute per client (0 turns limiting off) | `120` |
| `BRKIT_RATE_BURST` | Token-bucket size: requests allowed in a burst | `40` |
| `BRKIT_TRUST_PROXY` | `1` to take the client address from the right-most `X-Forwarded-For` entry | off |

The rate limiter covers the API (`/api/...`); the playground's own files and `/healthz` are not counted, so loading
the page never spends the budget of the calls it then makes. Behind a reverse proxy set `BRKIT_TRUST_PROXY=1` so the
limiter sees the real client, and only then: with it on, anyone who can reach the application directly can pick
their own address. The limiter keeps its state in memory, per process.

## Security headers

Every response carries `x-content-type-options: nosniff`, `referrer-policy: no-referrer` and
`x-frame-options: DENY`. HTML is served with `default-src 'self'; script-src 'self'; style-src 'self';
connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none';
form-action 'self'`, so the playground cannot load anything from another origin, and SVG files are sandboxed.
Static files are served only from `public/`: segments must be plain names (no dots at the start, no encoded
separators), symbolic links cannot leave the folder and files larger than 5 MiB are refused.
