require_relative "helper"

# Connection setup and count maintenance
class ConnectionsTest < BotTest
  def test_no_connections_without_app_token
    bot = TestBot.new(token: "xoxb")
    assert_empty bot.instance_variable_get(:@conns)
  end

  def test_opens_num_of_connections_with_app_token
    connect(num: 3)
    assert_equal 3, @bot.instance_variable_get(:@conns).size
  end

  # Drive #replenish_connections with add_connection stubbed
  def reconnect_bot(target:, conns: [], logger: nil)
    bot = TestBot.new(token: "xoxb", logger: logger)
    bot.instance_variable_set(:@num_of_connections, target)
    bot.instance_variable_set(:@conns, conns)
    bot
  end

  # Reopen connections up to the target count
  def test_self_heals_up_to_target
    bot = reconnect_bot(target: 3)
    bot.define_singleton_method(:add_connection) { |_cb| @conns << Object.new }
    bot.send(:replenish_connections)
    assert_equal 3, bot.instance_variable_get(:@conns).size
  end

  # Tolerate a single reopen failure when other connections survive
  def test_tolerates_single_failure_when_survivors_exist
    log = CaptureLogger.new
    bot = reconnect_bot(target: 4, conns: [Object.new], logger: log)
    bot.define_singleton_method(:add_connection) { |_cb| raise "boom" }
    bot.send(:replenish_connections)
    assert_equal 1, log.warns.size
  end

  # Fail loud when every connection is lost
  def test_raises_when_every_connection_is_lost
    bot = reconnect_bot(target: 4, conns: [], logger: CaptureLogger.new)
    bot.define_singleton_method(:add_connection) { |_cb| raise "boom" }
    assert_raises(SlackSocketModeBot::Error) { bot.send(:replenish_connections) }
  end
end
