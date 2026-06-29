require_relative "helper"
require "socket"

# The real SimpleWebSocket over a socketpair, with only the transport constructors stubbed
class SimpleWebSocketTest < Minitest::Test
  SWS = SlackSocketModeBot::SimpleWebSocket

  def setup
    @client, @server = UNIXSocket.pair
    @client.define_singleton_method(:connect) { nil }
    @events = []
    @ws = build_ws
    # complete the opening handshake
    @ws.step([], [])
    @hs = WebSocket::Handshake::Server.new
    @hs << @server.readpartial(4096)
    @server.write(@hs.to_s)
    @ws.step([], [])
  end

  def teardown
    @client.close rescue nil
    @server.close rescue nil
  end

  # Build a SimpleWebSocket on our socketpair end
  def build_ws
    orig_tcp = TCPSocket.method(:new)
    orig_ssl = OpenSSL::SSL::SSLSocket.method(:new)
    TCPSocket.define_singleton_method(:new) { |*| :unused }
    client = @client
    OpenSSL::SSL::SSLSocket.define_singleton_method(:new) { |*| client }
    SWS.new("wss://slack.invalid/ws") { |*a| @events << a }
  ensure
    TCPSocket.define_singleton_method(:new, orig_tcp)
    OpenSSL::SSL::SSLSocket.define_singleton_method(:new, orig_ssl)
  end

  def server_send(data, type: :text)
    @server.write(WebSocket::Frame::Outgoing::Server.new(version: @hs.version, data: data, type: type).to_s)
  end

  # Read one frame the client sent
  def read_frame
    incoming = WebSocket::Frame::Incoming::Server.new(version: @hs.version)
    incoming << @server.readpartial(4096)
    incoming.next
  end

  def test_handshake_yields_open
    assert_includes @events, [:open]
  end

  def test_incoming_text_message_is_yielded
    server_send('{"hello":1}')
    @ws.step([], [])
    assert_includes @events, [:message, '{"hello":1}', :text]
  end

  def test_outgoing_message_is_framed_on_the_wire
    @ws.send('{"ack":1}')
    @ws.step([], []) # flush the buffered frame
    msg = read_frame
    assert_equal :text, msg.type
    assert_equal '{"ack":1}', msg.data
  end

  def test_ping_is_answered_with_pong
    server_send("hi", type: :ping)
    @ws.step([], []) # read ping -> a pong is buffered
    @ws.step([], []) # flush the pong
    assert_equal :pong, read_frame.type
  end

  def test_close_frame_is_yielded
    server_send("", type: :close)
    @ws.step([], [])
    assert @events.any? { |e| e[0] == :close }
  end
end
