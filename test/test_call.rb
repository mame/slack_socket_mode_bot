require_relative "helper"

# The Web API wrapper #call, with Net::HTTP.post stubbed
class CallTest < Minitest::Test
  def res(klass, body: "{}", headers: {})
    r = klass.allocate
    r.instance_variable_set(:@header, headers.transform_values { |v| Array(v) })
    r.define_singleton_method(:body) { body }
    r
  end

  # No app_token means no connections, and we capture #sleep
  def build_bot
    bot = SlackSocketModeBot.new(token: "xoxb")
    sleeps = (@sleeps = [])
    bot.define_singleton_method(:sleep) { |s| sleeps << s }
    bot
  end

  def stub_post(callable)
    orig = Net::HTTP.method(:post)
    Net::HTTP.define_singleton_method(:post) { |*a, **k| callable.call(*a, **k) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:post, orig)
  end

  def test_success_returns_parsed_json
    bot = build_bot
    stub_post(->(*) { res(Net::HTTPOK, body: '{"ok":true,"channel":"C1"}') }) do
      assert_equal({ ok: true, channel: "C1" }, bot.call("chat.postMessage", {}))
    end
  end

  def test_ok_false_raises_error_with_message
    bot = build_bot
    stub_post(->(*) { res(Net::HTTPOK, body: '{"ok":false,"error":"not_in_channel"}') }) do
      e = assert_raises(SlackSocketModeBot::Error) { bot.call("chat.postMessage", {}) }
      assert_equal "not_in_channel", e.message
    end
  end

  def test_dns_failure_retries_three_times_then_raises
    bot = build_bot
    calls = 0
    stub_post(->(*) { calls += 1; raise Socket::ResolutionError, "dns" }) do
      assert_raises(Socket::ResolutionError) { bot.call("x", {}) }
    end
    assert_equal 3, calls
  end
end
