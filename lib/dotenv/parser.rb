require "dotenv/substitutions/variable"
require "dotenv/substitutions/command" if RUBY_VERSION > "1.8.7"

module Dotenv
  class FormatError < SyntaxError; end

  # This class enables parsing of a string for key value pairs to be returned
  # and stored in the Environment. It allows for variable substitutions and
  # exporting of variables.
  class Parser
    @substitutions =
      [Dotenv::Substitutions::Variable, Dotenv::Substitutions::Command]

    LINE = /
      (?:^|\A)              # beginning of line
      \s*                   # leading whitespace
      (?:export\s+)?        # optional export
      ([\w\.]+)             # key
      (?:\s*=\s*?|:\s+?)    # separator
      (                     # optional value begin
        \s*'(?:\\'|[^'])*'  #   single quoted value
        |                   #   or
        \s*"(?:\\"|[^"])*"  #   double quoted value
        |                   #   or
        [^\#\r\n]+          #   unquoted value
      )?                    # value end
      \s*                   # trailing whitespace
      (?:\#.*)?             # optional comment
      (?:$|\z)              # end of line
    /x

    class << self
      attr_reader :substitutions

      def call(string, is_load = false)
        new(string, is_load).call
      end
    end

    def initialize(string, is_load = false)
      @string = string
      @hash = {}
      @is_load = is_load
    end

    def line_parse
      # Convert line breaks to same format
      lines = @string.gsub(/\r\n?/, "\n")
      # Process matches
      lines.scan(LINE).each do |key, value|
        @hash[key] = parse_value(value || "")
      end
      # Process non-matches
      lines.gsub(LINE, "").split(/[\n\r]+/).each do |line|
        parse_line(line)
      end
      @hash
    end

    def yaml_parse
      # Load as YAML
      hash = YAML.load(@string)

      @hash.replace(parse_hash(nil, hash, @hash))
    end

    def call
       if /^---$/ =~ @string
         yaml_parse
       else
         line_parse
       end
    end

    private

    def parse_hash prefix, hash, target
      hash.reduce(target) do |res, (key, value)|
        case value
        when Hash
          parse_hash([prefix, key].compact.join("_"), value, res)
        when Array
          tmp = value.map.with_index {|x, i| [i, x]}.to_h
          parse_hash([prefix, key].compact.join("_"), tmp, res)
        else
          res.merge([prefix, key].compact.join("_").upcase => value.to_s)
        end
      end
    end

    def parse_line(line)
      if line.split.first == "export"
        if variable_not_set?(line)
          raise FormatError, "Line #{line.inspect} has an unset variable"
        end
      end
    end

    def parse_value(value)
      # Remove surrounding quotes
      value = value.strip.sub(/\A(['"])(.*)\1\z/m, '\2')
      maybe_quote = Regexp.last_match(1)
      value = unescape_value(value, maybe_quote)
      value = perform_substitutions(value, maybe_quote)
      value
    end

    def unescape_characters(value)
      value.gsub(/\\([^$])/, '\1')
    end

    def expand_newlines(value)
      value.gsub('\n', "\n").gsub('\r', "\r")
    end

    def variable_not_set?(line)
      !line.split[1..-1].all? { |var| @hash.member?(var) }
    end

    def unescape_value(value, maybe_quote)
      if maybe_quote == '"'
        unescape_characters(expand_newlines(value))
      elsif maybe_quote.nil?
        unescape_characters(value)
      else
        value
      end
    end

    def perform_substitutions(value, maybe_quote)
      if maybe_quote != "'"
        self.class.substitutions.each do |proc|
          value = proc.call(value, @hash, @is_load)
        end
      end
      value
    end
  end
end
