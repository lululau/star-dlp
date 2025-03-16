# frozen_string_literal: true

require "github_api"
require "json"
require "fileutils"
require "time"
require "base64"
require "thread"

module Star
  module Dlp
    class Downloader
      attr_reader :config, :github, :username
      
      LAST_REPO_FILE = "last_downloaded_repo.txt"
      DEFAULT_THREAD_COUNT = 2
      DEFAULT_RETRY_COUNT = 5
      DEFAULT_RETRY_DELAY = 1 # seconds
      
      def initialize(config, username, thread_count: DEFAULT_THREAD_COUNT)
        @config = config
        @username = username
        @thread_count = thread_count
        
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
        # Get last downloaded info
        last_repo_name = get_last_repo_name
        
        if last_repo_name
          puts "Last download stopped at repository: #{last_repo_name}."
          puts "Will only fetch stars added after this timestamp."
        else
          puts "No previous download record found. Will download all stars."
        end
        
        # Download all stars
        all_stars = []
        page = 1
        newest_repo_name = nil
        newest_starred_at = nil
        
        # Download stars page by page
        loop do
          puts "Fetching page #{page}..."
          stars = github.activity.starring.starred(user: username, per_page: 100, page: page)
          break if stars.empty?

          puts "  - Got #{stars.size} repositories from page #{page}"
          
          # Store the name and starred_at of the newest star (first star on first page)
          if page == 1 && !stars.empty?
            newest_repo = stars.first
            newest_repo_name = get_repo_full_name(newest_repo)
            newest_starred_at = newest_repo.respond_to?(:starred_at) ? newest_repo.starred_at : nil
            
            puts "Newest starred repository: #{newest_repo_name} (starred at: #{newest_starred_at || 'unknown'})"
          end
          
          # Check if we've reached repos that were already downloaded
          should_break = false
          
          # If we have both last_repo_name, we can use them for comparison
          if last_repo_name
            stars.each do |star|
              repo_name = get_repo_full_name(star)
              starred_at = star.respond_to?(:starred_at) ? star.starred_at : nil
              
              # If we find a star with the same name and timestamp, we've reached our previous download point
              if repo_name == last_repo_name
                puts "  - Reached previously downloaded repository: #{repo_name} (starred at: #{starred_at})"
                puts "  - Stopping pagination."
                should_break = true
                break
              end
              all_stars << star
            end
          else
            all_stars.concat(stars)
          end
          
          page += 1
          
          break if should_break
        end
        
        # Filter out stars that already exist in our collection
        new_stars = all_stars
        
        puts "Found #{new_stars.size} new starred repositories to download"
        
        # Save new stars using multiple threads
        if new_stars.any?
          puts "Downloading new repositories using #{@thread_count} threads:"
          
          # Create a thread-safe queue for the stars
          queue = Queue.new
          new_stars.each { |star| queue << star }
          
          # Create a mutex for thread-safe output
          mutex = Mutex.new
          
          # Create a progress counter
          total = new_stars.size
          completed = 0
          
          # Create and start the worker threads
          threads = Array.new(@thread_count) do
            Thread.new do
              until queue.empty?
                # Try to get a star from the queue (non-blocking)
                star = queue.pop(true) rescue nil
                break unless star
                
                # Get the repository name for logging
                repo_name = get_repo_full_name(star)
                
                # Process the star with retry mechanism
                success = false
                retry_count = 0
                
                until success || retry_count >= DEFAULT_RETRY_COUNT
                  begin
                    # Save the star as JSON and Markdown
                    save_star_as_json(star)
                    save_star_as_markdown(star)
                    success = true
                  rescue => e
                    retry_count += 1
                    
                    # Log the error and retry information
                    mutex.synchronize do
                      puts "  Error downloading #{repo_name}: #{e.message}"
                      if retry_count < DEFAULT_RETRY_COUNT
                        puts "  Retrying in #{DEFAULT_RETRY_DELAY} seconds (attempt #{retry_count + 1}/#{DEFAULT_RETRY_COUNT})..."
                      else
                        puts "  Failed to download after #{DEFAULT_RETRY_COUNT} attempts."
                      end
                    end
                    
                    # Wait before retrying
                    sleep(DEFAULT_RETRY_DELAY)
                  end
                end
                
                # Update progress
                mutex.synchronize do
                  completed += 1
                  puts "  [#{completed}/#{total}] Downloaded: #{repo_name} (#{(completed.to_f / total * 100).round(1)}%)"
                end
              end
            end
          end
          
          # Wait for all threads to complete
          threads.each(&:join)
          
          puts "Download completed successfully!"
        else
          puts "No new repositories to download."
        end
        
        # Save the newest repo info for next time
        if newest_repo_name
          save_last_repo_name(newest_repo_name)
          puts "Saved latest repository name: #{newest_repo_name}"
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
      
      
      def save_star_as_json(star)
        star_data = star.to_hash
        
        # Get starred_at date or use current date as fallback
        starred_at = star.respond_to?(:starred_at) ? Time.parse(star.starred_at) : Time.now
        
        # Create directory structure based on starred_at date: json/YYYY/MM/
        year_dir = starred_at.strftime("%Y")
        month_dir = starred_at.strftime("%m")
        target_dir = File.join(config.json_dir, year_dir, month_dir)
        FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
        
        # Format filename: YYYYMMDD.username.repo_name.json
        date_str = starred_at.strftime("%Y%m%d")
        repo_name = get_repo_full_name(star).gsub('/', '.')
        filename = "#{date_str}.#{repo_name}.json"
        
        filepath = File.join(target_dir, filename)
        File.write(filepath, JSON.pretty_generate(star_data))
      end
      
      def save_star_as_markdown(star)
        # Get starred_at date or use current date as fallback
        starred_at = star.respond_to?(:starred_at) ? Time.parse(star.starred_at) : Time.now
        
        # Create directory structure based on starred_at date: markdown/YYYY/MM/
        year_dir = starred_at.strftime("%Y")
        month_dir = starred_at.strftime("%m")
        target_dir = File.join(config.markdown_dir, year_dir, month_dir)
        FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
        
        # Format filename: YYYYMMDD.username.repo_name.md
        date_str = starred_at.strftime("%Y%m%d")
        repo_full_name = get_repo_full_name(star)
        repo_name = repo_full_name.gsub('/', '.')
        filename = "#{date_str}.#{repo_name}.md"
        
        filepath = File.join(target_dir, filename)

        return if File.exist?(filepath)
        
        # Include starred_at in the markdown
        starred_at_str = star.respond_to?(:starred_at) ? star.starred_at : "N/A"
        
        # Basic repository information
        content = <<~MARKDOWN
          # #{repo_full_name}
          
          #{get_description(star)}
          
          - **Stars**: #{get_stargazers_count(star)}
          - **Forks**: #{get_forks_count(star)}
          - **Language**: #{get_language(star)}
          - **Created at**: #{get_created_at(star)}
          - **Updated at**: #{get_updated_at(star)}
          - **Starred at**: #{starred_at_str}
          
          [View on GitHub](#{get_html_url(star)})
          
          ## Topics
          
          #{(get_topics(star) || []).map { |topic| "- #{topic}" }.join("\n")}
        MARKDOWN
        
        # Try to fetch README.md content
        readme_content = fetch_readme(repo_full_name)
        if readme_content
          content += "\n\n## README\n\n#{readme_content}\n"
        else
          content += "\n\n## Description\n\n#{get_description(star)}\n"
        end
        
        File.write(filepath, content)
      end
      
      # Helper methods to safely access star properties
      def get_repo_full_name(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:full_name)
          star.repo.full_name
        elsif star.respond_to?(:full_name)
          star.full_name
        else
          "unknown/unknown"
        end
      end
      
      def get_description(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:description)
          star.repo.description
        elsif star.respond_to?(:description)
          star.description
        else
          ""
        end
      end
      
      def get_stargazers_count(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:stargazers_count)
          star.repo.stargazers_count
        elsif star.respond_to?(:stargazers_count)
          star.stargazers_count
        else
          0
        end
      end
      
      def get_forks_count(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:forks_count)
          star.repo.forks_count
        elsif star.respond_to?(:forks_count)
          star.forks_count
        else
          0
        end
      end
      
      def get_language(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:language)
          star.repo.language
        elsif star.respond_to?(:language)
          star.language
        else
          "Unknown"
        end
      end
      
      def get_created_at(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:created_at)
          star.repo.created_at
        elsif star.respond_to?(:created_at)
          star.created_at
        else
          "Unknown"
        end
      end
      
      def get_updated_at(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:updated_at)
          star.repo.updated_at
        elsif star.respond_to?(:updated_at)
          star.updated_at
        else
          "Unknown"
        end
      end
      
      def get_html_url(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:html_url)
          star.repo.html_url
        elsif star.respond_to?(:html_url)
          star.html_url
        else
          "https://github.com"
        end
      end
      
      def get_topics(star)
        if star.respond_to?(:repo) && star.repo.respond_to?(:topics)
          star.repo.topics
        elsif star.respond_to?(:topics)
          star.topics
        else
          []
        end
      end
      
      # Fetch README.md content from GitHub
      def fetch_readme(repo_full_name)
        begin
          # Get README content using GitHub API
          response = github.repos.contents.get(
            user: repo_full_name.split('/').first,
            repo: repo_full_name.split('/').last,
            path: 'README.md'
          )
          
          # Decode content from Base64
          if response.content && response.encoding == 'base64'
            return Base64.decode64(response.content).force_encoding('UTF-8')
          end
        rescue Github::Error::NotFound
          # Try README.markdown if README.md not found
          begin
            response = github.repos.contents.get(
              user: repo_full_name.split('/').first,
              repo: repo_full_name.split('/').last,
              path: 'README.markdown'
            )
            
            if response.content && response.encoding == 'base64'
              return Base64.decode64(response.content).force_encoding('UTF-8')
            end
          rescue Github::Error::NotFound
            # Try readme.md (lowercase) if previous attempts failed
            begin
              response = github.repos.contents.get(
                user: repo_full_name.split('/').first,
                repo: repo_full_name.split('/').last,
                path: 'readme.md'
              )
              
              if response.content && response.encoding == 'base64'
                return Base64.decode64(response.content).force_encoding('UTF-8')
              end
            rescue Github::Error::NotFound
              # README not found
              return nil
            rescue => e
              puts "Error fetching lowercase readme.md for #{repo_full_name}: #{e.message}"
              raise e
            end
          rescue => e
            puts "Error fetching README.markdown for #{repo_full_name}: #{e.message}"
            raise e
          end
        rescue => e
          puts "Error fetching README.md for #{repo_full_name}: #{e.message}"
          raise e
        end
      end
    end
  end
end 