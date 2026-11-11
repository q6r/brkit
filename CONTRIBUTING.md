# Contributing to brkit

Thanks for helping. The project is small on purpose: a library with no runtime dependencies, a command line,
a Rack JSON API and a static playground. Please keep it that way.

## Setup

You need Ruby 3.1 or newer.

```sh
git clone https://github.com/q6r/brkit.git
cd brkit
bundle install
```

To run the server (`brkit serve` and the playground) install the optional group too:

```sh
bundle config set --local with server
bundle install
bundle exec rackup config.ru --host 127.0.0.1 --port 9292    # or: bundle exec ruby exe/brkit serve
```

## Tests

```sh
bundle exec rake test     # the whole suite, about 10 seconds
ruby -Ilib -Itest test/cpf_test.rb   # one file
```

- `test/all.rb` lists every test file explicitly (so the suite also runs in sandboxes that cannot list
  directories). `test/manifest_test.rb` fails when you add a `*_test.rb` and forget to list it there.
- Tests must be deterministic and offline: seed every random source, inject clocks, never touch the network.
- A new validator or generator needs the edge cases too: wrong length, wrong characters, repeated digits,
  a bad checksum, hostile input (control characters, bidi marks, very long values), not only the happy path.
- Behaviour that the README or `docs/` describe must have a test that would fail if the description became false.

## Lint

```sh
bundle exec rubocop
bundle exec rake          # tests and rubocop
```

The configuration is in `.rubocop.yml`. Public methods carry YARD comments (`@param`, `@return`, an example when
it helps).

## The playground

The playground lives in `public/` and is plain HTML, CSS and JavaScript: no build step, no CDN, no web fonts, no
inline scripts or styles (the server sends `script-src 'self'; style-src 'self'`).

- `aurora.css` and `aurora.js` are the project's own bundled Aurora UI kit (zero dependencies, MIT, part of this
  repository). Project-specific styling and behaviour belong in `app.css` and `app.js`. The kit files are small and
  dependency-free and may be edited with care: keep the page policy (no `innerHTML`, no inline style or script,
  tokens only, no external requests). The kit's charts module is not used by the playground and is not shipped.
- The page is built by `Aurora.shell` (navigation rail, top bar, tool pills, status bar); `public/index.html` is an
  empty page for it to fill. A new tool needs a view (an entry in `DOCS` in `public/app.js`, or a function of its
  own), an entry in `TAB_IDS`, `TAB_ICONS` and `ALGO_ICONS`, its `tab.*` and `algo.*` texts in both languages, and
  its id in the list in `test/playground_test.rb`.
- Texts live in the dictionary at the top of `public/app.js`, in Portuguese and English. Add both when you add a
  string; `test/playground_test.rb` checks that the two languages have the same keys and that every text the script
  asks for exists. Texts under `aurora.` replace the kit's own labels (palette, tables, theme toggle).
- All text reaches the page through `textContent`. Never build HTML from API data.
- Colours come from the kit's tokens (`var(--ink-1)`, `var(--accent)`, ...); a test fails on a colour literal.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat: ...`, `fix: ...`, `docs: ...`,
  `test: ...`, `refactor: ...`, `chore: ...`.
- Keep a pull request to one change, add a line to `CHANGELOG.md` under *Unreleased*, and make sure
  `bundle exec rake` is green.
- Security problems: do not open a public issue; follow [SECURITY.md](SECURITY.md).

## Ground rules

- Fictitious data only. Generated CPFs, CNPJs, cards and people pass the checksum but belong to nobody; never add
  real personal data, real card numbers or real PIX keys to tests, docs or examples.
- Do not add runtime dependencies. Development tools (minitest, rake, rubocop) are fine.
