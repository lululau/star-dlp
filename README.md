# Star-DLP

Star-DLP (Star Downloader) is a Ruby gem for downloading and managing repositories you've starred on GitHub. It supports downloading starred repositories as JSON and Markdown files, and features incremental downloading, only downloading new starred repositories that aren't already in your local collection.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'star-dlp'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install star-dlp
```

## Usage

### Configuration

First, you can configure Star-DLP:

```bash
$ star-dlp config --token=your_github_token
```

You can set the following options:
- `--token`: GitHub API token (recommended to avoid API rate limits)
- `--output_dir`: Output directory
- `--json_dir`: JSON files directory
- `--markdown_dir`: Markdown files directory

### Downloading Starred Repositories

To download your starred repositories:

```bash
$ star-dlp download your_github_username
```

This will download all your starred repositories and save them as JSON and Markdown files. If you've previously downloaded some repositories, it will only download newly starred repositories.

Available options:
- `--token`: GitHub API token
- `--output_dir`: Output directory
- `--json_dir`: JSON files directory
- `--markdown_dir`: Markdown files directory
- `--threads`: Number of download threads (default: 16)
- `--skip_readme`: Skip downloading README files
- `--retry_count`: Number of retry attempts for failed downloads (default: 5)
- `--retry_delay`: Delay in seconds between retry attempts (default: 1)

Example with options:

```bash
$ star-dlp download your_github_username --threads=8 --skip_readme --retry_count=3
```

### Downloading READMEs

If you've already downloaded your starred repositories but want to download or update their README files separately:

```bash
$ star-dlp download_readme
```

This command will scan your JSON files directory, extract repository information, and download README files for repositories that don't already have them.

Available options:
- `--threads`: Number of download threads (default: 16)
- `--retry_count`: Number of retry attempts for failed downloads (default: 5)
- `--retry_delay`: Delay in seconds between retry attempts (default: 1)
- `--force`: Force download even if README was already downloaded

Example with options:

```bash
$ star-dlp download_readme --threads=8 --force
```

### View Version

```bash
$ star-dlp version
```

## File Structure

Star-DLP saves files in the following locations:

- Configuration file: `~/.star-dlp/config.json`
- Starred repositories: `~/.star-dlp/stars/`
  - JSON files: `~/.star-dlp/stars/json/YYYY/MM/YYYYMMDD.owner.repo.json`
  - Markdown files: `~/.star-dlp/stars/markdown/YYYY/MM/YYYYMMDD.owner.repo.md`
  - Last downloaded repository: `~/.star-dlp/stars/last_downloaded_repo.txt`
  - Downloaded READMEs list: `~/.star-dlp/stars/downloaded_readmes.txt`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
