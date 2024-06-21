# SlackSocketModeBot

This is a simple Ruby wrapper for the [Slack's Socket Mode API](https://api.slack.com/apis/socket-mode).
It allows you to write a Slack bot without exposing a public HTTP endpoint.

## Usage

First, set up your Slack app for Socket Mode by reading [the official document](https://api.slack.com/apis/socket-mode).

Then, run the following script.

```ruby
# simple echo bot

require "slack_socket_mode_bot"
require "logger"

# Slack's Bot User OAuth Token
# You can create this token with: https://api.slack.com/apps/ - "OAuth & Permissions" - "OAuth Tokens for Your Workspace"
SLACK_BOT_TOKEN = "xoxb-..."

# Slack's App-Level Token
# You can create this token with: https://api.slack.com/apps/ - "Basic Information" - "App-Level Tokens"
SLACK_APP_TOKEN = "xapp-..."

logger = Logger.new(STDOUT, level: Logger::Severity::INFO)

bot = SlackSocketModeBot.new(token: SLACK_BOT_TOKEN, app_token: SLACK_APP_TOKEN, logger: logger) do |data|
  # Event handler. A sample data is
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
  # See https://api.slack.com/apis/socket-mode#events in detail

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
```

```
$ ruby example/echo_bot.rb
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2560] websocket open
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2600] websocket open
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2560] slack hello
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2560] active connection count: 4
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2600] slack hello
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2600] active connection count: 4
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2640] websocket open
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2640] slack hello
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2640] active connection count: 4
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2680] websocket open
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2680] slack hello
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2680] active connection count: 4
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2680] slack events_api (event_callback)
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2680] slack events_api (event_callback)
I, [20XX-XX-XXTXX:XX:XX.XXXXXX #XXXXXX]  INFO -- : [ws:2680] slack events_api (event_callback)
...
```

## API

### `SlackSocketModeBot.new(token:, app_token:, logger:)`

Connects to Slack with Socket Mode.

* `token`: Slack's Bot User OAuth token (starting with `xoxb-`)
* `app_token`: Slack's App-Level token (starting with `xapp-`)
* `logger`: A Logger instance (optional)
* block: Handles events received from Slack

Note: The block must return as soon as possible. Otherwise, the Slack server will re-send the event.
If you want to do a time-consuming process, it is recommended that you do it in a sub thread.

### `SlackSocketModeBot#call(method, data, token:)`

Calls Slack's [Web API](https://api.slack.com/methods), such as [chat.postMessage](https://api.slack.com/methods/chat.postMessage).

* `method`: API name (such as `"chat.postMessage"`)
* `data`: Arguments

This method returns the response as a JSON data.

### `SlackSocketModeBot#run`

Starts the main loop of communication with Slack. This method does not return.

### `SlackSocketModeBot#step`

Proceeds with the communication one step.

This method returns an array of IO waiting to be readable and an array of IO waiting to be writable.
They are supposed to be passed to `IO.select`.

Typically, this method should be used as follows.

```ruby
while true
  read_ios, write_ios = app.step
  IO.select(read_ios, write_ios)
end
```

This method allows you to manage the main loop yourself.
If you don't need it, you can just use `SlackSocketModeBot#run`.
