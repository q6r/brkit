# Algorithms

How each document is checked, with the worked examples the playground animates. Every number below is produced by
the library (`brkit cpf validate ... --explain`, or `explain=true` on the API).

## Weighted modulo 11: CPF, CNPJ and PIS

Each check digit is computed from the characters before it:

1. Give every character a numeric value (a digit is itself; see the alphanumeric CNPJ below).
2. Multiply each value by its weight and add the products.
3. Take the remainder of the sum modulo 11.
4. The digit is `0` when the remainder is 0 or 1, otherwise `11 - remainder`.

### CPF

Nine serial digits, then two check digits: `NNN.NNN.NNN-DD`. The ninth serial digit is the *fiscal region*
(0 to 9, each assigned to a group of states). The first check digit uses weights `10 9 8 7 6 5 4 3 2` over the nine
digits; the second uses weights `11 10 9 8 7 6 5 4 3 2` over those nine digits plus the first check digit.
A CPF whose digits are all the same (`111.111.111-11`) passes the arithmetic and is rejected anyway.

`529.982.247-25`:

| | digits | weights | sum | sum mod 11 | digit |
|---|---|---|---|---|---|
| first | 5 2 9 9 8 2 2 4 7 | 10 9 8 7 6 5 4 3 2 | 50+18+72+63+48+10+8+12+14 = 295 | 9 | 11 - 9 = **2** |
| second | 5 2 9 9 8 2 2 4 7 2 | 11 10 9 8 7 6 5 4 3 2 | 55+20+81+72+56+12+10+16+21+4 = 347 | 6 | 11 - 6 = **5** |

The ninth digit is 7, which is the fiscal region of Espírito Santo and Rio de Janeiro: that is where the
`ufs: ["ES", "RJ"]` in the result comes from. `Brkit::CPF.generate(uf: "SP")` picks the region digit of São Paulo (8).

### CNPJ, classic and alphanumeric

Fourteen characters: eight of root, four of branch (*ordem*, `0001` is the head office) and two check digits:
`XX.XXX.XXX/XXXX-DD`. Weights are `5 4 3 2 9 8 7 6 5 4 3 2` for the first digit (over the twelve root and branch
characters) and `6 5 4 3 2 9 8 7 6 5 4 3 2` for the second (over those twelve plus the first digit).

The **alphanumeric CNPJ**, in force from July 2026, allows the letters `A` to `Z` in the first twelve characters. The
rule changes only step 1: a character's value is its ASCII code minus 48, so digits keep their value (`"0"` is 48,
so 0; `"9"` is 9) and letters follow on: `A` is 17, `B` is 18, ..., `Z` is 42. The weights and the modulo-11 rule are
unchanged, and the two check digits are always numeric. Every existing numeric CNPJ stays valid.

`12.ABC.345/01DE-35`:

| | characters → values | weights | sum | mod 11 | digit |
|---|---|---|---|---|---|
| first | 1 2 A B C 3 4 5 0 1 D E → 1 2 **17 18 19** 3 4 5 0 1 **20 21** | 5 4 3 2 9 8 7 6 5 4 3 2 | 459 | 8 | 11 - 8 = **3** |
| second | the same twelve plus 3 | 6 5 4 3 2 9 8 7 6 5 4 3 2 | 424 | 6 | 11 - 6 = **5** |

Lower-case letters are accepted and normalised to upper case; a CNPJ of one repeated character is rejected.

### PIS, PASEP, NIS and NIT

One 11-digit format: ten digits and one check digit, written `NNN.NNNNN.NN-D`, computed with the weights
`3 2 9 8 7 6 5 4 3 2` and the same modulo-11 rule.

## Luhn: payment cards

The Luhn (modulo 10) check catches typing mistakes. From the rightmost digit, going left, double every second digit
(starting with the second from the right); when doubling gives more than 9, subtract 9 (the same as adding the two
digits of the product). Add everything: the number is valid when the sum is a multiple of 10.

`4111 1111 1111 1111`, counting positions from the right starting at 0: the eight digits at even positions are
ones and count 1 each (8). Seven of the digits at odd positions are ones, doubled to 2 each (14); the eighth, the
leading `4`, is doubled to 8. The sum is 8 + 14 + 8 = 30, and 30 mod 10 = 0: valid.

The brand is detected from the leading digits (the IIN/BIN ranges of Visa, Mastercard, Elo, Hipercard, Hiper,
American Express, Diners Club, Discover, JCB and UnionPay) and its length rules are applied. That is a hint, not proof
that a card exists. `Brkit::Card.generate` produces Luhn-valid numbers with a real brand prefix; they are random test
numbers, never use them for real payments.

## PIX: the BR Code

A static PIX QR code, and its "copia e cola" text, is an EMV QRCPS payload: a sequence of **TLV** objects, each
`ID` (2 digits) + `length` (2 digits, decimal, counted in characters) + `value`. Some values are themselves a
sequence of TLVs (templates).

```text
00 02 01                                  payload format indicator = 01
26 58                                     merchant account information (template), 58 characters
   00 14 br.gov.bcb.pix                   GUI
   01 36 123e4567-e12b-12d1-a456-426655440000   the PIX key
52 04 0000                                merchant category code
53 03 986                                 currency (BRL)
58 02 BR                                  country
59 13 Fulano de Tal                       merchant name (25 characters at most)
60 08 BRASILIA                            merchant city (15 characters at most)
62 07 05 03 ***                           additional data: 05 = reference label (txid), *** = none
63 04 1D3D                                CRC16 of everything before it, "6304" included
```

The decoder checks the format indicator (`000201` first), that root IDs are unique, that the mandatory fields exist
(52, 53, 58, 59, 60, 62 with its reference label, and at least one merchant account), the fixed values (currency
`986`, country `BR`), the name and city limits, that the CRC field comes last, and the CRC itself. Every problem
becomes an error with a code and the field it refers to; the decoder never raises on bad input.

### CRC-16/CCITT-FALSE

Polynomial `0x1021`, initial value `0xFFFF`, no input or output reflection, no final XOR. The CRC covers the whole
payload up to and including the characters `6304` (the ID and length of the CRC field itself); its four hexadecimal
digits are the value of field 63. The check value for the ASCII text `123456789` is `0x29B1`.

The library uses the byte-at-a-time table form of the algorithm:

```text
index    = (register >> 8) XOR byte          (an 8-bit value)
register = ((register << 8) AND 0xFFFF) XOR TABLE[index]
```

where `TABLE[i]` is the register after feeding the byte `i` into the polynomial division bit by bit
(`TABLE[1] = 0x1021`). `Brkit::CRC16.trace(text)` returns one `{byte, index, table, crc}` per input byte, and
`POST /api/v1/pix/decode` with `"explain": true` puts that list in `details.crc.steps`: this is what the playground
steps through. For the static example of the Banco Central manual (`...6304`), the register after the last byte is
`0x1D3D`, the value printed in the manual.

Changing any single character of a payload changes the CRC: the test suite tries every single-character substitution
of the manual's example.

### Keys

| Type | Written in the payload as |
|---|---|
| CPF | 11 digits, no punctuation |
| CNPJ | 14 characters, no punctuation (letters allowed since the alphanumeric CNPJ) |
| Phone | `+55` and the number, mobile only: `+5511987654321` |
| E-mail | as registered, lower case, at most 77 characters |
| Random key (EVP) | a UUID with hyphens |

The key's type is detected from its shape (`Brkit::Pix::Key.detect`) unless forced with `key_type`. The key and the
free-text message share the 99 characters of the merchant-account template.

## Licence plates

Two layouts are in force: legacy `AAA-9999` and Mercosul `AAA9A99`. A legacy plate maps to its Mercosul equivalent
by replacing the 5th character (the second digit of the number) with a letter: `0` becomes `A`, `1` becomes `B`, and
so on up to `9` becoming `J`. `ABC-1234` has `2` in position 5, which becomes `C`: `ABC1C34`. Mercosul plates are
returned unchanged.

## Phone numbers

Geographic numbers only, following ANATEL's numbering plan: the area code (DDD) must be one of the 67 assigned codes;
a mobile number has 9 digits and starts with 9; a landline has 8 digits and starts with 2 to 5; eight-digit numbers
starting with 6 to 9 are the old mobile format and are reported as invalid. Accepted notations include
`(11) 98765-4321`, `11987654321`, `+55 11 98765-4321` and `011 98765-4321`; the canonical form is E.164
(`+5511987654321`). Special-service numbers (0800, 4004) and foreign numbers are rejected.

## CEP

Eight digits, `NNNNN-NNN`. Validation checks the shape only: there is no lookup and no claim that the code exists.
`Brkit::CEP` maps the first five digits to the state that owns the range (the table follows the prefix ranges
published by Correios and is approximate near range borders), which is what `generate(uf:)` uses.

## Fictitious people

`Brkit::Fake` combines common given names and surnames, a checksum-valid CPF whose region digit matches the person's
state, an e-mail on the reserved `example.com`, `.org` or `.net` domains, a mobile number whose area code matches the
state, a birthdate computed from a fixed reference date (so seeded output does not drift) and a made-up address with
a CEP in the state's range. The order in which random values are drawn is part of the contract: a seed always gives
the same person.
