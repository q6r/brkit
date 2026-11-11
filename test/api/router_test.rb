# frozen_string_literal: true

require_relative "../test_helper"
require "brkit/api"

module Brkit
  module API
    class RouterTest < Minitest::Test
      def router
        Router.new
      end

      def add_get(target, path = "/a", operation_id: "getA")
        target.get(path, operation_id: operation_id, summary: "s", tag: "T", response: :result) { |_context| { ok: true } }
      end

      def test_registers_and_finds_routes
        table = router
        route = add_get(table)
        assert_equal "GET", route.verb
        assert_same route, table.lookup("/a")["GET"]
        assert_nil table.lookup("/missing")
        assert_equal [route], table.routes
        assert_equal({ ok: true }, route.handler.call(nil))
      end

      def test_post_routes_carry_their_body_declaration
        table = router
        body = [Params.string(:key, required: true)]
        route = table.post("/p", operation_id: "p", summary: "s", tag: "T", response: :result, body: body) { |_c| {} }
        assert_equal "POST", route.verb
        assert_equal body, route.body
        assert_predicate route.body, :frozen?
        assert_predicate route.params, :frozen?
      end

      def test_one_path_can_have_several_methods
        table = router
        add_get(table, "/x", operation_id: "getX")
        table.post("/x", operation_id: "postX", summary: "s", tag: "T", response: :result) { |_c| {} }
        assert_equal %w[GET POST], table.lookup("/x").keys.sort
      end

      def test_duplicates_are_refused
        table = router
        add_get(table)
        assert_raises(ArgumentError) { add_get(table, "/a", operation_id: "other") }
        error = assert_raises(ArgumentError) { add_get(table, "/b", operation_id: "getA") }
        assert_includes error.message, "duplicate operation id"
      end

      def test_allowed_methods
        table = router
        add_get(table, "/g", operation_id: "g")
        table.post("/p", operation_id: "p", summary: "s", tag: "T", response: :result) { |_c| {} }
        assert_equal %w[GET HEAD OPTIONS], table.allowed_methods("/g")
        assert_equal %w[OPTIONS POST], table.allowed_methods("/p")
        assert_equal %w[OPTIONS], table.allowed_methods("/nothing")
      end

      def test_context_is_a_plain_value
        context = Context.new(params: { a: 1 }, body: { b: 2 }, request: :req)
        assert_equal [{ a: 1 }, { b: 2 }, :req], [context.params, context.body, context.request]
      end
    end
  end
end
