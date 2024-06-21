# simple slack command handler

# You must set up "Slash Commands" in https://api.slack.com/apps/

require "slack_socket_mode_bot"
require "logger"

# Slack's Bot User OAuth Token
# You can create one with: https://api.slack.com/apps/ - "OAuth & Permissions" - "OAuth Tokens for Your Workspace"
SLACK_BOT_TOKEN = ENV.fetch("SLACK_BOT_TOKEN")

# Slack's App-Level Token
# You can create one with: https://api.slack.com/apps/ - "Basic Information" - "App-Level Tokens"
SLACK_APP_TOKEN = ENV.fetch("SLACK_APP_TOKEN")

logger = Logger.new(STDOUT, level: Logger::Severity::INFO)

bot = SlackSocketModeBot.new(token: SLACK_BOT_TOKEN, app_token: SLACK_APP_TOKEN, logger: logger) do |data|
  # Event handler. A sample data is
  #
  # {
  #   "type": "slash_commands",
  #   "envelope_id": "...",
  #   "accepts_response_payload": true,
  #   "payload": {
  #     "command": "/test_echo_command",
  #     "text": "hello",
  #     ...
  #   }
  # }
  #
  # See https://api.slack.com/apis/socket-mode#command in detail

  if data[:type] = "slash_commands"
    # You need to return a response payload.
    # This message will be only visible to the user that invoked the slash command.
    {
      "text": "echo: " + data[:payload][:text]
    }

    # Or if you want to use mrkdwn:
    #
    # {
    #   "blocks": [
    #     {
    #       "type": "section",
    #       "text": {
    #         "type": "mrkdwn",
    #         "text": "echo: " + data[:payload][:text]
    #       }
    #     }
    #   ]
    # }
  end

rescue Exception
  puts $!.full_message
end

# Start the communication
bot.run
