require "test_helper"

class GlobalKamalTest < ActiveSupport::TestCase
  setup { @resolver = GlobalKamal.resolver; GlobalKamal.reset }
  teardown { GlobalKamal.resolver = @resolver; GlobalKamal.reset }

  test "resolves kamal from the home folder, so a repo's own bin/kamal can't shadow it" do
    calls = []
    GlobalKamal.resolver = ->(dir) { calls << dir; "/opt/ruby/bin/kamal\n" }

    assert_equal "/opt/ruby/bin/kamal", GlobalKamal.path
    assert_equal "/opt/ruby/bin/kamal", GlobalKamal.path
    assert_equal [ Dir.home ], calls, "looked up once, from the home folder"
  end

  test "refuses anything but an absolute path, so a bare name never reaches PATH lookup in a repo" do
    [ nil, "", "kamal\n", "bin/kamal\n" ].each do |answer|
      GlobalKamal.reset
      GlobalKamal.resolver = ->(_dir) { answer }

      assert_raises(GlobalKamal::NotFound) { GlobalKamal.path }
    end
  end
end
