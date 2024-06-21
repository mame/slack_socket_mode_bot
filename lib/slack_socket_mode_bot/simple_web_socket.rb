class SlackSocketModeBot::SimpleWebSocket
  def initialize(url)
    uri = URI.parse(url)

    unless uri.scheme == "https" || uri.scheme == "wss"
      raise "unexpected scheme (not secure?): #{ uri.scheme }"
    end

    ctx = OpenSSL::SSL::SSLContext.new
    ctx.ssl_version = "SSLv23"
    ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    ctx.cert_store = OpenSSL::X509::Store.new
    ctx.cert_store.set_default_paths

    count = 0
    begin
      io = TCPSocket.new(uri.host, uri.port || 443)
      @io = OpenSSL::SSL::SSLSocket.new(io, ctx)
      @io.connect
    rescue Socket::ResolutionError
      sleep 1
      count += 1
      retry if count < 3
      raise
    end

    @version = nil

    @fib = Fiber.new do
      closed = false
      begin
        handshake = WebSocket::Handshake::Client.new(url: url)
        @write_buff = handshake.to_s.dup
        handshake << Fiber.yield until handshake.finished?

        @version = handshake.version
        yield :open

        frame = WebSocket::Frame::Incoming::Client.new
        frame << handshake.leftovers
        while true
          while msg = frame.next
            case msg.type
            when :close
              yield :close unless closed
              closed = true
            when :ping
              send(msg.data, type: :pong)
            when :pong
            when :text
              yield :message, msg.data, :text
            when :binary
              yield :message, msg.data, :binary
            end
          end
          frame << Fiber.yield
        end
      rescue EOFError
      ensure
        yield :close unless closed
        @io.close
      end
    end

    @fib.resume
  end

  def send(data, type: :text, code: nil)
    raise "not opened yet" unless @version
    frame = WebSocket::Frame::Outgoing::Client.new(version: @version, data: data, type: type, code: code)
    @write_buff << frame.to_s
  end

  def close(code: 1000, reason: "")
    send(reason, type: :close, code: code) unless @io.closed?
  end

  def step(read_ios, write_ios)
    wait_readable = wait_writable = false

    unless @write_buff.empty?
      len = @io.write_nonblock(@write_buff, exception: false)
      case len
      when :wait_readable then wait_readable = true
      when :wait_writable then wait_writable = true
      else
        @write_buff.clear
      end
    end

    while true
      read_buff = @io.read_nonblock(4096, exception: false)
      case read_buff
      when :wait_readable then wait_readable = true; break
      when :wait_writable then wait_writable = true; break
      when nil
        raise Errno::EPIPE
      else
        @fib.resume(read_buff)
      end
    end

    read_ios << @io if wait_readable
    write_ios << @io if wait_writable
    return true

  rescue Errno::EPIPE, Errno::ECONNRESET
    begin
      @fib.raise(EOFError)
    rescue FiberError
    end
    return false
  end
end
