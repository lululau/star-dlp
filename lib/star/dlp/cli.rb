# frozen_string_literal: true

require "thor"
require "fileutils"
require "json"
require "time"
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
      option :threads, type: :numeric, default: 16, desc: "Number of download threads"
      option :skip_readme, type: :boolean, default: false, desc: "Skip downloading README files"
      option :retry_count, type: :numeric, default: 5, desc: "Number of retry attempts for failed downloads"
      option :retry_delay, type: :numeric, default: 1, desc: "Delay in seconds between retry attempts"
      def download(username)
        config = Config.load
        
        # Override config with command line options
        config.github_token = options[:token] if options[:token]
        config.output_dir = options[:output_dir] if options[:output_dir]
        config.json_dir = options[:json_dir] if options[:json_dir]
        config.markdown_dir = options[:markdown_dir] if options[:markdown_dir]
        
        # Save config for future use
        config.save
        
        downloader = Downloader.new(
          config, 
          username, 
          thread_count: options[:threads],
          skip_readme: options[:skip_readme],
          retry_count: options[:retry_count],
          retry_delay: options[:retry_delay]
        )
        downloader.download
      end
      
      desc "download_readme", "Download READMEs for all repositories from JSON files"
      option :threads, type: :numeric, default: 16, desc: "Number of download threads"
      option :retry_count, type: :numeric, default: 5, desc: "Number of retry attempts for failed downloads"
      option :retry_delay, type: :numeric, default: 1, desc: "Delay in seconds between retry attempts"
      option :force, type: :boolean, default: false, desc: "Force download even if README was already downloaded"
      def download_readme
        config = Config.load
        
        # Create a downloader instance
        downloader = Downloader.new(
          config,
          "readme_downloader", # Placeholder username
          thread_count: options[:threads],
          retry_count: options[:retry_count],
          retry_delay: options[:retry_delay]
        )
        
        # Call the download_readmes method in the Downloader class
        result = downloader.download_readmes(force: options[:force])
        
        puts "README download completed!"
        puts "Successfully downloaded: #{result[:success]}"
        puts "Failed or not found: #{result[:failed]}"
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