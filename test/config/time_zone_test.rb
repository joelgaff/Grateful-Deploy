require "test_helper"

class TimeZoneTest < ActiveSupport::TestCase
  test "times show in the laptop's time zone, not UTC" do
    laptop_zone = File.readlink("/etc/localtime").split("zoneinfo/").last

    assert_equal laptop_zone, Time.zone.tzinfo.name
  end
end
