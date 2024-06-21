# one-shot say hello

require "slack_socket_mode_bot"

# Slack's Bot User OAuth Token
# You can create one with: https://api.slack.com/apps/ - "OAuth & Permissions" - "OAuth Tokens for Your Workspace"
SLACK_BOT_TOKEN = ENV.fetch("SLACK_BOT_TOKEN")

# Slack target channel ID: "C........"
# You can see the id in the bottom of "View channel details" in the channel's context menu
TARGET_CHANNEL = ARGV[0]

bot = SlackSocketModeBot.new(token: SLACK_BOT_TOKEN)

bot.call("chat.postMessage", { channel: TARGET_CHANNEL, text: "hello" })
