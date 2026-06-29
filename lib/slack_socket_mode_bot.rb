# frozen_string_literal: true

require "uri"
require "net/http"
require "openssl"
require "websocket"
require "json"

require_relative "slack_socket_mode_bot/version"
require_relative "slack_socket_mode_bot/simple_web_socket"

class SlackSocketModeBot
  class Error < StandardError; end

  API_BASE = "https://slack.com/api/"

  # Internal signal: retry after `wait` seconds. Always caught in #call.
  class Retry < StandardError
    attr_reader :wait
    def initialize(wait)
      @wait = wait
      super("retry after #{ wait }s")
    end
  end
  private_constant :Retry

  # Max seconds to sleep on a 429 Retry-After; #call may run in the event loop.
  RETRY_AFTER_CAP = 60

  #: (token: String, ?app_token: String, ?num_of_connections: Integer, ?debug: boolean, ?logger: Logger) { (untyped) -> untyped } -> void
  def initialize(token:, app_token: nil, num_of_connections: 4, debug: false, logger: nil, &callback)
    @token = token
    @app_token = app_token
    @conns = []
    @debug = debug
    @logger = logger
    @events = {}
    @callback = callback
    # No app token: Web API calls only, no Socket Mode connections.
    @num_of_connections = app_token ? num_of_connections : 0
    replenish_connections
  end

  #: (String method, untyped data, ?token: String) -> untyped
  def call(method, data, token: @token)
    url = URI(API_BASE + method)
    body = JSON.generate(data)
    headers = {
      "Content-type" => "application/json; charset=utf-8",
      "Authorization" => "Bearer " + token,
    }

    retries = 0
    begin
      res = Net::HTTP.post(url, body, headers)

      case res
      when Net::HTTPSuccess
        json = JSON.parse(res.body, symbolize_names: true)
        raise Error, json[:error] unless json[:ok]
        json
      when Net::HTTPTooManyRequests
        # Rejected, not processed: safe to retry after Retry-After seconds.
        raise Retry, Integer(res["retry-after"] || retries + 1)
      else
        # 5xx etc.: may already be processed, so don't retry; just don't crash.
        raise Error, "HTTP #{ res.code } #{ res.message }"
      end
    rescue Socket::ResolutionError, Net::OpenTimeout
      # Never sent (DNS / connect failure): safe to retry.
      retries += 1
      raise if retries >= 3
      sleep 1
      retry
    rescue Retry => e
      # Don't block the event loop on an absurdly long wait.
      retries += 1
      raise Error, "rate limited (retry-after: #{ e.wait }s)" if retries >= 3 || e.wait > RETRY_AFTER_CAP
      sleep e.wait
      retry
    end
  end

  private def replenish_connections
    # Reopen from the main loop, tolerating a single failure; #step retries.
    while @conns.size < @num_of_connections
      begin
        add_connection(@callback)
      rescue => e
        @logger.warn("[reconnect] failed: #{ e.message }") if @logger
        break
      end
    end
    # Fail loud rather than degrade silently once every connection is gone.
    raise Error, "all socket connections lost" if @num_of_connections > 0 && @conns.empty?
  end

  private def add_connection(callback)
    json = call("apps.connections.open", {}, token: @app_token)

    url = json[:url]
    url += "&debug_reconnects=true" if @debug
    ws = SimpleWebSocket.new(url) do |type, data|
      case type
      when :open
        @logger.info("[ws:#{ ws.object_id }] websocket open") if @logger
      when :close
        # #step drops the dead connection; #replenish_connections reopens it.
        @logger.info("[ws:#{ ws.object_id }] websocket closed") if @logger
      when :message
        begin
          json = JSON.parse(data, symbolize_names: true)
        rescue JSON::ParserError
          # A stray non-JSON frame: skip it, don't open a spurious connection.
          @logger.warn("[ws:#{ ws.object_id }] received a non-JSON message; ignored") if @logger
          next
        end

        if @logger
          @logger.debug("[ws:#{ ws.object_id }] slack message: #{ JSON.generate(json) }")
        end

        case json[:type]
        when "hello"
          @logger.info("[ws:#{ ws.object_id }] hello (active connections: #{ @conns.size })") if @logger
        when "disconnect"
          ws.close
          @logger.info("[ws:#{ ws.object_id }] disconnect (active connections: #{ @conns.size })") if @logger
        else
          payload = json[:payload]
          if @logger
            # Log a per-type identifier; event_id/retry only apply to events_api.
            detail =
              case json[:type]
              when "events_api"   then [payload.dig(:event, :type), payload[:event_id]].compact.join(" ")
              when "slash_commands" then payload[:command]
              else payload[:type]
              end
            retry_n = json[:retry_attempt].to_i
            line = "[ws:#{ ws.object_id }] #{ json[:type] }"
            line += " #{ detail }" if detail && !detail.empty?
            line += " (retry ##{ retry_n })" if retry_n > 0
            @logger.info(line)
          end
          # Only events_api has an event_id; dedup just those (others have none).
          event_id = payload[:event_id]
          expired = Time.now.to_i - 600
          @events.reject! {|_, timestamp| timestamp < expired }

          # ACK every message; only skip the handler for a duplicate, else Slack resends.
          duplicate = event_id && @events[event_id]
          @events[event_id] = payload[:event_time] if event_id

          response = { envelope_id: json[:envelope_id] }
          unless duplicate
            result = callback.call(json)
            response[:payload] = result if json[:accepts_response_payload]
          end
          ws.send(JSON.generate(response))
        end
      end
    end

    @conns << ws
  end

  #: -> [Array[IO], Array[IO]]
  def step
    read_ios, write_ios = [], []
    @conns.select! {|ws| ws.step(read_ios, write_ios) }
    replenish_connections
    return read_ios, write_ios
  end

  #: -> bot
  def run
    while true
      read_ios, write_ios = step
      IO.select(read_ios, write_ios)
    end
  end
end
