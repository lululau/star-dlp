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
      DOWNLOADED_READMES_FILE = "downloaded_readmes.txt"
      DEFAULT_THREAD_COUNT = 16
      DEFAULT_RETRY_COUNT = 5
      DEFAULT_RETRY_DELAY = 1 # seconds
      
      def initialize(config, username, thread_count: DEFAULT_THREAD_COUNT, skip_readme: false, retry_count: DEFAULT_RETRY_COUNT, retry_delay: DEFAULT_RETRY_DELAY)
        @config = config
        @username = username
        @thread_count = thread_count
        @skip_readme = skip_readme
        @retry_count = retry_count
        @retry_delay = retry_delay
        
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
          
          # Process stars with multithreading
          process_items_with_threads(
            new_stars,
            ->(star) { get_repo_full_name(star) },
            ->(star) {
              save_star_as_json(star)
              save_star_as_markdown(star)
            }
          )
          
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
      
      # Download READMEs for all repositories from JSON files
      def download_readmes(force: false)
        puts "Downloading READMEs for repositories from JSON files"
        
        # File to track repositories with downloaded READMEs
        downloaded_readmes_file = File.join(config.output_dir, DOWNLOADED_READMES_FILE)
        
        # Load list of repositories with already downloaded READMEs
        downloaded_repos = Set.new
        if File.exist?(downloaded_readmes_file) && !force
          File.readlines(downloaded_readmes_file).each do |line|
            downloaded_repos.add(line.strip)
          end
          puts "Found #{downloaded_repos.size} repositories with already downloaded READMEs"
        end
        
        # Find all JSON files in the json directory
        json_files = Dir.glob(File.join(config.json_dir, "**", "*.json"))
        puts "Found #{json_files.size} JSON files"
        
        # Extract repository names from JSON files
        repos_to_process = []
        repo_dates = {} # Store starred_at dates for repositories
        
        json_files.each do |json_file|
          begin
            data = JSON.parse(File.read(json_file))
            
            # Extract repository full name from JSON data
            repo_full_name = nil
            starred_at = nil
            
            if data.is_a?(Hash) && data["repo"] && data["repo"]["full_name"]
              repo_full_name = data["repo"]["full_name"]
              starred_at = data["starred_at"] if data.key?("starred_at")
            elsif data.is_a?(Hash) && data["full_name"]
              repo_full_name = data["full_name"]
              starred_at = data["starred_at"] if data.key?("starred_at")
            elsif File.basename(json_file) =~ /(\d{8})\.(.+)\.json$/
              # Try to extract from filename (format: YYYYMMDD.owner.repo.json)
              date_str = $1
              parts = $2.split('.')
              if parts.size >= 2
                repo_full_name = "#{parts[0]}/#{parts[1]}"
                # Convert YYYYMMDD to ISO date format
                if date_str =~ /^(\d{4})(\d{2})(\d{2})$/
                  starred_at = "#{$1}-#{$2}-#{$3}T00:00:00Z"
                end
              end
            end
            
            # Skip if we couldn't determine the repository name or if README was already downloaded
            next if repo_full_name.nil?
            next if downloaded_repos.include?(repo_full_name) && !force
            
            repos_to_process << repo_full_name
            # Store the starred_at date if available
            repo_dates[repo_full_name] = starred_at if starred_at
          rescue JSON::ParserError => e
            puts "Error parsing JSON file #{json_file}: #{e.message}"
          end
        end
        
        puts "Found #{repos_to_process.size} repositories that need README downloads"
        
        # Create a mutex for thread-safe file writing
        mutex = Mutex.new
        success_count = 0
        failed_count = 0
        
        # Process repositories with multithreading
        result = process_items_with_threads(
          repos_to_process,
          ->(repo) { repo }, # Item name is the repo name itself
          ->(repo_full_name) {
            # Try to download README
            readme_content = fetch_readme(repo_full_name)
            
            if readme_content
              # Get starred_at date if available, or use current date as fallback
              date = nil
              if repo_dates.key?(repo_full_name) && repo_dates[repo_full_name]
                begin
                  date = Time.parse(repo_dates[repo_full_name])
                rescue
                  date = Time.now
                end
              else
                date = Time.now
              end
              
              # Create markdown file path
              md_filepath = get_markdown_filepath(repo_full_name, date)
              
              mutex.synchronize do
                # Check if file exists
                if File.exist?(md_filepath)
                  # Append README content to existing file
                  File.open(md_filepath, 'a') do |file|
                    file.puts "\n\n## README\n\n#{readme_content}\n"
                  end
                else
                  # Create new file with repository information and README
                  content = <<~MARKDOWN
                    # #{repo_full_name}
                    
                    - **Downloaded at**: #{Time.now.iso8601}
                    - **Starred at**: #{date.iso8601}
                    
                    [View on GitHub](https://github.com/#{repo_full_name})
                    
                    ## README
                    
                    #{readme_content}
                  MARKDOWN
                  
                  File.write(md_filepath, content)
                end
                
                # Add to downloaded repositories list
                File.open(downloaded_readmes_file, 'a') do |file|
                  file.puts repo_full_name
                end
                
                success_count += 1
              end
              
              true
            else
              mutex.synchronize do
                puts "No README found for #{repo_full_name}"
                failed_count += 1
              end
              true # Mark as success even if README not found to avoid retries
            end
          }
        )
        
        puts "README download completed!"
        puts "Successfully downloaded: #{success_count}"
        puts "Failed or not found: #{failed_count}"
        
        return {
          total: repos_to_process.size,
          success: success_count,
          failed: failed_count
        }
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
        
        nil
      end
      
      private
      
      # Process a list of items using multiple threads
      # items: Array of items to process
      # name_proc: Proc to get item name for logging
      # process_proc: Proc to process each item
      def process_items_with_threads(items, name_proc, process_proc)
        return if items.empty?
        
        # Create a thread-safe queue for the items
        queue = Queue.new
        items.each { |item| queue << item }
        
        # Create a mutex for thread-safe output
        mutex = Mutex.new
        
        # Create a progress counter
        total = items.size
        completed = 0
        
        # Create and start the worker threads
        threads = Array.new(@thread_count) do
          Thread.new do
            until queue.empty?
              # Try to get an item from the queue (non-blocking)
              item = queue.pop(true) rescue nil
              break unless item
              
              # Get the item name for logging
              item_name = name_proc.call(item)
              
              # Process the item with retry mechanism
              success = false
              retry_count = 0
              
              until success || retry_count >= @retry_count
                begin
                  # Process the item
                  process_proc.call(item)
                  success = true
                rescue => e
                  retry_count += 1
                  
                  # Log the error and retry information
                  mutex.synchronize do
                    puts "  Error processing #{item_name}: #{e.message}"
                    if retry_count < @retry_count
                      puts "  Retrying in #{@retry_delay} seconds (attempt #{retry_count + 1}/#{@retry_count})..."
                    else
                      puts "  Failed to process after #{@retry_count} attempts."
                    end
                  end
                  
                  # Wait before retrying
                  sleep(@retry_delay)
                end
              end
              
              # Update progress
              mutex.synchronize do
                completed += 1
                puts "  [#{completed}/#{total}] Processed: #{item_name} (#{(completed.to_f / total * 100).round(1)}%)"
              end
            end
          end
        end
        
        # Wait for all threads to complete
        threads.each(&:join)
        
        return {
          total: total,
          completed: completed
        }
      end
      
      # Get the markdown file path for a repository
      def get_markdown_filepath(repo_full_name, date = Time.now)
        # Create directory structure based on date: markdown/YYYY/MM/
        year_dir = date.strftime("%Y")
        month_dir = date.strftime("%m")
        target_dir = File.join(config.markdown_dir, year_dir, month_dir)
        FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
        
        # Format filename: YYYYMMDD.repo_owner.repo_name.md
        date_str = date.strftime("%Y%m%d")
        repo_name = repo_full_name.gsub('/', '.')
        filename = "#{date_str}.#{repo_name}.md"
        
        File.join(target_dir, filename)
      end
      
      # Get the JSON file path for a repository
      def get_json_filepath(repo_full_name, date = Time.now)
        # Create directory structure based on date: json/YYYY/MM/
        year_dir = date.strftime("%Y")
        month_dir = date.strftime("%m")
        target_dir = File.join(config.json_dir, year_dir, month_dir)
        FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
        
        # Format filename: YYYYMMDD.repo_owner.repo_name.json
        date_str = date.strftime("%Y%m%d")
        repo_name = repo_full_name.gsub('/', '.')
        filename = "#{date_str}.#{repo_name}.json"
        
        File.join(target_dir, filename)
      end
      
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
        
        # Get the repository name
        repo_full_name = get_repo_full_name(star)
        
        # Get the JSON file path
        filepath = get_json_filepath(repo_full_name, starred_at)
        
        # Write the JSON file
        File.write(filepath, JSON.pretty_generate(star_data))
      end
      
      def save_star_as_markdown(star)
        # Get starred_at date or use current date as fallback
        starred_at = star.respond_to?(:starred_at) ? Time.parse(star.starred_at) : Time.now
        
        # Get the repository name
        repo_full_name = get_repo_full_name(star)
        
        # Get the markdown file path
        filepath = get_markdown_filepath(repo_full_name, starred_at)
        
        # Skip if file already exists
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
        
        # Try to fetch README.md content if not skipped
        unless @skip_readme
          readme_content = fetch_readme(repo_full_name)
          if readme_content
            content += "\n\n## README\n\n#{readme_content}\n"
          else
            content += "\n\n## Description\n\n#{get_description(star)}\n"
          end
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
    end
  end
end 