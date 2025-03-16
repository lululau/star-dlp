# frozen_string_literal: true

require_relative "lib/star/dlp/version"

Gem::Specification.new do |spec|
  spec.name = "star-dlp"
  spec.version = Star::Dlp::VERSION
  spec.authors = ["Liu Xiang"]
  spec.email = ["liuxiang921@gmail.com"]

  spec.summary = "A Ruby gem for downloading and managing your GitHub stars"
  spec.description = "star-dlp is a tool that helps you download, organize, and manage repositories you've starred on GitHub"
  spec.homepage = "https://github.com/lululau/star-dlp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lululau/star-dlp"
  spec.metadata["changelog_uri"] = "https://github.com/lululau/star-dlp/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "github_api", "~> 0.19.0"
  spec.add_dependency "thor", "~> 1.2"
  spec.add_dependency "fileutils", "~> 1.6"
  spec.add_dependency "json", "~> 2.6"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
