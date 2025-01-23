# -*- coding: utf-8 -*-
$:.unshift(File.expand_path("lib", File.dirname(__FILE__)))
require 'mosql/version'

Gem::Specification.new do |gem|
  gem.authors       = ["Nelson Elhage"]
  gem.email         = ["nelhage@stripe.com"]
  gem.description   = %q{A library for streaming MongoDB to SQL}
  gem.summary       = %q{MongoDB -> SQL streaming bridge}
  gem.homepage      = "https://github.com/stripe/mosql"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "mosql"
  gem.require_paths = ["lib"]
  gem.version       = MoSQL::VERSION

  gem.add_runtime_dependency "sequel", "~> 5.8"
  gem.add_runtime_dependency "pg", "~> 1.5"
  gem.add_runtime_dependency "rake", "13.2.1"
  gem.add_runtime_dependency "logger", "1.6.5"
  gem.add_runtime_dependency "json", "2.9.1"

  gem.add_runtime_dependency "mongo", "~> 2.2"
  gem.add_runtime_dependency "bson", "5.0.2"

  gem.add_development_dependency "minitest", "~> 5.25"
  gem.add_development_dependency "mocha", "~> 2.7"
end
