require_relative "helper"

# Connection setup
class ConnectionsTest < BotTest
  def test_no_connections_without_app_token
    bot = TestBot.new(token: "xoxb") # no app_token -> opens nothing
    assert_empty bot.instance_variable_get(:@conns)
  end

  def test_opens_num_of_connections_with_app_token
    connect(num: 3)
    assert_equal 3, @bot.instance_variable_get(:@conns).size
  end
end
