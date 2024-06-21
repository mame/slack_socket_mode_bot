# frozen_string_literal: true

require_relative "lib/slack_socket_mode_bot/version"

Gem::Specification.new do |spec|
  spec.name = "slack_socket_mode_bot"
  spec.version = SlackSocketModeBot::VERSION
  spec.authors = ["Yusuke Endoh"]
  spec.email = ["mame@ruby-lang.org"]

  spec.summary = "A simple wrapper library for Slack's Socket Mode API"
  spec.homepage = "https://github.com/mame/slack_socket_mode_bot"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/mame/slack_socket_mode_bot"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[examples/ test/ .git Gemfile Gemfile.lock])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "websocket", "~> 1.2"
end
