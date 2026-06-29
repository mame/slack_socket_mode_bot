require "minitest/autorun"
require "json"
require "socket"
require "slack_socket_mode_bot"

# Point the Web API at an unroutable host so a missed stub never reaches Slack
SlackSocketModeBot.send(:remove_const, :API_BASE)
SlackSocketModeBot::API_BASE = "https://slack.invalid/api/"

# Real SimpleWebSocket over a socketpair, with only the transport and Web API stubbed

class CaptureLogger
  attr_reader :infos, :warns
  def initialize
    @infos = []
    @warns = []
  end
  def info(line) = @infos << line
  def warn(line) = @warns << line
  def debug(*); end
end

# Stub apps.connections.open so #initialize makes no HTTP call
class TestBot < SlackSocketModeBot
  def call(*) = { url: "wss://slack.invalid/ws" }
end

# The Slack side of one connection
class FakeSlack
  def initialize(server)
    @server = server
    @acks = []
  end

  def handshake
    hs = WebSocket::Handshake::Server.new
    hs << @server.readpartial(4096)
    @server.write(hs.to_s)
    @version = hs.version
    @incoming = WebSocket::Frame::Incoming::Server.new(version: @version)
  end

  def deliver(obj)
    @server.write(WebSocket::Frame::Outgoing::Server.new(version: @version, data: JSON.generate(obj), type: :text).to_s)
  end

  # Send a frame whose payload is not valid JSON
  def deliver_raw(text)
    @server.write(WebSocket::Frame::Outgoing::Server.new(version: @version, data: text, type: :text).to_s)
  end

  def send_close
    @server.write(WebSocket::Frame::Outgoing::Server.new(version: @version, data: "", type: :close).to_s)
  end

  # Every ACK received so far, decoded
  def acks
    while (buf = @server.read_nonblock(4096, exception: false)) && buf != :wait_readable
      @incoming << buf
      while (frame = @incoming.next)
        @acks << JSON.parse(frame.data, symbolize_names: true)
      end
    end
    @acks
  end
end

class BotTest < Minitest::Test
  def teardown
    @pairs&.each { |c, s| c.close rescue nil; s.close rescue nil }
  end

  # Connect a bot with `num` socketpair connections, recording handler calls into @calls
  def connect(num: 1, logger: nil)
    @pairs = Array.new(num) { UNIXSocket.pair }
    clients = @pairs.map { |c, _| c.define_singleton_method(:connect) { nil }; c }
    @calls = []
    handler = ->(json) { @calls << json; { text: "hi" } }

    with_stubbed_transport(clients) do
      @bot = TestBot.new(token: "xoxb", app_token: "xapp", num_of_connections: num, logger: logger, &handler)
    end

    @slacks = @pairs.map { |_, server| FakeSlack.new(server) }
    pump
    @slacks.each(&:handshake)
    pump
    @slack = @slacks.first
    @bot
  end

  def pump(n = 4) = n.times { @bot.step }

  private def with_stubbed_transport(clients)
    orig_tcp = TCPSocket.method(:new)
    orig_ssl = OpenSSL::SSL::SSLSocket.method(:new)
    TCPSocket.define_singleton_method(:new) { |*| :unused }
    OpenSSL::SSL::SSLSocket.define_singleton_method(:new) { |*| clients.shift }
    yield
  ensure
    TCPSocket.define_singleton_method(:new, orig_tcp)
    OpenSSL::SSL::SSLSocket.define_singleton_method(:new, orig_ssl)
  end
end
