# frozen_string_literal: true

module Brkit
  class CLI
    # The shell completion scripts printed by +brkit completion SHELL+.
    #
    # Both scripts are generated from one table of what each command accepts, so they offer exactly the words the
    # command line knows; test/cli_test.rb checks every option in the table against the real option parsers.
    # @api private
    module Completion
      SHELLS = %w[bash powershell].freeze
      # Options every command that takes options also accepts.
      COMMON = %w[--help --color].freeze
      GENERATE = %w[-n --count --seed --format --formatted --json].freeze
      # Options that consume the next word, so it must not be mistaken for a sub-command or a value to check.
      VALUE_OPTIONS = %w[-n --count --seed --uf --branch --brand --layout --ddd --type --key --name --city --amount --txid
                         --message --key-type --host --port --color].freeze

      class << self
        # @param shell [String] one of {SHELLS}
        # @return [String] the script, ending in a newline
        # @raise [ArgumentError] for an unknown shell
        def script(shell)
          case shell
          when "bash" then bash
          when "powershell" then powershell
          else raise ArgumentError, "unknown shell #{shell.inspect}; expected #{SHELLS.join(' or ')}"
          end
        end

        # @return [Hash{String=>Array<String>}] the words that may follow each prefix of the command line; the key is
        #   the first one or two words that are not options ("" is the program name alone)
        def words
          table = { "" => %w[pix fake serve completion help version --help --version] + CLI::DOCUMENTS.keys }
          CLI::DOCUMENTS.each { |name, document| table.update(document_words(name, document)) }
          table.update("pix" => %w[payload decode], "pix payload" => payload_options, "pix decode" => %w[--json] + COMMON,
                       "fake" => %w[person], "fake person" => %w[-n --count --seed --json] + COMMON,
                       "serve" => %w[--host --port] + COMMON, "completion" => SHELLS)
        end

        # @return [Hash{String=>Array<String>}] the values that follow an option
        def values
          { "--color" => CLI::COLOR_MODES, "--layout" => %w[mercosul legacy], "--type" => %w[mobile landline],
            "--brand" => Card.brands, "--key-type" => Pix::Key::TYPES, "--uf" => UF::CODES }
        end

        private

        def document_words(name, document)
          actions = %w[validate generate]
          actions << "format" if document.library.respond_to?(:format)
          actions << "convert" if name == "plate"
          table = { name => actions, "#{name} validate" => (document.explain ? %w[--explain] : []) + %w[--json] + COMMON,
                    "#{name} generate" => GENERATE + generate_options(name) + COMMON }
          table["#{name} format"] = COMMON if actions.include?("format")
          table["plate convert"] = %w[--json] + COMMON if name == "plate"
          table
        end

        def generate_options(name)
          { "cpf" => %w[--uf], "cnpj" => %w[--alphanumeric --branch], "card" => %w[--brand], "plate" => %w[--layout],
            "phone" => %w[--ddd --uf --type], "cep" => %w[--uf] }.fetch(name, [])
        end

        def payload_options
          %w[--key --name --city --amount --txid --message --key-type --json] + COMMON
        end

        def bash
          cases = words.map { |prefix, list| "    #{prefix.inspect}) words=#{list.join(' ').inspect} ;;" }.join("\n")
          choices = values.map do |option, list|
            "    #{option}) COMPREPLY=($(compgen -W #{list.join(' ').inspect} -- \"$cur\")); return ;;"
          end
          BASH_TEMPLATE.sub("@@VALUE_OPTIONS@@", VALUE_OPTIONS.join("|")).sub("@@CHOICES@@", choices.join("\n"))
                       .sub("@@CASES@@", cases)
        end

        def powershell
          contexts = words.map { |prefix, list| "        '#{prefix}' = #{powershell_array(list)}" }.join("\n")
          choices = values.map { |option, list| "        '#{option}' = #{powershell_array(list)}" }.join("\n")
          POWERSHELL_TEMPLATE.sub("@@VALUE_OPTIONS@@", VALUE_OPTIONS.map { |option| "'#{option}'" }.join(", "))
                             .sub("@@CHOICES@@", choices).sub("@@CONTEXTS@@", contexts)
        end

        def powershell_array(list)
          "@(#{list.map { |word| "'#{word}'" }.join(', ')})"
        end
      end

      BASH_TEMPLATE = <<~BASH
        # bash completion for brkit. Load it with:  source <(brkit completion bash)
        _brkit() {
          local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}" prefix="" count=0 words i
          case "$prev" in
        @@CHOICES@@
          esac
          # The first two words that are not options (and not the value of an option) say what may come next.
          for ((i = 1; i < COMP_CWORD; i++)); do
            case "${COMP_WORDS[i]}" in
              @@VALUE_OPTIONS@@) ((i++)) ;;
              -*) ;;
              *) if ((count < 2)); then prefix="${prefix:+$prefix }${COMP_WORDS[i]}"; fi; ((count++)) ;;
            esac
          done
          case "$prefix" in
        @@CASES@@
            *) words="" ;;
          esac
          COMPREPLY=($(compgen -W "$words" -- "$cur"))
        }
        complete -F _brkit brkit
      BASH

      POWERSHELL_TEMPLATE = <<~'POWERSHELL'
        # PowerShell completion for brkit. Load it with:  brkit completion powershell | Out-String | Invoke-Expression
        # (PowerShell does not call completers for a bare - or --: type one letter after the dashes.)
        Register-ArgumentCompleter -Native -CommandName brkit -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            $contexts = @{
        @@CONTEXTS@@
            }
            $choices = @{
        @@CHOICES@@
            }
            $valueOptions = @(@@VALUE_OPTIONS@@)

            # The words before the one being completed, taken from the text up to the cursor ("--" is not an AST element).
            $text = $commandAst.ToString()
            $length = $cursorPosition - $commandAst.Extent.StartOffset
            if ($length -ge 0 -and $length -lt $text.Length) { $text = $text.Substring(0, $length) }
            $typed = @($text -split '\s+' | Where-Object { $_ -ne '' } | Select-Object -Skip 1)
            if ($typed.Count -gt 0 -and $wordToComplete -ne '' -and $typed[$typed.Count - 1] -eq $wordToComplete) {
                $typed = @($typed | Select-Object -SkipLast 1)
            }
            $previous = if ($typed.Count -gt 0) { $typed[$typed.Count - 1] } else { '' }
            if ($choices.ContainsKey($previous)) {
                $candidates = $choices[$previous]
            } else {
                $prefix = @()
                for ($i = 0; $i -lt $typed.Count; $i++) {
                    if ($valueOptions -contains $typed[$i]) { $i++; continue }
                    if ($typed[$i].StartsWith('-')) { continue }
                    if ($prefix.Count -lt 2) { $prefix += $typed[$i] }
                }
                $key = $prefix -join ' '
                $candidates = if ($contexts.ContainsKey($key)) { $contexts[$key] } else { @() }
            }
            $candidates | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
      POWERSHELL
    end
  end
end
