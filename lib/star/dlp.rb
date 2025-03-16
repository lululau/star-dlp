# frozen_string_literal: true

require_relative "dlp/version"
require_relative "dlp/config"
require_relative "dlp/downloader"
require_relative "dlp/cli"

module Star
  module Dlp
    class Error < StandardError; end
    
    def self.start(args = ARGV)
      CLI.start(args)
    end
  end
end
