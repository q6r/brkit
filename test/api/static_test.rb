# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/rack_helpers"
require_relative "../support/static_fixture"
require "brkit/api"

module Brkit
  module API
    class StaticTest < Minitest::Test
      include StaticFixture

      def setup
        build_fixture
      end

      def teardown
        remove_fixture
      end

      def app
        @app ||= App.new(config: Config.new(rate_limit_per_minute: 0), public_dir: public_root)
      end

      def get(path, headers: {})
        request(app, :get, path, headers: headers)
      end

      def static_request(path)
        Request.new(env_for("GET", path))
      end

      def test_the_root_serves_the_index_with_a_strict_policy
        reply = get("/")
        assert_equal 200, reply.status
        assert_equal StaticFixture::INDEX, reply.body
        assert_equal "text/html; charset=utf-8", reply.header("content-type")
        assert_equal "no-cache", reply.header("cache-control")
        policy = reply.header("content-security-policy")
        ["default-src 'self'", "script-src 'self'", "style-src 'self'", "object-src 'none'",
         "frame-ancestors 'none'"].each { |directive| assert_includes policy, directive }
        refute_includes policy, "unsafe-inline"
        assert_equal "DENY", reply.header("x-frame-options")
        assert_equal "nosniff", reply.header("x-content-type-options")
      end

      def test_content_types_follow_the_extension
        { "/app.css" => "text/css; charset=utf-8", "/app.js" => "text/javascript; charset=utf-8",
          "/data.json" => "application/json", "/notes.txt" => "text/plain; charset=utf-8",
          "/mystery.xyz" => "application/octet-stream", "/UPPER.CSS" => "text/css; charset=utf-8",
          "/logo.svg" => "image/svg+xml" }.each do |path, type|
          assert_equal type, get(path).header("content-type"), path
        end
      end

      def test_assets_are_cached_and_html_must_revalidate
        assert_equal "public, max-age=3600", get("/app.js").header("cache-control")
        assert_equal "no-cache", get("/sub/page.html").header("cache-control")
        refute get("/app.js").headers.key?("content-security-policy"), "only documents carry the page policy"
      end

      def test_svg_files_are_sandboxed
        policy = get("/logo.svg").header("content-security-policy")
        assert_includes policy, "default-src 'none'"
        assert_includes policy, "sandbox"
      end

      def test_directories_serve_their_index_but_are_never_listed
        assert_includes get("/sub/").body, "<title>sub</title>"
        assert_equal 404, get("/sub").status
        assert_equal 404, get("/nothing/").status
      end

      def test_missing_files_are_problem_documents
        reply = get("/missing.css")
        assert_equal 404, reply.status
        assert_predicate reply, :problem?
      end

      def test_conditional_requests
        first = get("/app.css")
        etag = first.header("etag")
        assert_match(/\A"[0-9a-f]+-[0-9a-f]+"\z/, etag)
        assert_match(/\A\w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} GMT\z/, first.header("last-modified"))

        cached = get("/app.css", headers: { "If-None-Match" => etag })
        assert_equal 304, cached.status
        assert_empty cached.body
        assert_equal etag, cached.header("etag")

        assert_equal 304, get("/app.css", headers: { "If-None-Match" => "W/#{etag}" }).status
        assert_equal 304, get("/app.css", headers: { "If-None-Match" => "\"x\", #{etag}" }).status
        assert_equal 304, get("/app.css", headers: { "If-None-Match" => "*" }).status
        assert_equal 200, get("/app.css", headers: { "If-None-Match" => "\"other\"" }).status
        assert_equal 304, get("/app.css", headers: { "If-Modified-Since" => first.header("last-modified") }).status
        assert_equal 200, get("/app.css", headers: { "If-Modified-Since" => "not a date" }).status
      end

      def test_if_none_match_wins_over_if_modified_since
        future = (Time.now + 86_400).httpdate
        reply = get("/app.css", headers: { "If-None-Match" => "\"stale\"", "If-Modified-Since" => future })
        assert_equal 200, reply.status
      end

      def test_head_has_the_headers_but_no_body
        reply = request(app, :head, "/app.css")
        assert_equal 200, reply.status
        assert_empty reply.body
        assert_equal File.size(File.join(public_root, "app.css")).to_s, reply.header("content-length")
      end

      def test_other_methods_are_refused_on_static_paths
        post = request(app, :post, "/app.css")
        assert_equal 405, post.status
        assert_equal "GET, HEAD, OPTIONS", post.header("allow")
        assert_equal "GET, HEAD, OPTIONS", request(app, :options, "/app.css").header("allow")
      end

      def test_traversal_hidden_files_and_odd_segments_never_resolve
        ["/../secret.txt", "/%2e%2e/secret.txt", "/sub/../../secret.txt", "/..%2fsecret.txt", "/sub/..%2f..%2fsecret.txt",
         "/.hidden", "/.git/config", "/sub/.%2e/secret.txt", "/%2e/app.css", "/a b", "/-x", "/app.css%00", "/app.css/",
         "//app.css", "/#{'a' * 101}", "/\\..\\secret.txt", "/app.css;x"].each do |path|
          reply = get(path)
          assert_includes [400, 404], reply.status, path
          refute_includes reply.body, StaticFixture::SECRET, path
        end
      end

      def test_a_symbolic_link_cannot_leave_the_root
        link = File.join(public_root, "escape.txt")
        begin
          File.symlink(File.join(tmp_root, "secret.txt"), link)
        rescue NotImplementedError, SystemCallError
          skip "symbolic links are unavailable here"
        end
        track_for_cleanup(link)

        reply = get("/escape.txt")
        assert_equal 404, reply.status
        refute_includes reply.body, StaticFixture::SECRET
      end

      def test_files_over_the_limit_are_not_served
        static = Static.new(root: public_root, max_bytes: 10)
        assert_nil static.call(static_request("/app.js"))
        assert_nil static.call(static_request("/index.html"))
        assert static.call(static_request("/data.json")), "a file under the limit is served"
      end

      def test_a_missing_root_serves_nothing_but_the_api_still_works
        bare = App.new(config: Config.new(rate_limit_per_minute: 0), public_dir: File.join(tmp_root, "nowhere"))
        assert_equal 404, request(bare, :get, "/").status
        assert_equal 200, request(bare, :get, "/healthz").status
        assert_nil Static.new(root: File.join(tmp_root, "nowhere")).root
      end

      def test_locate_maps_only_regular_files_inside_the_root
        static = Static.new(root: public_root)
        assert_equal File.join(static.root, "app.css"), static.locate("/app.css")
        assert_equal File.join(static.root, "sub", "index.html"), static.locate("/sub/")
        assert_nil static.locate("/sub")
        assert_nil static.locate("/../secret.txt")
        assert_nil static.locate("/.hidden")
      end

      def test_static_files_do_not_spend_the_api_rate_limit
        limited = App.new(config: Config.new(rate_limit_per_minute: 60, rate_burst: 1), public_dir: public_root,
                          clock: -> { 1.0 })
        5.times { assert_equal 200, request(limited, :get, "/app.css").status }
        assert_equal 200, request(limited, :get, "/api/v1/cpf/generate").status
        assert_equal 429, request(limited, :get, "/api/v1/cpf/generate").status
        assert_equal 200, request(limited, :get, "/").status, "the page itself still loads"
      end

      def test_unknown_api_paths_stay_json_problems
        reply = get("/api/v1/nothing")
        assert_equal 404, reply.status
        assert_predicate reply, :problem?
      end
    end
  end
end
