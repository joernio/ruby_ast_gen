require 'bundler/setup'
require_relative 'lib/ruby_ast_gen/version'

PACKAGE_NAME = "ruby_ast_gen"
VERSION = RubyAstGen::VERSION
TRAVELING_RUBY_VERSION = "20240904-3.1.6"

desc "Package your app"
task :package => ['package:linux:x86_64', 'package:osx:x86_64', 'package:windows:x86_64']

namespace :package do
  namespace :linux do
    desc "Package your app for Linux x86_64"
    task :x86_64 => [:bundle_install, "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86_64.tar.gz"] do
      create_package("linux-x86_64")
    end
  end

  namespace :osx do
    desc "Package your app for OS X"
    task :x86_64 => [:bundle_install, "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-osx-x86_64.tar.gz"] do
      create_package("osx-x86_64")
    end
  end

  namespace :windows do
    desc "Package your app for Windows"
    task :x86_64 => [:bundle_install, "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-windows-x86_64.tar.gz"] do
      create_package("windows-x86_64")
    end
  end

  desc "Install gems to local directory"
  task :bundle_install do
    if RUBY_VERSION !~ /^3\.1\./
      abort "You can only 'bundle install' using Ruby 3.1, because that's what Traveling Ruby uses."
    end
    sh "rm -rf packaging/tmp"
    sh "mkdir packaging/tmp"
    sh "cp Gemfile Gemfile.lock packaging/tmp/"
    sh "mkdir -p packaging/tmp/lib/ruby_ast_gen/"
    sh "cp lib/ruby_ast_gen/version.rb packaging/tmp/lib/ruby_ast_gen/"
    Bundler.with_unbundled_env do
      sh "cd packaging/tmp && env BUNDLE_IGNORE_CONFIG=1 bundle install --path ../vendor --without development"
    end
    sh "rm -rf packaging/tmp"
    sh "rm -f packaging/vendor/*/*/cache/*"
  end
end

file "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-linux-x86_64.tar.gz" do
  download_runtime("linux-x86_64")
end

file "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-osx-x86_64.tar.gz" do
  download_runtime("osx-x86_64")
end

file "packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-windows-x86_64.tar.gz" do
  download_runtime("windows-x86_64")
end

def create_package(target)
  package_dir = "#{PACKAGE_NAME}-#{VERSION}-#{target}"
  sh "rm -rf #{package_dir}"
  sh "mkdir #{package_dir}"
  sh "mkdir -p #{package_dir}/lib/app"
  sh "cp -r lib/ #{package_dir}/lib/app/lib/"
  sh "cp -r exe/ #{package_dir}/lib/app/exe/"
  sh "cp -r sig/ #{package_dir}/lib/app/sig/"
  sh "mkdir #{package_dir}/lib/ruby"
  sh "tar -xzf packaging/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz -C #{package_dir}/lib/ruby"
  sh "cp packaging/runner.sh #{package_dir}/ruby_ast_gen"
  sh "cp -pR packaging/vendor #{package_dir}/lib/"
  sh "cp Gemfile Gemfile.lock #{package_dir}/lib/vendor/"
  sh "mkdir -p #{package_dir}/lib/vendor/.bundle"
  sh "cp packaging/bundler-config #{package_dir}/lib/vendor/.bundle/config"
  if !ENV['DIR_ONLY']
    sh "tar -czf #{package_dir}.tar.gz #{package_dir}"
    sh "rm -rf #{package_dir}"
  end
end

def download_runtime(target)
  sh "cd packaging && curl -L -O --fail " +
    "https://github.com/YOU54F/traveling-ruby/releases/download/rel-20240904/traveling-ruby-#{TRAVELING_RUBY_VERSION}-#{target}.tar.gz"
end