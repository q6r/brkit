# frozen_string_literal: true

require "stringio"
require "tmpdir"

require_relative "test_helper"
require "brkit/cli"

module Brkit
  class CLITest < Minitest::Test
    Outcome = Struct.new(:status, :out, :err) do
      def lines
        out.lines.map(&:chomp)
      end

      def json
        JSON.parse(out)
      end
    end

    MANUAL_PAYLOAD = "00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913" \
                     "Fulano de Tal6008BRASILIA62070503***63041D3D"

    def brkit(*argv, stdin: "", env: {}, exec: nil)
      out = StringIO.new
      err = StringIO.new
      exec ||= ->(*_args) { flunk "the CLI must not exec here" }
      status = CLI.start(argv, stdout: out, stderr: err, stdin: StringIO.new(stdin), env: env, exec: exec)
      Outcome.new(status, out.string, err.string)
    end

    # -- general ------------------------------------------------------------------------------------------

    def test_version_and_help
      assert_equal ["brkit #{VERSION}"], brkit("--version").lines
      help = brkit("--help")
      assert_equal 0, help.status
      %w[cpf cnpj pix fake serve].each { |word| assert_includes help.out, word }
      assert_equal help.out, brkit("help").out
    end

    def test_usage_errors_exit_with_2_and_point_to_help
      [[], ["nonsense"], %w[cpf], %w[cpf dance], %w[cpf validate], %w[pix], %w[pix dance], %w[fake],
       %w[cpf validate --nope x]].each do |argv|
        outcome = brkit(*argv)
        assert_equal 2, outcome.status, argv.inspect
        assert_empty outcome.out
        assert_includes outcome.err, "Try 'brkit --help'", argv.inspect
      end
    end

    def test_per_command_help_exits_cleanly
      outcome = brkit("cpf", "generate", "--help")
      assert_equal 0, outcome.status
      assert_includes outcome.out, "--seed"
      assert_includes outcome.out, "--uf"
    end

    # -- validate -----------------------------------------------------------------------------------------

    def test_a_valid_cpf_exits_0_and_names_the_region
      outcome = brkit("cpf", "validate", "529.982.247-25")
      assert_equal 0, outcome.status
      assert_equal ["valid: 529.982.247-25 (CPF) - fiscal region 7 (ES, RJ)"], outcome.lines
    end

    def test_an_invalid_cpf_exits_1_and_explains_why
      outcome = brkit("cpf", "validate", "529.982.247-26")
      assert_equal 1, outcome.status
      assert_equal "invalid: 529.982.247-26 (CPF)", outcome.lines.first
      assert_includes outcome.lines[1], "second check digit"
    end

    def test_several_values_report_each_and_fail_if_any_fails
      outcome = brkit("cpf", "validate", "529.982.247-25", "111.111.111-11")
      assert_equal 1, outcome.status
      assert_equal(%w[valid: invalid:], outcome.lines.grep(/\A(in)?valid:/).map { |line| line[/\A\S+/] })
    end

    def test_values_can_come_from_standard_input
      outcome = brkit("cpf", "validate", "-", stdin: "529.982.247-25\n\n52998224725\n")
      assert_equal 0, outcome.status
      assert_equal 2, outcome.lines.length
    end

    def test_json_output_is_one_object_per_value
      outcome = brkit("cnpj", "validate", "12.ABC.345/01DE-35", "11.222.333/0001-82", "--json")
      first, second = outcome.lines.map { |line| JSON.parse(line) }
      assert_equal [true, "cnpj", "12ABC34501DE35"], first.values_at("valid", "kind", "normalized")
      assert_equal false, second["valid"]
      assert_equal 1, outcome.status
    end

    def test_explain_shows_the_checksum_work
      cpf = brkit("cpf", "validate", "529.982.247-25", "--explain").out
      assert_includes cpf, "first check digit"
      assert_includes cpf, "sum 295; 295 mod 11 = 9; check digit 2"
      assert_match(/^    products {1,2}50 18 72 63 48 10  8 12 14$/, cpf, "row labels keep a gap before the first cell")

      cnpj = brkit("cnpj", "validate", "12.ABC.345/01DE-35", "--explain").out
      assert_match(/values\s+1\s+2\s+17\s+18\s+19/, cnpj, "letters are shown as their numeric value")

      luhn = brkit("card", "validate", "4111111111111111", "--explain").out
      assert_includes luhn, "Luhn"
      assert_includes luhn, "sum 30; 30 mod 10 = 0"
      rows = luhn.lines(chomp: true).grep(/\A    (digits|doubled|counts) /)
      assert_equal 3, rows.length
      assert_equal [rows.first.length], rows.map(&:length).uniq, "the x2 marks line up under the digits"
    end

    def test_documents_without_steps_have_no_explain_flag
      assert_equal 2, brkit("plate", "validate", "ABC-1234", "--explain").status
    end

    def test_every_document_has_a_validator
      { "pis" => "123.45678.91-9", "card" => "4111 1111 1111 1111", "plate" => "ABC1D23",
        "phone" => "(11) 98765-4321", "cep" => "01310-100" }.each do |document, value|
        outcome = brkit(document, "validate", value)
        assert_equal 0, outcome.status, document
        assert outcome.out.start_with?("valid:"), document
      end
    end

    # -- generate and format ------------------------------------------------------------------------------

    def test_generation_is_reproducible_and_valid
      first = brkit("cpf", "generate", "--seed", "42", "-n", "5")
      assert_equal first.out, brkit("cpf", "generate", "--seed", "42", "-n", "5").out
      refute_equal first.out, brkit("cpf", "generate", "--seed", "43", "-n", "5").out
      assert_equal 5, first.lines.length
      first.lines.each { |cpf| assert_valid CPF.validate(cpf) }
    end

    # The first line printed by +brkit <document> generate --seed 1 <options>+.
    def generated(document, *options)
      brkit(document, "generate", "--seed", "1", *options).lines.first
    end

    def test_generation_options_reach_the_generators
      assert_match(/\A\d{3}\.\d{3}\.\d{3}-\d{2}\z/, generated("cpf", "--format"))
      assert_equal 8, CPF.validate(generated("cpf", "--uf", "SP")).details[:region_digit]
      assert_match(/\A[0-9A-Z]{8}0002\d{2}\z/, generated("cnpj", "--alphanumeric", "--branch", "0002"))
      assert_equal "visa", Card.detect(generated("card", "--brand", "visa").delete(" ")).id
      assert_match(/\A[A-Z]{3}-\d{4}\z/, generated("plate", "--layout", "legacy", "--format"))
      assert_equal "landline", Phone.validate(generated("phone", "--ddd", "11", "--type", "landline")).details[:type]
      assert_valid PIS.validate(generated("pis"))
      assert_equal "RJ", CEP.validate(generated("cep", "--uf", "RJ")).details[:uf]
    end

    def test_json_generation_has_the_same_envelope_as_the_api
      document = brkit("cpf", "generate", "-n", "2", "--seed", "9", "--json").json
      assert_equal ["cpf", 9, 2], document.values_at("kind", "seed", "count")
      assert_equal 2, document["items"].length

      card = brkit("card", "generate", "--seed", "9", "--json").json["items"].first
      assert_equal %w[number formatted brand brand_name], card.keys
    end

    def test_generation_limits
      assert_equal 2, brkit("cpf", "generate", "-n", "0").status
      assert_equal 2, brkit("cpf", "generate", "-n", "10001").status
      assert_equal 2, brkit("cpf", "generate", "--seed", "-1").status
      assert_equal 2, brkit("cpf", "generate", "extra").status
      assert_equal 2, brkit("cpf", "generate", "-n", "many").status
      assert_equal 1, brkit("cpf", "generate", "--uf", "ZZ").status, "a library refusal exits 1"
    end

    def test_format_applies_the_display_mask
      assert_equal ["529.982.247-25", "12.ABC.345/01DE-35"],
                   brkit("cpf", "format", "52998224725").lines + brkit("cnpj", "format", "12abc34501de35").lines
      assert_equal 2, brkit("card", "format", "4111111111111111").status
      assert_equal 2, brkit("cpf", "format").status
    end

    def test_plate_conversion
      assert_equal ["ABC1C34"], brkit("plate", "convert", "ABC-1234").lines
      assert_equal ["ABC1D23"], brkit("plate", "convert", "ABC1D23").lines
      invalid = brkit("plate", "convert", "AB-1234")
      assert_equal 1, invalid.status
      assert_includes invalid.err, "AB-1234"
      details = brkit("plate", "convert", "ABC-1234", "--json").json["details"]
      assert_equal %w[legacy mercosul], details.values_at("from", "layout")
      assert_equal 2, brkit("cpf", "convert", "1").status
    end

    # -- PIX ----------------------------------------------------------------------------------------------

    def test_pix_payload_reproduces_the_manual_example
      outcome = brkit("pix", "payload", "--key", "123e4567-e12b-12d1-a456-426655440000", "--name", "Fulano de Tal",
                      "--city", "BRASILIA", "--txid", "***")
      assert_equal 0, outcome.status
      assert_equal [MANUAL_PAYLOAD], outcome.lines
    end

    def test_pix_payload_json_and_options
      document = brkit("pix", "payload", "--key", "+5511987654321", "--name", "Loja", "--city", "Sao Paulo",
                       "--amount", "12.50", "--txid", "PED1", "--message", "Obrigado", "--json").json
      assert_equal "phone", document["key_type"]
      assert_match(/\A\h{4}\z/, document["crc"])
      assert_includes document["payload"], "540512.50"
    end

    def test_pix_payload_needs_its_required_options
      outcome = brkit("pix", "payload", "--name", "Loja")
      assert_equal 2, outcome.status
      assert_includes outcome.err, "--key, --city"
      assert_equal 1, brkit("pix", "payload", "--key", "nope", "--name", "Loja", "--city", "SP").status
    end

    def test_pix_decode_prints_the_tree_and_the_verdict
      outcome = brkit("pix", "decode", MANUAL_PAYLOAD)
      assert_equal 0, outcome.status
      assert_equal "valid: BR Code, CRC 1D3D", outcome.lines.first
      assert_includes outcome.out, "26 Merchant Account Information"
      assert_includes outcome.out, "  01 Pix key (chave): 123e4567-e12b-12d1-a456-426655440000"
    end

    def test_pix_decode_reports_a_tampered_payload
      outcome = brkit("pix", "decode", MANUAL_PAYLOAD.sub("Fulano", "Fulana"))
      assert_equal 1, outcome.status
      assert_equal "invalid: BR Code", outcome.lines.first
      assert_includes outcome.out, "CRC mismatch"
      assert_equal false, brkit("pix", "decode", "garbage", "--json").json["valid"]
      assert_equal 2, brkit("pix", "decode").status
    end

    def test_pix_decode_reads_standard_input
      assert_equal 0, brkit("pix", "decode", "-", stdin: "#{MANUAL_PAYLOAD}\n").status
    end

    # -- fake people --------------------------------------------------------------------------------------

    def test_fake_people_are_reproducible_and_carry_valid_cpfs
      first = brkit("fake", "person", "--seed", "5", "-n", "3")
      assert_equal first.out, brkit("fake", "person", "--seed", "5", "-n", "3").out
      cpfs = first.out.scan(/CPF (\d{3}\.\d{3}\.\d{3}-\d{2})/).flatten
      assert_equal 3, cpfs.length
      cpfs.each { |cpf| assert_valid CPF.validate(cpf) }
    end

    def test_fake_people_as_json
      document = brkit("fake", "person", "--seed", "5", "--json").json
      assert_equal ["person", 5, 1], document.values_at("kind", "seed", "count")
      assert_equal 2, brkit("fake", "robot").status
    end

    # -- colour -------------------------------------------------------------------------------------------

    # A terminal as far as the CLI can tell.
    class TerminalIO < StringIO
      def tty?
        true
      end
    end

    ANSI = /\e\[[\d;]*m/

    def on_terminal(*argv, env: {})
      out = TerminalIO.new
      CLI.start(argv, stdout: out, stderr: StringIO.new, stdin: StringIO.new, env: env, exec: ->(*) {})
      out.string
    end

    def test_colour_is_off_unless_asked_for_or_on_a_terminal
      refute_includes brkit("cpf", "validate", "529.982.247-25").out, "\e["
      assert_includes brkit("cpf", "validate", "529.982.247-25", "--color", "always").out, "\e[1;32mvalid:\e[0m"
      assert_includes brkit("cpf", "validate", "--color=always", "529.982.247-26").out, "\e[1;31minvalid:\e[0m"
      refute_includes brkit("cpf", "validate", "529.982.247-25", "--color", "never").out, "\e["
    end

    def test_a_terminal_is_coloured_unless_no_color_or_a_dumb_terminal
      assert_includes on_terminal("cpf", "validate", "529.982.247-25"), "\e[1;32m"
      refute_includes on_terminal("cpf", "validate", "529.982.247-25", env: { "NO_COLOR" => "1" }), "\e["
      refute_includes on_terminal("cpf", "validate", "529.982.247-25", env: { "TERM" => "dumb" }), "\e["
      assert_includes on_terminal("cpf", "validate", "529.982.247-25", "--color", "always", env: { "NO_COLOR" => "1" }), "\e["
    end

    def test_json_and_generated_values_are_never_coloured
      refute_includes brkit("cpf", "validate", "529.982.247-25", "--json", "--color", "always").out, "\e["
      refute_includes brkit("cpf", "generate", "--seed", "1", "--color", "always").out, "\e["
    end

    def test_colour_only_adds_escape_sequences
      %w[529.982.247-25 529.982.247-26].each do |value|
        coloured = brkit("cpf", "validate", value, "--explain", "--color", "always").out
        assert_equal brkit("cpf", "validate", value, "--explain").out, coloured.gsub(ANSI, "")
      end
      assert_equal brkit("card", "validate", "4111111111111111", "--explain").out,
                   brkit("card", "validate", "4111111111111111", "--explain", "--color", "always").out.gsub(ANSI, "")
      [MANUAL_PAYLOAD, MANUAL_PAYLOAD.sub("Fulano", "Fulana")].each do |payload|
        assert_equal brkit("pix", "decode", payload).out, brkit("pix", "decode", payload, "--color", "always").out.gsub(ANSI, "")
      end
      people = brkit("fake", "person", "--seed", "3", "--color", "always").out
      assert_equal brkit("fake", "person", "--seed", "3").out, people.gsub(ANSI, "")
    end

    def test_the_colour_option_is_checked
      ["--color", "--color=rainbow", "--color=", "--color=Always"].each do |flag|
        outcome = brkit("cpf", "validate", "529.982.247-25", flag)
        assert_equal 2, outcome.status, flag
        assert_includes outcome.err, "--color expects one of: auto, always, never"
      end
      assert_equal 2, brkit("cpf", "validate", "529.982.247-25", "--color", "sepia").status
    end

    # -- completion ---------------------------------------------------------------------------------------

    def test_completion_scripts_are_printed_for_the_known_shells
      bash = brkit("completion", "bash")
      assert_equal 0, bash.status
      assert_includes bash.out, "complete -F _brkit brkit"
      powershell = brkit("completion", "powershell")
      assert_equal 0, powershell.status
      assert_includes powershell.out, "Register-ArgumentCompleter -Native -CommandName brkit"
      [bash.out, powershell.out].each do |script|
        assert script.end_with?("\n")
        CLI::DOCUMENTS.each_key { |name| assert_includes script, name }
        %w[pix fake serve completion --explain --alphanumeric --key-type].each { |word| assert_includes script, word }
      end
    end

    def test_completion_needs_exactly_one_known_shell
      [%w[completion], %w[completion zsh], %w[completion bash extra]].each do |argv|
        outcome = brkit(*argv)
        assert_equal 2, outcome.status, argv.inspect
        assert_includes outcome.err, "completion: expected bash or powershell"
      end
    end

    def test_every_completed_option_exists_in_the_real_command
      CLI::Completion.words.each do |prefix, words|
        next if prefix.empty? || words.none? { |word| word.start_with?("-") }

        help = brkit(*prefix.split, "--help")
        assert_equal 0, help.status, prefix
        (words.grep(/\A-/) - CLI::Completion::COMMON).each do |option|
          assert_includes help.out, option, "#{prefix} does not document #{option}"
        end
      end
    end

    def test_every_listed_command_is_a_real_command
      groups = %w[pix fake completion] + CLI::DOCUMENTS.keys
      CLI::Completion.words.each do |prefix, words|
        words.reject { |word| word.start_with?("-") }.each do |word|
          argv = prefix.empty? ? [word] : [*prefix.split, word]
          next if prefix.empty? && groups.include?(word) # a group needs its sub-command; those are listed on their own

          assert_equal 0, brkit(*argv, "--help").status, "#{argv.join(' ')} --help"
        end
      end
    end

    def test_value_lists_come_from_the_library
      values = CLI::Completion.values
      assert_equal Card.brands, values["--brand"]
      assert_equal Pix::Key::TYPES, values["--key-type"]
      assert_equal UF::CODES, values["--uf"]
      assert_equal CLI::COLOR_MODES, values["--color"]
    end

    # -- serve --------------------------------------------------------------------------------------------

    # Puts an executable +rackup.bat+ (the suffix makes it executable on Windows too) on a private PATH. The files
    # are removed one by one: Dir.mktmpdir with a block lists directories, which some sandboxes cannot do.
    def with_fake_rackup
      directory = Dir.mktmpdir("brkit-cli")
      path = File.join(directory, "rackup.bat")
      File.write(path, "")
      make_executable(path)
      yield path, { "PATH" => directory }
    ensure
      File.delete(path) if path && File.exist?(path)
      Dir.rmdir(directory) if directory
    end

    def make_executable(path)
      File.chmod(0o755, path)
    rescue NotImplementedError, SystemCallError
      nil # a sandbox without permission bits (WASI) treats every file as executable
    end

    def test_serve_hands_over_to_rackup_with_the_project_config
      with_fake_rackup do |rackup, env|
        calls = []
        outcome = brkit("serve", "--port", "17400", env: env, exec: ->(*args) { calls << args })
        assert_equal 0, outcome.status
        command, config, *flags = calls.first
        assert_equal rackup, command
        assert_equal "config.ru", File.basename(config)
        assert File.file?(config), "config.ru must exist next to the library"
        assert_equal %w[--host 127.0.0.1 --port 17400], flags
      end
    end

    def test_serve_without_rackup_is_an_environment_problem
      outcome = brkit("serve", env: { "PATH" => "" })
      assert_equal 3, outcome.status
      assert_includes outcome.err, "bundle config set --local with server"
    end

    def test_serve_validates_its_options
      with_fake_rackup do |_rackup, env|
        [%w[--port 0], %w[--port 70000], %w[--host bad/host], %w[--host], %w[extra]].each do |arguments|
          assert_equal 2, brkit("serve", *arguments, env: env).status, arguments.inspect
        end
      end
    end
  end
end
