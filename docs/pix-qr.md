# From a BR Code to a QR image

A static PIX QR code is just text. The "copia e cola" string that brkit builds is exactly what the QR symbol
encodes, and exactly what a payer's app reads back after scanning it. brkit produces and checks that text; it
does not ship a QR encoder, so the last step (turning text into pixels) is a call to the encoder of your choice.

## What is inside the symbol

```sh
brkit pix payload --key 123e4567-e12b-12d1-a456-426655440000 --name "Fulano de Tal" --city BRASILIA --amount 12.50 --txid PED123
```

```text
00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000520400005303986540512.505802BR5913Fulano de Tal6008BRASILIA62100506PED12363046B07
```

It is a chain of `ID` (2 digits), `length` (2 digits) and `value` objects, in the EMV QR Code format:

| ID | Meaning | Value here |
|---|---|---|
| `00` | Payload format indicator | `01` |
| `26` | Merchant account (a template with sub-fields `00` = `br.gov.bcb.pix`, `01` = the PIX key) | `0014br.gov.bcb.pix0136123e4567-...` |
| `52` | Merchant category code | `0000` |
| `53` | Currency (986 is the real) | `986` |
| `54` | Amount | `12.50` |
| `58` | Country | `BR` |
| `59` | Merchant name (25 characters at most) | `Fulano de Tal` |
| `60` | Merchant city (15 characters at most) | `BRASILIA` |
| `62` | Additional data (sub-field `05` = the reconciliation id, `***` when there is none) | `0506PED123` |
| `63` | CRC-16 of everything before it, `6304` included | `6B07` |

[algorithms.md](algorithms.md) explains the TLV layout and the CRC. The builder strips accents and accepts only
printable ASCII, so the text is always safe to hand to a QR encoder.

## Rendering the code

1. Build the text: `Brkit::Pix.build(...).to_s`, `brkit pix payload ...`, or `POST /api/v1/pix/payload`.
2. Pass that exact string, unchanged and with no trailing newline, to a QR encoder as the data to encode. The text
   contains lower-case letters, so the encoder will use its byte mode. Any encoder works (a gem, a library for your
   front end, or a command line tool); which one is a matter of your stack.
3. Print or show the symbol with a quiet zone (a blank margin) around it and strong contrast. Keep the "copia e cola"
   text next to it: people whose camera fails can paste it.
4. Scan the result with a real banking app before you ship it. A QR encoder cannot tell you whether a PSP accepts
   the key.

Do not edit the string after building it. Any change, even one character in the merchant name, invalidates the CRC
and the payer's app will refuse the code. That is what the playground's "Alterar 1 caractere" button demonstrates.

## Checking a code you already have

Whatever produced the QR, the text a scanner reads can be checked offline:

```sh
echo "$PAYLOAD" | brkit pix decode -
```

```text
valid: BR Code, CRC 6B07
00 Payload Format Indicator: 01
26 Merchant Account Information
  00 Globally Unique Identifier: br.gov.bcb.pix
  01 Pix key (chave): 123e4567-e12b-12d1-a456-426655440000
...
```

The command exits with status 1 and lists the problems (`CRC mismatch`, a missing mandatory field, a name longer than
25 characters, ...) when the code is wrong. The same check is `POST /api/v1/pix/decode`, and
`Brkit::Pix.decode(text)` in Ruby.

## Static and dynamic codes

brkit builds **static** codes: they carry the key and, optionally, an amount and a reconciliation id, and anyone can
pay them any number of times. A **dynamic** code replaces the key by the address of a payload (field `25` inside the
merchant account) that a PSP serves for one charge. The decoder reads such codes (`details.pix.url`, `dynamic: true`)
but the builder does not produce them yet; see the roadmap in the README.

## What brkit does not check

It checks structure, the fixed values, the field limits and the CRC. It does not know whether the key is registered,
whether the merchant exists or whether the amount is sensible: those live in the PSP's systems.
