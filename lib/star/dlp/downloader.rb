# frozen_string_literal: true

require "github_api"
require "json"
require "fileutils"
require "time"

module Star
  module Dlp
    class Downloader
      attr_reader :config, :github, :username
      
      LAST_REPO_FILE = "last_downloaded_repo.txt"
      
      def initialize(config, username)
        @config = config
        @username = username
        
        # Initialize GitHub API client with the special Accept header for starred_at field
        options = {
          headers: {
            "Accept" => "application/vnd.github.star+json",
            "X-GitHub-Api-Version" => "2022-11-28"
          }
        }
        
        # Add token if available
        options[:oauth_token] = config.github_token if config.github_token
        
        @github = Github.new(options)
      end
      
      def download
        puts "Downloading stars for user: #{username}"
        
        # Get existing stars from JSON files
        existing_stars = get_existing_stars
        existing_star_map = existing_stars.each_with_object({}) do |star, hash|
          hash[star[:id]] = star
        end
        
        # Get last downloaded repo if available
        last_repo_name = get_last_repo_name
        if last_repo_name
          puts "Last download stopped at repository: #{last_repo_name}. Will only fetch stars added after this repo."
        else
          puts "No previous download record found. Will download all stars."
        end
        
        # Download all stars
        all_stars = []
        page = 1
        newest_repo_name = nil
        
        # Download stars page by page
        loop do
          puts "Fetching page #{page}..."
          stars = github.activity.starring.starred(user: username, per_page: 100, page: page)
          break if stars.empty?
          
          # Store the name of the newest star (first star on first page)
          if page == 1 && !stars.empty?
            newest_repo = stars.first
            newest_repo_name = newest_repo.full_name if newest_repo.respond_to?(:full_name)
          end
          
          # Check if we've reached repos that were already downloaded
          should_break = false
          if last_repo_name
            stars.each do |star|
              if star.respond_to?(:full_name) && star.full_name == last_repo_name
                puts "  - Reached previously downloaded repository: #{last_repo_name}. Stopping pagination."
                should_break = true
                break
              end
            end
          end
          
          puts "  - Got #{stars.size} repositories from page #{page}"
          all_stars.concat(stars.to_a)
          page += 1
          
          break if should_break
        end
        
        puts "Found #{all_stars.size} starred repositories to process"
        
        # Separate stars into new and existing
        new_stars = []
        updated_stars = []
        
        all_stars.each do |star|
          if existing_star_map.key?(star.id)
            # Check if the star has been updated
            existing_star = existing_star_map[star.id]
            if star_needs_update?(star, existing_star)
              updated_stars << star
            end
          else
            new_stars << star
          end
        end
        
        puts "Found #{new_stars.size} new starred repositories to download"
        puts "Found #{updated_stars.size} existing repositories that need updates"
        
        # Save new stars
        if new_stars.any?
          puts "Downloading new repositories:"
          new_stars.each_with_index do |star, index|
            puts "  [#{index + 1}/#{new_stars.size}] Downloading: #{star.full_name}"
            save_star_as_json(star)
            save_star_as_markdown(star)
          end
        else
          puts "No new repositories to download."
        end
        
        # Update existing stars
        if updated_stars.any?
          puts "Updating existing repositories:"
          updated_stars.each_with_index do |star, index|
            puts "  [#{index + 1}/#{updated_stars.size}] Updating: #{star.full_name}"
            save_star_as_json(star)
            save_star_as_markdown(star)
          end
        else
          puts "No existing repositories need updates."
        end
        
        # Save the newest repo name for next time
        if newest_repo_name
          save_last_repo_name(newest_repo_name)
          puts "Saved latest repository name: #{newest_repo_name}"
        end
        
        if new_stars.any? || updated_stars.any?
          puts "Download and update completed successfully!"
        else
          puts "All repositories are up to date."
        end
      end
      
      private
      
      def get_last_repo_name
        last_repo_file = File.join(config.output_dir, LAST_REPO_FILE)
        return nil unless File.exist?(last_repo_file)
        
        File.read(last_repo_file).strip
      end
      
      def save_last_repo_name(repo_name)
        last_repo_file = File.join(config.output_dir, LAST_REPO_FILE)
        File.write(last_repo_file, repo_name)
      end
      
      def star_needs_update?(current_star, existing_star)
        # Convert to hash for easier comparison
        current_data = current_star.to_hash
        
        # Check for changes in key attributes
        return true if current_data[:stargazers_count] != existing_star[:stargazers_count]
        return true if current_data[:forks_count] != existing_star[:forks_count]
        return true if current_data[:updated_at] != existing_star[:updated_at]
        return true if current_data[:description] != existing_star[:description]
        return true if current_data[:topics] != existing_star[:topics]
        
        # No significant changes detected
        false
      end
      
      def get_existing_stars
        return [] unless Dir.exist?(config.json_dir)
        
        json_files = Dir.glob(File.join(config.json_dir, "*.json"))
        json_files.map do |file|
          JSON.parse(File.read(file), symbolize_names: true)
        end
      end
      
      def save_star_as_json(star)
        star_data = star.to_hash
        filename = "#{star.id}.json"
        filepath = File.join(config.json_dir, filename)
        
        File.write(filepath, JSON.pretty_generate(star_data))
      end
      
      def save_star_as_markdown(star)
        filename = "#{star.full_name.gsub('/', '-')}.md"
        filepath = File.join(config.markdown_dir, filename)
        
        # Include starred_at in the markdown if available
        starred_at = star.respond_to?(:starred_at) ? star.starred_at : "N/A"
        
        content = <<~MARKDOWN
          # #{star.full_name}
          
          #{star.description}
          
          - **Stars**: #{star.stargazers_count}
          - **Forks**: #{star.forks_count}
          - **Language**: #{star.language}
          - **Created at**: #{star.created_at}
          - **Updated at**: #{star.updated_at}
          - **Starred at**: #{starred_at}
          
          [View on GitHub](#{star.html_url})
          
          ## Topics
          
          #{(star.topics || []).map { |topic| "- #{topic}" }.join("\n")}
          
          ## Description
          
          #{star.description}
        MARKDOWN
        
        File.write(filepath, content)
      end
    end
  end
end 