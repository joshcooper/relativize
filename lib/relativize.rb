# frozen_string_literal: true

require 'pathname'
require 'optparse'
require 'relativize/version'

# Convert `require` statements to `require_relative` in a ruby project with
# a typical directory structure:
#
# lib/project.rb
#    /project/a/{c.rb}
#             b/{d.rb}
#
# The following conversions will be made for "file" that requires "other":
#
# 1. Any require that doesn't start with `project.rb` or `project/` will be left as-is,
#    such as 'pathname' or 'project_impl'
#
# 2. If the "file" without an extension is an ancestor directory of "other", then
#    convert from require to require_relative using the "file"'s parent as the base.
#
#    In project.rb:
#      require 'project/a'   =>  require_relative 'project/a'
#
#    In project/a.rb:
#      require 'project/a/c' => require_relative 'a/c'
#      require 'project/b'   => require_relative 'b'
#
# 3. Otherwise determine the path of the "lib" directory relative to "file" and
#    append the path of "other" relative to "lib".
#
#    In c.rb:
#      require 'project'     => require_relative '../../project'
#      require 'project/b'   => require_relative '../../project/b'
#
module Relativize
  class CLI
    def initialize(argv = ARGV)
      @argv = argv
    end

    def parse
      options = { exclude: [] }

      OptionParser.new do |opts|
        opts.banner = 'Usage: relativize [options]'

        opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
          options[:verbose] = v
        end

        opts.on('-nNAME', '--name NAME', 'Name of the project') do |name|
          options[:name] = name
        end

        opts.on('-pPATH', '--path PATH', 'Path to the project') do |path|
          options[:path] = path
        end

        opts.on('-ePATHS', '--exclude PATHS', 'Comma separated list of paths to exclude') do |paths|
          options[:exclude] = paths.split(',')
        end
      end.parse!(@argv)

      raise ArgumentError, "Option '--name' is required" unless options[:name]
      raise ArgumentError, "Option '--path' is required" unless options[:path]

      options
    end
  end

  class Converter
    ROOT = Pathname.new('.').freeze

    def initialize(options)
      @name = options[:name]
      @exclude = options[:exclude]

      libdir = File.join(options[:path], 'lib')
      raise ArgumentError, "Path '#{libdir}' does not exist" unless File.exist?(libdir)

      @base = libdir
      @count = 0
    end

    # Convert content
    #
    # @relative_path [String] The relative path of the file we are converting, such as puppet/util.rb
    # @param content [String] The content of the file to convert
    # @return [String] New content with require statements replaced
    def convert_content(relative_path, content)
      current_dir = relative_path.to_s.chomp('.rb') # => puppet/util
      parent = relative_path.parent # => puppet

      # match require 'puppet' or require 'puppet/...' but not 'puppet_impl' or 'pathname'

      content.gsub!(%r{^(\s*)require '(#{@name}/.*|#{@name})'(.*)$}) do |line|
        prefix = Regexp.last_match(1)
        requiree = Pathname.new(Regexp.last_match(2))
        suffix = Regexp.last_match(3)

        newline = if ROOT == relative_path.parent
                    #
                    # require 'puppet/version' => require_relative 'puppet/version'
                    #
                    "require_relative '#{Regexp.last_match(2)}'"
                  elsif line.match(%r{#{current_dir}/(.*)'})
                    #
                    # require 'puppet/util/platform' => require_relative 'util/platform'
                    #
                    rel_child = requiree.relative_path_from(parent)
                    "require_relative '#{rel_child}'"
                  else
                    #
                    # require 'puppet/file_system/uniquefile' => require_relative '../../puppet/file_system/uniquefile'
                    #
                    "require_relative '#{ROOT.relative_path_from(parent)}/#{requiree}'"
                  end

        @count += 1
        "#{prefix}#{newline}#{suffix}"
      end
    end

    def source_paths
      Dir.glob('**/*.rb', base: @base).reject do |name|
        %w[. ..].include?(name)
      end
    end

    def convert
      paths = source_paths - @exclude
      paths.each do |path|
        current_file = File.join(@base, path)
        puts "converting: #{current_file}"

        content = File.read(current_file, encoding: 'utf-8')
        convert_content(Pathname.new(path), content)
        File.write(current_file, content, encoding: 'utf-8')
      end

      puts "converted #{@count} files"
    end
  end
end
