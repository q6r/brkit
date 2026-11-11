# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/rack_helpers"
require "brkit/api"

module Brkit
  # Static checks of the playground in public/: what the browser may load, and the Portuguese and English texts.
  # The page itself is exercised in a real browser (see docs/); these tests keep its contract with the server
  # (Content-Security-Policy: no inline code, same origin only) from rotting.
  class PlaygroundTest < Minitest::Test
    PUBLIC = File.expand_path("../public", __dir__)
    OWN_FILES = %w[index.html app.css app.js].freeze

    def read(name)
      File.read(File.join(PUBLIC, name), encoding: "UTF-8")
    end

    def app
      @app ||= API::App.new(config: API::Config.new(rate_limit_per_minute: 0))
    end

    def referenced_files
      read("index.html").scan(/\b(?:src|href)="([^"#][^"]*)"/).flatten.reject { |ref| ref.start_with?("/", ".") }
    end

    def dictionaries
      json = read("app.js")[%r{/\* i18n:start \*/(.*?)/\* i18n:end \*/}m, 1]
      JSON.parse(json)
    end

    # app.js without its dictionaries: the code that asks for texts.
    def script_code
      read("app.js").sub(%r{/\* i18n:start \*/.*?/\* i18n:end \*/}m, "")
    end

    # The ids of the tools, in the order of the tool pills.
    def tool_ids
      read("app.js")[/const TAB_IDS = \[(.*?)\]/m, 1].scan(/'(\w+)'/).flatten
    end

    def test_the_page_references_only_files_that_exist
      refute_empty referenced_files
      referenced_files.each { |ref| assert_path_exists File.join(PUBLIC, ref), "index.html points at #{ref}" }
      assert_includes referenced_files, "aurora.css"
      assert_includes referenced_files, "aurora.js"
      assert_includes referenced_files, "app.js"
    end

    def test_nothing_is_loaded_from_another_origin
      OWN_FILES.each do |name|
        assert_empty read(name).scan(%r{(?:https?:)?//[a-z0-9.-]+\.[a-z]{2,}[/"')\s]}i), "#{name} mentions another origin"
      end
      refute_match(/@import|@font-face|url\(\s*["']?https?:/i, read("app.css"))
    end

    def test_no_inline_script_style_or_handler
      html = read("index.html")
      refute_match(/<style/i, html)
      refute_match(/\sstyle\s*=/i, html)
      refute_match(/\son[a-z]+\s*=/i, html, "inline event handlers are blocked by the policy")
      html.scan(/<script\b[^>]*>/i).each { |tag| assert_match(/\bsrc=/, tag, "inline script: #{tag}") }
    end

    def test_the_script_never_turns_data_into_markup_or_code
      js = read("app.js")
      %w[innerHTML outerHTML insertAdjacentHTML document.write eval( new\ Function setAttribute('style' ].each do |pattern|
        refute_includes js, pattern, "app.js must not use #{pattern}"
      end
      refute_match(/set(Timeout|Interval)\(\s*["'`]/, js, "string timers evaluate code")
    end

    def test_the_stylesheet_and_the_script_use_tokens_not_colour_literals
      css = read("app.css")
      refute_match(/#[0-9a-f]{3,8}\b/i, css)
      refute_match(/\b(?:rgb|rgba|hsl|hsla)\(/i, css)
      refute_match(/font-family:\s*["'][^v]/, css, "only the --font-* tokens")
      refute_match(/#[0-9a-f]{3,8}\b/i, script_code, "app.js must not carry colours")
      refute_match(/\b(?:rgb|rgba|hsl|hsla)\(/i, script_code, "app.js must not carry colours")
    end

    def test_every_file_of_the_page_is_served_with_the_right_type_and_policy
      { "/" => "text/html", "/index.html" => "text/html", "/app.css" => "text/css", "/aurora.css" => "text/css",
        "/app.js" => "text/javascript", "/aurora.js" => "text/javascript",
        "/favicon.svg" => "image/svg+xml" }.each do |path, type|
        reply = request(app, :get, path)
        assert_equal 200, reply.status, path
        assert reply.header("content-type").start_with?(type), "#{path}: #{reply.header('content-type')}"
      end
      policy = request(app, :get, "/").header("content-security-policy")
      assert_includes policy, "script-src 'self'"
      assert_includes policy, "style-src 'self'"
      assert_includes policy, "connect-src 'self'"
    end

    def test_both_languages_have_the_same_keys_and_placeholders
      pt = dictionaries.fetch("pt")
      en = dictionaries.fetch("en")
      assert_empty pt.keys - en.keys, "missing from English"
      assert_empty en.keys - pt.keys, "missing from Portuguese"
      placeholders = ->(text) { text.scan(/\{(\w+)\}/).flatten.sort }
      pt.each { |key, text| assert_equal placeholders.call(text), placeholders.call(en.fetch(key)), "placeholders of #{key}" }
      pt.each_value { |text| refute_empty text.strip }
    end

    # The page is built by the shell, so its texts are named in the script, not in the HTML: every key the code asks
    # for (written out, or as the prefix of a computed key) must exist in the dictionary.
    def test_every_text_the_script_asks_for_exists
      pt = dictionaries.fetch("pt")
      namespaces = pt.keys.map { |key| key.split(".").first }.uniq
      literals = script_code.scan(/'([a-z]+(?:\.[A-Za-z0-9]+)+)'/).flatten
      literals = literals.select { |key| namespaces.include?(key.split(".").first) }
      refute_empty literals
      literals.each { |key| assert pt.key?(key), "app.js asks for the missing text #{key}" }

      prefixes = script_code.scan(/`([a-z]+(?:\.[a-z]+)*)\.\$\{/).flatten
      refute_empty prefixes
      prefixes.each do |prefix|
        assert(pt.keys.any? { |key| key.start_with?("#{prefix}.") }, "no text starts with #{prefix}.")
      end
    end

    def test_the_page_starts_in_portuguese_and_its_title_matches_the_dictionary
      html = read("index.html")
      assert_match(/<html lang="pt-BR"/, html)
      assert_equal dictionaries.fetch("pt").fetch("app.title"), html[%r{<title>(.*?)</title>}, 1]
    end

    def test_the_html_is_an_empty_page_for_the_shell_to_fill
      html = read("index.html")
      refute_match(/<(header|main|nav|footer)\b/, html, "the rail, bars and status bar are built by Aurora.shell")
      assert_includes script_code, "Aurora.shell("
      assert_includes html, "<noscript>"
    end

    def test_every_tool_has_its_texts_in_both_languages
      assert_equal %w[cpf cnpj pix card plate phone cep fake], tool_ids
      dictionaries.each_value do |texts|
        tool_ids.each { |id| %W[tab.#{id} algo.#{id}].each { |key| assert texts.key?(key), "missing #{key}" } }
      end
    end

    # Texts under "aurora." replace the UI kit's built-in labels (palette, tables, theme toggle, landmarks) when the
    # language changes; a key the kit does not know would silently do nothing.
    def test_the_kit_labels_in_the_dictionary_are_labels_the_kit_has
      kit_keys = read("aurora.js")[/const STR = \{(.*?)\n  \};/m, 1].scan(/'([A-Za-z]+\.[A-Za-z]+)':/).flatten
      refute_empty kit_keys
      dictionaries.each_value do |texts|
        texts.each_key do |key|
          next unless key.start_with?("aurora.")

          assert_includes kit_keys, key.delete_prefix("aurora."), "#{key} is not a label of the kit"
        end
      end
    end

    def test_the_bundled_ui_kit_is_present_and_its_unused_charts_module_is_not_shipped
      assert_path_exists File.join(PUBLIC, "aurora.css")
      assert_path_exists File.join(PUBLIC, "aurora.js")
      refute_includes read("index.html"), "aurora-charts.js", "the charts module is not used, so it is not shipped"
      refute_path_exists File.join(PUBLIC, "aurora-charts.js")
    end
  end
end
