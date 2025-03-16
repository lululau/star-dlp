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

### View Version

```bash
$ star-dlp version
```

## File Structure

Star-DLP saves files in the following locations:

- Configuration file: `~/.star-dlp/config.json`
- Starred repositories: `~/.star-dlp/stars/`
  - JSON files: `~/.star-dlp/stars/json/`
  - Markdown files: `~/.star-dlp/stars/markdown/`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
