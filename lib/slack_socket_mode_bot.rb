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

  #: (token: String, ?app_token: String, ?num_of_connections: Integer, ?debug: boolean, ?logger: Logger) { (untyped) -> untyped } -> void
  def initialize(token:, app_token: nil, num_of_connections: 4, debug: false, logger: nil, &callback)
    @token = token
    @app_token = app_token
    @conns = []
    @debug = debug
    @logger = logger
    @events = {}
    num_of_connections.times { add_connection(callback) } if app_token
  end

  #: (String method, untyped data, ?token: String) -> untyped
  def call(method, data, token: @token)
    count = 0
    begin
      url = URI("https://slack.com/api/" + method)
      res = Net::HTTP.post(
        url, JSON.generate(data),
        "Content-type" => "application/json; charset=utf-8",
        "Authorization" => "Bearer " + token,
      )
      json = JSON.parse(res.body, symbolize_names: true)
      raise Error, json[:error] unless json[:ok]
      json
    rescue Socket::ResolutionError
      sleep 1
      count += 1
      retry if count < 3
      raise
    end
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
        @logger.info("[ws:#{ ws.object_id }] websocket closed") if @logger
        add_connection(callback)
      when :message
        begin
          json = JSON.parse(data, symbolize_names: true)
        rescue JSON::ParserError
          add_connection(callback)
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
            msg = "[ws:#{ ws.object_id }] #{ json[:type] } [##{ json[:retry_attempt] + 1 }] (#{
              {
                event_id: payload[:event_id],
                event_time: Time.at(payload[:event_time]).strftime("%FT%T"),
                type: payload[:type],
              }.map {|k, v| "#{ k }: #{ v }" }.join(", ")
            })"
            @logger.info(msg)
          end
          expired = Time.now.to_i - 600
          @events.reject! {|_, timestamp| timestamp < expired }

          if @events[json[:payload][:event_id]]
            # ignore
          else
            @events[json[:payload][:event_id]] = json[:payload][:event_time]

            response = { envelope_id: json[:envelope_id] }
            if json[:accepts_response_payload]
              response[:payload] = callback.call(json)
            else
              callback.call(json)
            end
            ws.send(JSON.generate(response))
          end
        end
      end
    end

    @conns << ws
  end

  #: -> [Array[IO], Array[IO]]
  def step
    read_ios, write_ios = [], []
    @conns.select! {|ws| ws.step(read_ios, write_ios) }
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
