# frozen_string_literal: true

require "json"
require "optparse"
require "securerandom"

require_relative "../brkit"
require_relative "cli/completion"
require_relative "cli/explain"
require_relative "cli/style"

module Brkit
  # The +brkit+ command line.
  #
  # {CLI.start} takes the arguments and the IO objects and returns the exit status instead of exiting, so it
  # is easy to test and to embed. Exit status: 0 success or valid, 1 invalid value, 2 usage error, 3 environment
  # problem (for example +rackup+ missing for +serve+).
  class CLI
    EXIT_OK = 0
    EXIT_INVALID = 1
    EXIT_USAGE = 2
    EXIT_ENVIRONMENT = 3

    # Most values a single +generate+ run may print.
    MAX_COUNT = 10_000
    DEFAULT_HOST = "127.0.0.1"
    DEFAULT_PORT = 9292

    # Raised for bad command lines; rendered as exit status 2.
    class UsageError < Brkit::Error; end

    # Raised by +--help+ inside an option parser; the message is the help text.
    class HelpRequested < Brkit::Error; end

    # OptionParser without its "officious" +--help+/+--version+/completion options, which call +exit+ and
    # would terminate a host process that embeds the CLI.
    class Parser < OptionParser
      def add_officious; end
    end

    # A document handled by the generic +validate+/+generate+/+format+ commands.
    Document = Struct.new(:name, :label, :library, :explain, keyword_init: true)

    DOCUMENTS = [
      Document.new(name: "cpf", label: "CPF", library: CPF, explain: true),
      Document.new(name: "cnpj", label: "CNPJ", library: CNPJ, explain: true),
      Document.new(name: "pis", label: "PIS", library: PIS, explain: true),
      Document.new(name: "card", label: "Card", library: Card, explain: true),
      Document.new(name: "plate", label: "Plate", library: Plate, explain: false),
      Document.new(name: "phone", label: "Phone", library: Phone, explain: false),
      Document.new(name: "cep", label: "CEP", library: CEP, explain: false)
    ].to_h { |document| [document.name, document] }.freeze

    # Document specific options of +generate+: each lambda declares them on the parser and fills the options hash.
    EXTRA_OPTIONS = {
      "cpf" => ->(parser, o) { parser.on("--uf UF", "state of the fiscal-region digit") { |value| o[:uf] = value } },
      "cnpj" => lambda do |parser, o|
        parser.on("--alphanumeric", "include letters (alphanumeric CNPJ)") { o[:alphanumeric] = true }
        parser.on("--branch XXXX", "four-character branch, default 0001") { |value| o[:branch] = value }
      end,
      "pis" => ->(_parser, _options) {},
      "card" => lambda do |parser, o|
        parser.on("--brand BRAND", "one of #{Card.brands.join(', ')}") { |value| o[:brand] = value }
      end,
      "plate" => lambda do |parser, o|
        parser.on("--layout LAYOUT", "mercosul (default) or legacy") { |value| o[:layout] = value }
      end,
      "phone" => lambda do |parser, o|
        parser.on("--ddd DDD", "area code") { |value| o[:ddd] = value }
        parser.on("--uf UF", "state of the area code") { |value| o[:uf] = value }
        parser.on("--type TYPE", "mobile (default) or landline") { |value| o[:type] = value }
      end,
      "cep" => ->(parser, o) { parser.on("--uf UF", "state of the CEP prefix") { |value| o[:uf] = value } }
    }.freeze

    # Document specific generation: builds one value from the options and the shared random source.
    BUILDERS = {
      "cpf" => ->(o, rng) { CPF.generate(uf: o[:uf], formatted: o[:format], rng: rng) },
      "cnpj" => lambda do |o, rng|
        CNPJ.generate(alphanumeric: o[:alphanumeric] || false, branch: o[:branch] || "0001", formatted: o[:format],
                      rng: rng)
      end,
      "pis" => ->(o, rng) { PIS.generate(formatted: o[:format], rng: rng) },
      "card" => ->(o, rng) { Card.generate(brand: o[:brand], formatted: o[:format], rng: rng) },
      "plate" => ->(o, rng) { Plate.generate(layout: o[:layout] || :mercosul, formatted: o[:format], rng: rng) },
      "phone" => lambda do |o, rng|
        Phone.generate(ddd: o[:ddd], uf: o[:uf], type: o[:type] || :mobile, formatted: o[:format], rng: rng)
      end,
      "cep" => ->(o, rng) { CEP.generate(uf: o[:uf], formatted: o[:format], rng: rng) }
    }.freeze

    USAGE = <<~TEXT
      Usage: brkit <command> [options]

      Documents: cpf, cnpj, pis, card, plate, phone, cep
        brkit <document> validate VALUE... [--explain] [--json]   check values ("-" reads them from stdin)
        brkit <document> generate [-n N] [--seed N] [--format] [--json] [document options]
            cpf: --uf   cnpj: --alphanumeric --branch   card: --brand   plate: --layout   phone: --ddd --uf --type
            cep: --uf
        brkit <document> format VALUE...                          apply the display mask (cpf cnpj pis phone cep)
        brkit plate convert VALUE...                              legacy plate to Mercosul

      PIX:
        brkit pix payload --key KEY --name NAME --city CITY [--amount 12.50] [--txid ID] [--message TEXT] [--json]
        brkit pix decode PAYLOAD [--json]

      Other:
        brkit fake person [-n N] [--seed N] [--json]
        brkit serve [--host HOST] [--port PORT]    start the HTTP API and playground (needs the rackup gem)
        brkit completion bash|powershell           print a shell completion script
        brkit --version | --help

      Colour: --color auto|always|never (default auto: only on a terminal; NO_COLOR is honoured). JSON is never coloured.
      Exit status: 0 success or valid, 1 invalid value, 2 usage error, 3 environment problem.
    TEXT

    COLOR_MODES = %w[auto always never].freeze

    # @param argv [Array<String>] the arguments after the program name
    # @param stdout [IO] normal output
    # @param stderr [IO] diagnostics
    # @param stdin [IO] read for the +-+ argument
    # @param env [#[]] environment (+PATH+ is used to find +rackup+)
    # @param exec [#call, nil] replaces the process for +serve+ (+Kernel.exec+ by default)
    # @return [Integer] the exit status
    def self.start(argv, stdout: $stdout, stderr: $stderr, stdin: $stdin, env: ENV, exec: nil)
      new(stdout: stdout, stderr: stderr, stdin: stdin, env: env, exec: exec || Kernel.method(:exec)).run(argv)
    end

    def initialize(stdout:, stderr:, stdin:, env:, exec:)
      @style = Style::PLAIN
      @stdout = stdout
      @stderr = stderr
      @stdin = stdin
      @env = env
      @exec = exec
    end

    # @param argv [Array<String>]
    # @return [Integer] the exit status
    def run(argv)
      args = argv.dup
      @style = Style.new(color_wanted?(take_color_option(args)))
      dispatch(args.shift, args)
    rescue HelpRequested => e
      @stdout.puts(e.message)
      EXIT_OK
    rescue UsageError, OptionParser::ParseError => e
      usage_error(e.message)
    rescue InvalidInputError => e
      e.issues.each { |issue| @stderr.puts("brkit: #{describe(issue)}") }
      EXIT_INVALID
    rescue Errno::EPIPE
      EXIT_OK
    end

    private

    def dispatch(command, args)
      case command
      when nil then usage_error("missing command")
      when "-h", "--help", "help" then print_usage
      when "-v", "--version", "version" then print_version
      when "serve" then serve(args)
      when "pix" then pix(args)
      when "fake" then fake(args)
      when "completion" then completion(args)
      else
        document = DOCUMENTS[command]
        document ? run_document(document, args) : usage_error("unknown command #{command.inspect}")
      end
    end

    # Removes every +--color WHEN+ or +--color=WHEN+ from +args+ and returns the last value ("auto" when absent).
    def take_color_option(args)
      mode = "auto"
      while (index = args.index { |arg| arg == "--color" || arg.start_with?("--color=") })
        arg = args.delete_at(index)
        mode = arg.include?("=") ? arg.split("=", 2).last : args.delete_at(index)
        raise UsageError, "--color expects one of: #{COLOR_MODES.join(', ')}" unless COLOR_MODES.include?(mode)
      end
      mode
    end

    def color_wanted?(mode)
      return mode == "always" unless mode == "auto"

      @stdout.respond_to?(:tty?) && @stdout.tty? && @env["NO_COLOR"].to_s.empty? && @env["TERM"] != "dumb"
    end

    def print_usage
      @stdout.puts(USAGE)
      EXIT_OK
    end

    def print_version
      @stdout.puts("brkit #{VERSION}")
      EXIT_OK
    end

    def usage_error(message)
      @stderr.puts("brkit: #{message}")
      @stderr.puts("Try 'brkit --help'.")
      EXIT_USAGE
    end

    def describe(issue)
      issue.field ? "#{issue.field}: #{issue.message}" : issue.message
    end

    # Builds a parser, lets the block declare options, then parses +args+ in place (leaving the positional ones).
    def parse(args, banner)
      parser = Parser.new(banner)
      parser.on("-h", "--help", "show this help") { raise HelpRequested, parser.help }
      yield parser
      parser.parse!(args)
    end

    def values_from(args)
      args.flat_map { |arg| arg == "-" ? @stdin.each_line.map(&:chomp).reject(&:empty?) : [arg] }
    end

    def seed_from(options)
      seed = options[:seed]
      return SecureRandom.random_number(Rng::MAX_SEED + 1) if seed.nil?
      raise UsageError, "seed must be between 0 and #{Rng::MAX_SEED}" unless seed.between?(0, Rng::MAX_SEED)

      seed
    end

    def count_from(options, limit = MAX_COUNT)
      count = options[:count]
      raise UsageError, "count must be between 1 and #{limit}" unless count.between?(1, limit)

      count
    end

    # -- documents ----------------------------------------------------------------------------------------

    def run_document(document, args)
      case (action = args.shift)
      when "validate" then validate(document, args)
      when "generate" then generate(document, args)
      when "format" then format_values(document, args)
      when "convert" then document.name == "plate" ? convert_plates(args) : usage_error("#{document.name} has no convert")
      else usage_error("#{document.name}: expected validate, generate or format, got #{action.inspect}")
      end
    end

    def validate(document, args)
      options = { explain: false, json: false }
      parse(args, "Usage: brkit #{document.name} validate VALUE... [options]") do |parser|
        parser.on("--explain", "show the checksum computation step by step") { options[:explain] = true } if document.explain
        parser.on("--json", "one JSON object per value") { options[:json] = true }
      end
      values = values_from(args)
      raise UsageError, "nothing to validate: pass one or more values (or - to read stdin)" if values.empty?

      results = values.map { |value| validate_one(document, value, options) }
      results.each { |result| report(document, result, options) }
      results.all?(&:valid?) ? EXIT_OK : EXIT_INVALID
    end

    def validate_one(document, value, options)
      return document.library.validate(value) unless document.explain

      document.library.validate(value, explain: options[:explain])
    end

    def report(document, result, options)
      return @stdout.puts(JSON.generate(result.to_h)) if options[:json]

      shown = result.formatted || result.input
      verdict = result.valid? ? @style.paint("valid:", :bold, :green) : @style.paint("invalid:", :bold, :red)
      detail = @style.paint("(#{document.label})#{summary(document, result)}", :dim)
      @stdout.puts("#{verdict} #{shown} #{detail}")
      result.errors.each { |issue| @stdout.puts(@style.paint("  - #{issue.message}", :red)) }
      Explain.lines(result.details, @style).each { |line| @stdout.puts(line) } if options[:explain]
    end

    # Extra facts appended to the first line of a valid result.
    def summary(document, result)
      return "" unless result.valid?

      details = result.details
      case document.name
      when "cpf" then " - fiscal region #{details[:region_digit]} (#{details[:ufs].join(', ')})"
      when "cnpj" then details[:alphanumeric] ? " - alphanumeric" : ""
      when "card" then " - #{details[:brand_name] || 'unknown brand'}"
      when "phone" then " - #{result.normalized}, #{details[:type]}, #{details[:uf]}"
      when "plate" then details[:layout] == "legacy" ? " - legacy, Mercosul #{details[:mercosul]}" : " - Mercosul"
      when "cep" then details[:uf] ? " - #{details[:uf]}" : ""
      else ""
      end
    end

    def format_values(document, args)
      library = document.library
      unless library.respond_to?(:format)
        return usage_error("#{document.name} has no format command; validate prints the display form")
      end

      parse(args, "Usage: brkit #{document.name} format VALUE...") { |_parser| nil }
      values = values_from(args)
      raise UsageError, "nothing to format: pass one or more values" if values.empty?

      values.each { |value| @stdout.puts(library.format(value)) }
      EXIT_OK
    end

    def convert_plates(args)
      options = { json: false }
      parse(args, "Usage: brkit plate convert VALUE... [--json]") do |parser|
        parser.on("--json", "one JSON object per value") { options[:json] = true }
      end
      values = values_from(args)
      raise UsageError, "nothing to convert: pass one or more plates" if values.empty?

      results = values.map { |value| Plate.convert(value) }
      results.each { |result| report_conversion(result, options) }
      results.all?(&:valid?) ? EXIT_OK : EXIT_INVALID
    end

    def report_conversion(result, options)
      if options[:json]
        @stdout.puts(JSON.generate(result.to_h))
      elsif result.valid?
        @stdout.puts(result.normalized)
      else
        @stderr.puts("brkit: #{result.input.inspect}: #{result.error_messages.join('; ')}")
      end
    end

    # -- generators ---------------------------------------------------------------------------------------

    def generate(document, args)
      options = { count: 1, seed: nil, format: false, json: false }
      parse(args, "Usage: brkit #{document.name} generate [options]") do |parser|
        common_generate_options(parser, options)
        EXTRA_OPTIONS.fetch(document.name).call(parser, options)
      end
      raise UsageError, "unexpected argument #{args.first.inspect}" unless args.empty?

      count = count_from(options)
      seed = seed_from(options)
      rng = Random.new(seed)
      items = Array.new(count) { BUILDERS.fetch(document.name).call(options, rng) }
      print_generated(document, items, seed, options[:json])
    end

    def common_generate_options(parser, options)
      parser.on("-n", "--count N", Integer, "how many values (default 1)") { |value| options[:count] = value }
      parser.on("--seed N", Integer, "seed for reproducible output") { |value| options[:seed] = value }
      parser.on("--format", "--formatted", "apply the display mask") { options[:format] = true }
      parser.on("--json", "JSON with kind, seed, count and items") { options[:json] = true }
    end

    def print_generated(document, items, seed, json)
      if json
        @stdout.puts(JSON.generate(kind: document.name, seed: seed, count: items.length,
                                   items: items.map { |item| json_item(document, item) }))
      else
        items.each { |item| @stdout.puts(item) }
      end
      EXIT_OK
    end

    # Card items are objects in JSON, like in the HTTP API; the other documents are plain strings.
    def json_item(document, item)
      return item unless document.name == "card"

      digits = item.delete(" ")
      brand = Card.detect(digits)
      { number: digits, formatted: Card.group(digits, brand), brand: brand.id, brand_name: brand.name }
    end

    # -- PIX ------------------------------------------------------------------------------------------------

    def pix(args)
      case (action = args.shift)
      when "payload" then pix_payload(args)
      when "decode" then pix_decode(args)
      else usage_error("pix: expected payload or decode, got #{action.inspect}")
      end
    end

    def pix_payload(args)
      options = { json: false }
      parse(args, "Usage: brkit pix payload --key KEY --name NAME --city CITY [options]") do |parser|
        pix_payload_options(parser, options)
      end
      raise UsageError, "unexpected argument #{args.first.inspect}" unless args.empty?

      missing = [:key, :name, :city].reject { |field| options[field] }
      unless missing.empty?
        raise UsageError, "missing required option#{'s' if missing.length > 1}: #{missing.map { |f| "--#{f}" }.join(', ')}"
      end

      payload = Pix.build(**options.except(:json))
      @stdout.puts(options[:json] ? JSON.generate(payload.to_h) : payload.to_s)
      EXIT_OK
    end

    def pix_payload_options(parser, options)
      parser.on("--key KEY", "PIX key: CPF, CNPJ, +55 phone, e-mail or random key") { |value| options[:key] = value }
      parser.on("--name NAME", "merchant name (25 characters at most)") { |value| options[:name] = value }
      parser.on("--city CITY", "merchant city (15 characters at most)") { |value| options[:city] = value }
      parser.on("--amount AMOUNT", "value in reais, e.g. 12.50") { |value| options[:amount] = value }
      parser.on("--txid ID", "reconciliation id (letters and digits)") { |value| options[:txid] = value }
      parser.on("--message TEXT", "text shown to the payer") { |value| options[:message] = value }
      parser.on("--key-type TYPE", Pix::Key::TYPES, "force the key type") { |value| options[:key_type] = value }
      parser.on("--json", "JSON with payload, crc and the TLV tree") { options[:json] = true }
    end

    def pix_decode(args)
      options = { json: false }
      parse(args, "Usage: brkit pix decode PAYLOAD [--json]") do |parser|
        parser.on("--json", "the full result as JSON") { options[:json] = true }
      end
      raise UsageError, "missing payload (quote it, or pass - to read stdin)" if args.empty?

      result = Pix.decode(values_from(args).join(" "))
      options[:json] ? @stdout.puts(JSON.generate(result.to_h)) : print_decoded(result)
      result.valid? ? EXIT_OK : EXIT_INVALID
    end

    def print_decoded(result)
      @stdout.puts(if result.valid?
                     "#{@style.paint('valid:', :bold, :green)} BR Code, CRC #{result.details[:crc][:actual]}"
                   else
                     "#{@style.paint('invalid:', :bold, :red)} BR Code"
                   end)
      result.errors.each do |issue|
        @stdout.puts(@style.paint("  - #{"[#{issue.field}] " if issue.field}#{issue.message}", :red))
      end
      Array(result.details[:fields]).each { |field| print_field(field, 0) }
    end

    def print_field(field, depth)
      label = "#{'  ' * depth}#{@style.paint(field[:id], :cyan)} #{field[:name]}"
      if field[:children]
        @stdout.puts(label)
        field[:children].each { |child| print_field(child, depth + 1) }
      else
        @stdout.puts("#{label}: #{@style.paint(field[:value], :bold)}")
      end
    end

    # -- fake people ----------------------------------------------------------------------------------------

    def fake(args)
      return usage_error("fake: expected person") unless args.shift == "person"

      options = { count: 1, seed: nil, json: false }
      parse(args, "Usage: brkit fake person [-n N] [--seed N] [--json]") do |parser|
        parser.on("-n", "--count N", Integer, "how many people (default 1)") { |value| options[:count] = value }
        parser.on("--seed N", Integer, "seed for reproducible output") { |value| options[:seed] = value }
        parser.on("--json", "JSON with kind, seed, count and items") { options[:json] = true }
      end
      raise UsageError, "unexpected argument #{args.first.inspect}" unless args.empty?

      seed = seed_from(options)
      people = Fake.people(count_from(options), seed: seed)
      print_people(people, seed, options[:json])
    end

    def print_people(people, seed, json)
      if json
        @stdout.puts(JSON.generate(kind: "person", seed: seed, count: people.length, items: people.map(&:to_h)))
      else
        people.each_with_index do |person, index|
          @stdout.puts if index.positive?
          person_lines(person).each { |line| @stdout.puts(line) }
        end
      end
      EXIT_OK
    end

    def person_lines(person)
      address = person.address
      street = [address[:street], address[:number], address[:complement]].compact.join(", ")
      [
        "#{@style.paint(person.name, :bold)} (#{person.gender})",
        "  CPF #{person.cpf}   phone #{person.phone}   e-mail #{person.email}",
        "  born #{person.birthdate.iso8601}",
        "  #{street} - #{address[:neighborhood]}, #{address[:city]}/#{address[:uf]}, #{address[:cep]}"
      ]
    end

    # -- completion -----------------------------------------------------------------------------------------

    def completion(args)
      parse(args, "Usage: brkit completion #{Completion::SHELLS.join('|')}") { |_parser| nil }
      unless args.length == 1 && Completion::SHELLS.include?(args.first)
        raise UsageError, "completion: expected #{Completion::SHELLS.join(' or ')}"
      end

      @stdout.write(Completion.script(args.first))
      EXIT_OK
    end

    # -- serve ----------------------------------------------------------------------------------------------

    def serve(args)
      options = { host: DEFAULT_HOST, port: DEFAULT_PORT }
      parse(args, "Usage: brkit serve [--host HOST] [--port PORT]") do |parser|
        parser.on("--host HOST", "address to bind (default #{DEFAULT_HOST})") { |value| options[:host] = value }
        parser.on("--port PORT", Integer, "port to listen on (default #{DEFAULT_PORT})") do |value|
          options[:port] = value
        end
      end
      raise UsageError, "unexpected argument #{args.first.inspect}" unless args.empty?
      raise UsageError, "invalid host #{options[:host].inspect}" unless options[:host].match?(/\A[A-Za-z0-9.:-]{1,253}\z/)
      raise UsageError, "port must be between 1 and 65535" unless options[:port].between?(1, 65_535)

      start_server(options)
    end

    def start_server(options)
      rackup = find_executable("rackup")
      unless rackup
        @stderr.puts("brkit: 'rackup' was not found. Install a Rack server first, for example:")
        @stderr.puts("  gem install rackup puma   (or: bundle config set --local with server, then bundle install)")
        return EXIT_ENVIRONMENT
      end

      @exec.call(rackup, File.expand_path("../../config.ru", __dir__), "--host", options[:host],
                 "--port", options[:port].to_s)
      EXIT_OK
    end

    # Looks +name+ up on PATH without running anything (a +.bat+/+.cmd+/+.exe+ suffix is tried too).
    def find_executable(name)
      @env["PATH"].to_s.split(File::PATH_SEPARATOR).each do |directory|
        ["", ".bat", ".cmd", ".exe"].each do |suffix|
          candidate = File.join(directory, "#{name}#{suffix}")
          return candidate if File.file?(candidate) && File.executable?(candidate)
        end
      end
      nil
    end
  end
end
