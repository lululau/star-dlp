# frozen_string_literal: true

require "thor"
require_relative "config"
require_relative "downloader"

module Star
  module Dlp
    class CLI < Thor
      desc "download USERNAME", "Download GitHub stars for a user"
      option :token, type: :string, desc: "GitHub API token"
      option :output_dir, type: :string, desc: "Output directory for stars"
      option :json_dir, type: :string, desc: "Directory for JSON files"
      option :markdown_dir, type: :string, desc: "Directory for Markdown files"
      def download(username)
        config = Config.load
        
        # Override config with command line options
        config.github_token = options[:token] if options[:token]
        config.output_dir = options[:output_dir] if options[:output_dir]
        config.json_dir = options[:json_dir] if options[:json_dir]
        config.markdown_dir = options[:markdown_dir] if options[:markdown_dir]
        
        # Save config for future use
        config.save
        
        downloader = Downloader.new(config, username)
        downloader.download
      end
      
      desc "config", "Configure star-dlp"
      option :token, type: :string, desc: "GitHub API token"
      option :output_dir, type: :string, desc: "Output directory for stars"
      option :json_dir, type: :string, desc: "Directory for JSON files"
      option :markdown_dir, type: :string, desc: "Directory for Markdown files"
      def config
        config = Config.load
        
        # Override config with command line options
        config.github_token = options[:token] if options[:token]
        config.output_dir = options[:output_dir] if options[:output_dir]
        config.json_dir = options[:json_dir] if options[:json_dir]
        config.markdown_dir = options[:markdown_dir] if options[:markdown_dir]
        
        # Save config for future use
        config.save
        
        puts "Configuration saved successfully!"
        puts "GitHub Token: #{config.github_token || 'Not set'}"
        puts "Output Directory: #{config.output_dir}"
        puts "JSON Directory: #{config.json_dir}"
        puts "Markdown Directory: #{config.markdown_dir}"
      end
      
      desc "version", "Show version"
      def version
        puts "star-dlp version #{VERSION}"
      end
    end
  end
end 