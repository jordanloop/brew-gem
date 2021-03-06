require 'erb'
require 'tempfile'
require 'shellwords'

module Brew::Gem::CLI
  module_function

  COMMANDS = {
    "install"   => ("Install a brew gem, accepts an optional version argument\n" +
                    "            (e.g. brew gem install <name> [version])"),
    "upgrade"   => "Upgrade to the latest version of a brew gem",
    "uninstall" => "Uninstall a brew gem",
    "info"      => "Show information for an installed gem",
    "formula"   => "Print out the generated formula for a gem",
    "help"      => "This message"
  }

  HOMEBREW_RUBY_FLAG = "--homebrew-ruby"
  SYSTEM_RUBY_FLAG   = "--system-ruby"
  RUBY_FLAGS = [HOMEBREW_RUBY_FLAG, SYSTEM_RUBY_FLAG]

  class Arguments
    attr_reader :ruby_flag

    def initialize(args)
      @ruby_flag          = args.select {|a| RUBY_FLAGS.include?(a) }.last
      @args               = args.reject {|a| RUBY_FLAGS.include?(a) }
      @args_without_flags = @args.reject {|a| a.start_with?('-') }
    end

    def command
      @args_without_flags[0]
    end

    def gem
      @args_without_flags[1]
    end

    def supplied_version
      @args_without_flags[2]
    end

    def to_args
      @args.reject {|a| a == gem || a == supplied_version }
    end
  end

  def help_msg
    (["Please specify a gem name (e.g. brew gem command <name>)"] +
      COMMANDS.map {|name, desc| "  #{name} - #{desc}"}).join("\n")
  end

  def fetch_version(name, version = nil)
    gems = `gem list --remote "^#{name}$"`.lines

    unless gems.detect { |f| f =~ /^#{name} \(([^\s,]+).*\)/ }
      abort "Could not find a valid gem '#{name}'"
    end

    version ||= $1
    version
  end

  def process_args(args)
    arguments = Arguments.new(args)
    command   = arguments.command
    abort help_msg unless command
    abort "unknown command: #{command}\n#{help_msg}" unless COMMANDS.keys.include?(command)

    if command == 'help'
      STDERR.puts help_msg
      exit 0
    end

    arguments
  end

  def homebrew_prefix
    ENV['HOMEBREW_PREFIX'] || `brew --prefix`.chomp
  end

  def expand_formula(name, version, use_homebrew_ruby=false)
    klass           = 'Gem' + name.capitalize.gsub(/[-_.\s]([a-zA-Z0-9])/) { $1.upcase }.gsub('+', 'x')
    user_gemrc      = "#{ENV['HOME']}/.gemrc"
    template_file   = File.expand_path('../formula.rb.erb', __FILE__)
    template        = ERB.new(File.read(template_file))
    template.result(binding)
  end

  def with_temp_formula(name, version, use_homebrew_ruby)
    filename = File.join Dir.tmpdir, "gem-#{name}.rb"

    open(filename, 'w') do |f|
      f.puts expand_formula(name, version, use_homebrew_ruby)
    end

    yield filename
  ensure
    File.unlink filename
  end

  def homebrew_ruby?(ruby_flag)
    File.exist?("#{homebrew_prefix}/opt/ruby") &&
      ruby_flag.nil? || ruby_flag == HOMEBREW_RUBY_FLAG
  end

  def run(args = ARGV)
    arguments = process_args(args)
    name      = arguments.gem
    version   = fetch_version(name, arguments.supplied_version)
    with_temp_formula(name, version, homebrew_ruby?(arguments.ruby_flag)) do |filename|
      case arguments.command
      when "formula"
        $stdout.puts File.read(filename)
      else
        system "brew #{arguments.to_args.shelljoin} #{filename}"
        exit $?.exitstatus unless $?.success?
      end
    end
  end
end
