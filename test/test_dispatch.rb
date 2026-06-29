require_relative "helper"

# Message dispatch across types, through the real SimpleWebSocket
class DispatchTest < BotTest
  def events_msg(event_id:, envelope_id:, accepts: false)
    { type: "events_api", envelope_id: envelope_id, retry_attempt: 0,
      accepts_response_payload: accepts,
      payload: { type: "event_callback", event_id: event_id, event_time: Time.now.to_i,
                 event: { type: "app_mention" } } }
  end

  def slash_msg(command:, envelope_id:)
    { type: "slash_commands", envelope_id: envelope_id, accepts_response_payload: true,
      payload: { command: command, text: "" } }
  end

  def test_event_runs_handler_and_acks
    connect(logger: CaptureLogger.new)
    @slack.deliver(events_msg(event_id: "Ev1", envelope_id: "e1"))
    pump
    assert_equal 1, @calls.size
    assert_equal [{ envelope_id: "e1" }], @slack.acks
  end

  def test_response_payload_returned_when_accepted
    connect
    @slack.deliver(events_msg(event_id: "Ev1", envelope_id: "e1", accepts: true))
    pump
    assert_equal [{ envelope_id: "e1", payload: { text: "hi" } }], @slack.acks
  end

  def test_duplicate_event_id_is_not_reprocessed
    connect
    @slack.deliver(events_msg(event_id: "Ev1", envelope_id: "e1"))
    pump
    @slack.deliver(events_msg(event_id: "Ev1", envelope_id: "e2"))
    pump
    assert_equal 1, @calls.size
  end

  # The logger must not assume every message has an event_id
  def test_slash_command_with_logger_does_not_crash
    connect(logger: CaptureLogger.new)
    @slack.deliver(slash_msg(command: "/x", envelope_id: "e1"))
    pump
    assert_equal 1, @calls.size
    assert_equal [{ envelope_id: "e1", payload: { text: "hi" } }], @slack.acks
  end
end
