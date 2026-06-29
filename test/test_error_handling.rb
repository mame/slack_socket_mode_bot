require_relative "helper"

# Error and edge-case handling in the message loop
class ErrorHandlingTest < BotTest
  def test_hello_is_logged
    log = CaptureLogger.new
    connect(logger: log)
    @slack.deliver({ type: "hello" })
    pump
    assert log.infos.any? { |l| l.include?("hello") }
  end

  def test_disconnect_is_logged
    log = CaptureLogger.new
    connect(logger: log)
    @slack.deliver({ type: "disconnect" })
    pump
    assert log.infos.any? { |l| l.include?("disconnect") }
  end

  def test_non_json_message_is_ignored
    log = CaptureLogger.new
    connect(logger: log)
    @slack.deliver_raw("this is not json")
    pump
    assert log.warns.any? { |l| l.include?("non-JSON") }
    assert_empty @calls
  end

  def test_close_frame_is_logged
    log = CaptureLogger.new
    connect(logger: log)
    @slack.send_close
    pump
    assert log.infos.any? { |l| l.include?("websocket closed") }
  end

  # #run drives #step in a loop until something raises
  def test_run_loops_over_step_until_it_raises
    connect
    r, w = IO.pipe
    w.write("x") # keep the readable set non-empty so IO.select returns at once
    n = 0
    @bot.define_singleton_method(:step) do
      n += 1
      raise "stop" if n >= 3
      [[r], []]
    end
    assert_raises(RuntimeError) { @bot.run }
    assert_equal 3, n
  ensure
    r&.close
    w&.close
  end
end
