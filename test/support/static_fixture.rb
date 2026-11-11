# frozen_string_literal: true

require "tmpdir"

module Brkit
  # Builds a throw-away directory tree for the static-file tests:
  #
  #   <tmp>/secret.txt          outside the served root; must never be reachable
  #   <tmp>/public/...          the served root
  #
  # Files are removed one by one (not with FileUtils.remove_entry) so it also works in restricted runtimes where
  # directories cannot be listed.
  module StaticFixture
    SECRET = "TOP-SECRET-DO-NOT-SERVE"
    INDEX = "<!doctype html><title>home</title><p>hello</p>\n"

    # name => content, relative to the public directory
    FILES = {
      "index.html" => INDEX,
      "app.css" => "body { color: black; }\n",
      "app.js" => "console.log('hi');\n",
      "logo.svg" => "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>\n",
      "data.json" => "{\"a\":1}\n",
      "notes.txt" => "plain notes\n",
      "mystery.xyz" => "unknown type\n",
      "UPPER.CSS" => "a {}\n",
      "sub/index.html" => "<!doctype html><title>sub</title>\n",
      "sub/page.html" => "<!doctype html><title>page</title>\n",
      ".hidden" => "hidden file\n",
      ".git/config" => "[core]\n"
    }.freeze

    attr_reader :tmp_root, :public_root

    # Creates the tree; call {#remove_fixture} in teardown.
    def build_fixture(extra: {})
      @tmp_root = Dir.mktmpdir("brkit-static")
      @public_root = File.join(@tmp_root, "public")
      @created = []
      write_file(File.join(@tmp_root, "secret.txt"), SECRET)
      Dir.mkdir(@public_root)
      @created << [:dir, @public_root]
      FILES.merge(extra).each { |name, content| write_file(File.join(@public_root, name), content) }
    end

    def write_file(path, content)
      make_directories(File.dirname(path))
      File.binwrite(path, content)
      @created << [:file, path]
    end

    def make_directories(path)
      return if File.directory?(path) || path == @tmp_root

      make_directories(File.dirname(path))
      Dir.mkdir(path)
      @created << [:dir, path]
    end

    # Registers an extra path for cleanup (for example a symbolic link made by a test).
    def track_for_cleanup(path)
      @created << [:file, path]
    end

    def remove_fixture
      return unless @tmp_root

      @created.reverse_each do |kind, path|
        kind == :dir ? Dir.rmdir(path) : File.delete(path)
      rescue SystemCallError
        nil # best effort: a test may already have removed it, and the OS clears the temp directory anyway
      end
      Dir.rmdir(@tmp_root)
    rescue SystemCallError
      nil
    end
  end
end
