# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "smart_message-transport-named_pipes"
  spec.version = "0.0.1"
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dewayne@vanhoozer.me"]

  spec.summary = "Named pipes transport layer for SmartMessage messaging system"
  spec.description = "Provides Unix named pipes (FIFO) based transport for the SmartMessage pub/sub messaging system, enabling fast IPC communication between processes on the same machine."
  spec.homepage = "https://github.com/MadBomber/smart_message-transport-named_pipes"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/MadBomber/smart_message-transport-named_pipes"
    spec.metadata["changelog_uri"] = "https://github.com/MadBomber/smart_message-transport-named_pipes/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "smart_message", ">= 0.1.0"

  # Development dependencies
  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.16"
  spec.add_development_dependency "rubocop", "~> 1.21"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
