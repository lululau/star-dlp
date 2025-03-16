# frozen_string_literal: true

require "fileutils"
require "json"

module Star
  module Dlp
    class Config
      DEFAULT_CONFIG_DIR = File.join(Dir.home, ".star-dlp")
      DEFAULT_CONFIG_FILE = File.join(DEFAULT_CONFIG_DIR, "config.json")
      DEFAULT_STARS_DIR = File.join(DEFAULT_CONFIG_DIR, "stars")
      DEFAULT_JSON_DIR = File.join(DEFAULT_STARS_DIR, "json")
      DEFAULT_MARKDOWN_DIR = File.join(DEFAULT_STARS_DIR, "markdown")
      
      attr_accessor :github_token, :output_dir, :json_dir, :markdown_dir
      
      def initialize(options = {})
        @github_token = options[:github_token]
        @output_dir = options[:output_dir] || DEFAULT_STARS_DIR
        @json_dir = options[:json_dir] || DEFAULT_JSON_DIR
        @markdown_dir = options[:markdown_dir] || DEFAULT_MARKDOWN_DIR
        
        create_directories
      end
      
      def self.load
        return new unless File.exist?(DEFAULT_CONFIG_FILE)
        
        config_data = JSON.parse(File.read(DEFAULT_CONFIG_FILE), symbolize_names: true)
        new(config_data)
      end
      
      def save
        FileUtils.mkdir_p(DEFAULT_CONFIG_DIR) unless Dir.exist?(DEFAULT_CONFIG_DIR)
        
        config_data = {
          github_token: @github_token,
          output_dir: @output_dir,
          json_dir: @json_dir,
          markdown_dir: @markdown_dir
        }
        
        File.write(DEFAULT_CONFIG_FILE, JSON.pretty_generate(config_data))
      end
      
      private
      
      def create_directories
        [@output_dir, @json_dir, @markdown_dir].each do |dir|
          FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
        end
      end
    end
  end
end 