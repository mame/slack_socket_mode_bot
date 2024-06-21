# simple echo bot

require "slack_socket_mode_bot"
require "logger"

# Slack's Bot User OAuth Token
# You can create this token with: https://api.slack.com/apps/ - "OAuth & Permissions" - "OAuth Tokens for Your Workspace"
SLACK_BOT_TOKEN = ENV.fetch("SLACK_BOT_TOKEN")

# Slack's App-Level Token
# You can create one with: https://api.slack.com/apps/ - "Basic Information" - "App-Level Tokens"
SLACK_APP_TOKEN = ENV.fetch("SLACK_APP_TOKEN")

logger = Logger.new(STDOUT, level: Logger::Severity::INFO)

bot = SlackSocketModeBot.new(token: SLACK_BOT_TOKEN, app_token: SLACK_APP_TOKEN, logger: logger) do |data|
  # Event handler. The `data` is a JSON object like this:
  #
  # {
  #   "type": "events_api",
  #   "envelope_id": "...",
  #   "accepts_response_payload": false,
  #   "payload": {
  #     "type": "event_callback",
  #     "event": {
  #       "type": "app_mention",
  #       "text": "hello",
  #       ...
  #     },
  #     ...
  #   }
  # }
  #
  # See https://api.slack.com/apis/socket-mode#events in detail.

  if data[:type] == "events_api" && data[:payload][:event][:type] == "app_mention"
    event = data[:payload][:event]

    text = event[:text]

    echo_text = "echo:" + text

    bot.call("chat.postMessage", { channel: event[:channel], text: echo_text })
  end

rescue Exception
  puts $!.full_message
end

# Start the communication
bot.run
