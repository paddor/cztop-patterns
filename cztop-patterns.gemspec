# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cztop/patterns/version'

Gem::Specification.new do |spec|
  spec.name          = "cztop-patterns"
  spec.version       = CZTop::Patterns::VERSION
  spec.authors       = ["Patrik Wenger"]
  spec.email         = ["paddor@gmail.com"]

  spec.summary       = %q{reusable ZMQ messaging patterns from the Zguide, on CZTop}
  spec.homepage      = "https://github.com/paddor/cztop-patterns"
  spec.license       = "ISC"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "cztop", "~> 0.11.0"
  spec.add_runtime_dependency "eventmachine", "~> 1.2.0.1"

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rspec-given", "~> 3.8.0"
end
