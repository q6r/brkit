#!/usr/bin/env bash
# Calls each kind of endpoint of a running brkit server and prints the replies.
#
#   brkit serve                      # in another terminal (or: bundle exec rackup config.ru)
#   bash examples/api.sh             # BRKIT_URL=http://127.0.0.1:9292 is the default
set -euo pipefail

base="${BRKIT_URL:-http://127.0.0.1:9292}"

get() {
  printf '\nGET %s\n' "$1"
  curl -sS "$base$1"
  echo
}

post() {
  printf '\nPOST %s\n' "$1"
  curl -sS -X POST "$base$1" -H 'content-type: application/json' -d "$2"
  echo
}

get "/healthz"
get "/api/v1/cpf/validate?cpf=529.982.247-25"
get "/api/v1/cpf/validate?cpf=529.982.247-26"
get "/api/v1/cnpj/generate?alphanumeric=true&count=2&seed=42&formatted=true"
get "/api/v1/card/generate?brand=visa&seed=1"
get "/api/v1/plate/convert?plate=ABC-1234"
post "/api/v1/pix/payload" '{"key":"123e4567-e12b-12d1-a456-426655440000","name":"Fulano de Tal","city":"BRASILIA","amount":12.5,"txid":"PED123"}'
post "/api/v1/pix/decode" '{"payload":"00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D"}'
get "/api/v1/fake/person?count=1&seed=7"
get "/api/v1/cpf/generate?count=500"
