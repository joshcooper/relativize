# frozen_string_literal: true

source 'https://rubygems.org'

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

gemspec

gem 'rubocop'
gem 'rubocop-rake'
gem 'rubocop-rspec'

eval_gemfile('Gemfile.local') if File.exist?('Gemfile.local')
