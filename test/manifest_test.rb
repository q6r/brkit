# frozen_string_literal: true

require_relative "test_helper"

module Brkit
  # Guards test/all.rb, whose explicit list exists for sandboxes that cannot list directories.
  class ManifestTest < Minitest::Test
    def test_all_rb_lists_every_test_file
      root = File.expand_path(__dir__)
      on_disk = Dir.glob(File.join(root, "**", "*_test.rb")).map { |path| path.delete_prefix("#{root}/").delete_suffix(".rb") }
      listed = File.read(File.join(root, "all.rb"))[/%w\[(.*?)\]/m, 1].split

      assert_equal on_disk.sort, listed.sort
      assert_equal listed.uniq, listed, "all.rb lists a file twice"
    rescue NotImplementedError, SystemCallError => e
      skip "directory listing is unavailable in this environment (#{e.class})"
    end
  end
end
