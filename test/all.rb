# frozen_string_literal: true

# Loads every test file. The list is explicit (no globbing) so the suite also runs in sandboxes that cannot list
# directories; test/manifest_test.rb fails when a new *_test.rb file is missing from it.
#
#   ruby test/all.rb
#   rake test
%w[
  manifest_test
  errors_test
  result_test
  text_test
  rng_test
  uf_test
  crc16_test
  luhn_test
  cpf_test
  cnpj_test
  pis_test
  phone_test
  cep_test
  plate_test
  card_test
  pix_tlv_test
  pix_key_test
  pix_builder_test
  pix_decoder_test
  fake_test
  api/config_test
  api/params_test
  api/problem_test
  api/request_test
  api/response_test
  api/router_test
  api/static_test
  api/middleware_test
  api/openapi_test
  api/endpoints_test
  cli_test
  config_ru_test
  playground_test
].each { |name| require_relative name }
