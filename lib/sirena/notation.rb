# frozen_string_literal: true

require_relative "error/notation_registration_error"
require_relative "error/pipeline_error"
require_relative "notation/entry"
require_relative "notation/parsed"
require_relative "notation/plugin_failure"

module Sirena
  # The registry of diagram notations. A notation is any object answering:
  #
  # - `id`: a lowercase Symbol, `/\A[a-z][a-z0-9_]*\z/`
  # - `extensions`: a frozen Array of lowercase dotted Strings, may be empty
  # - `claims?(source)`: true or false; never raises for any String
  # - `parse(source)`: returns a {Parsed}; an optional `logger:` keyword,
  #   declared by that name (`**options` does not count), receives the
  #   engine's progress lines under `verbose`
  # - `types`: an Array of Symbols
  #
  # Loading a file that calls {register} is all a consumer does to add one.
  module Notation
    ID_PATTERN = /\A[a-z][a-z0-9_]*\z/
    EXTENSION_PATTERN = /\A\.[a-z0-9_+-]+\z/
    DEFAULT_ID = :mermaid
    # The members `register` checks after `id`, in order, each by the
    # private method named here. `register` has no other plugin access.
    MEMBER_CHECKS = {
      extensions: :validated_extensions,
      claims?: :validated_claims,
      parse: :validated_parse,
      types: :validate_types,
    }.freeze
    private_constant :EXTENSION_PATTERN, :DEFAULT_ID, :MEMBER_CHECKS,
                     :Entry

    class << self
      # Registers a notation, validating everything before recording
      # anything. `claims?` and `parse` take exactly one positional argument.
      # Register at load time: the registry is not thread-safe.
      #
      # A plugin is trusted code: this refuses honest mistakes, not one that
      # overrides core methods (`method`, `is_a?`) to misreport itself.
      #
      # @param plugin [#id, #extensions, #claims?, #parse, #types]
      # @return [void]
      # @raise [NotationRegistrationError] naming the first broken member,
      #   including one whose reader raises
      def register(plugin)
        member = :id
        id = validated_id(plugin)
        checked = MEMBER_CHECKS.to_h do |name, check|
          member = name
          [name, send(check, plugin, id)]
        end
        record(plugin, id, checked[:extensions])
      rescue NotationRegistrationError then raise
      rescue PluginFailure
        raise malformed(member, id)
      end

      # @param id [Symbol, String]
      # @return [#parse] the registered notation
      # @raise [Engine::PipelineError] when `id` is not a Symbol or String,
      #   or names no registered notation
      def fetch(id)
        entry = lookup(id)
        return entry.plugin if entry

        raise Engine::PipelineError,
              "Unknown notation: #{printable(id)}. " \
              "Valid notations: #{ids.sort.join(', ')}"
      end

      # @return [Array<Symbol>] registered ids, in registration order
      def ids
        entries.keys
      end

      # @return [Array] registered notations, in registration order
      def plugins
        entries.values.map(&:plugin)
      end

      # @return [Array<String>] every registered extension
      def extensions
        entries.values.flat_map(&:extensions)
      end

      # @param extension [String] lowercase, dotted
      # @return [Object, nil] the notation that claims it
      def for_extension(extension)
        entries.each_value do |entry|
          return entry.plugin if entry.extensions.include?(extension)
        end
        nil
      end

      # Picks the notation for one render. The first signal that yields one
      # wins: the explicit id, then the path's extension, then the first
      # notation (in registration order) that claims the source, then Mermaid.
      #
      # @param explicit [Symbol, String, nil]
      # @param path [String, nil]
      # @param source [String]
      # @return [#parse]
      # @raise [Engine::PipelineError] for an invalid or unknown explicit id
      def resolve(explicit:, path:, source:)
        case explicit
        when nil
          for_extension(extension_of(path)) ||
            plugins.find { |plugin| plugin.claims?(source) } ||
            fetch(DEFAULT_ID)
        else
          fetch(explicit)
        end
      end

      private

      def entries
        @entries ||= {}
      end

      def record(plugin, id, declared)
        entries[id] = Entry.new(plugin, declared)
        nil
      end

      def malformed(member, id)
        owner = id ? "Notation #{id}" : "Notation"
        NotationRegistrationError.new("#{owner}: #{member} is malformed")
      end

      # A path is a hint, never a reason to fail: one that cannot name a
      # file (NUL byte, invalid or non-ASCII-compatible encoding) has no
      # extension, and the source decides.
      def extension_of(path)
        name = String === path ? String.new(path) : path.to_s
        return "" unless name.encoding.ascii_compatible? && name.valid_encoding?
        return "" if name.include?("\0")

        File.extname(name).downcase(:ascii)
      end

      def takes_no_arguments?(plugin, name)
        parameter_kinds(plugin, name).slice(:req, :keyreq).empty?
      end

      # Exactly one positional parameter; optional keywords are fine.
      def one_positional?(plugin, name)
        parameter_kinds(plugin, name)
          .slice(:req, :opt, :rest, :keyreq) == { req: 1 }
      end

      def parameter_kinds(plugin, name)
        plugin.method(name).parameters.map(&:first).tally
      end

      def printable(id)
        utf8(String === id ? String.new(id) : id.to_s)
      end

      def utf8(string)
        string.encode("UTF-8", invalid: :replace, undef: :replace).scrub
      rescue Encoding::ConverterNotFoundError
        string.b.force_encoding(Encoding::UTF_8).scrub
      end

      def lookup(id)
        case id
        when Symbol then entries[id]
        when String then entries[string_id(id)]
        else
          raise Engine::PipelineError,
                "Invalid notation: #{safe_inspect(id)}. " \
                "Notation must be a Symbol or String"
        end
      end

      def string_id(id)
        return unless String.instance_method(:valid_encoding?).bind_call(id)

        String.instance_method(:to_sym).bind_call(id)
      end

      def safe_inspect(value)
        utf8(String.new(value.inspect))
      rescue PluginFailure
        "<uninspectable>"
      end

      def validated_id(plugin)
        id = member(plugin, :id)
        unless Symbol === id && matches?(id.to_s, ID_PATTERN)
          raise NotationRegistrationError,
                "Notation id must be a lowercase Symbol matching " \
                "#{ID_PATTERN.inspect}, got #{id.inspect}"
        end
        return id unless entries.key?(id)

        raise NotationRegistrationError, "Notation #{id} is already registered"
      end

      def validated_extensions(plugin, id)
        declared = member(plugin, :extensions, id)
        check_extension_shape!(declared, id)
        snapshot = declared.map { |ext| String.new(ext).freeze }.freeze
        check_extensions_free!(snapshot, id)
        snapshot
      end

      def check_extension_shape!(declared, id)
        return if Array === declared && declared.frozen? &&
          declared.all? { |ext| extension?(ext) }

        raise NotationRegistrationError,
              "Notation #{id}: extensions must be a frozen Array of " \
              "lowercase dotted Strings, got #{declared.inspect}"
      end

      def extension?(ext)
        String === ext && matches?(String.new(ext), EXTENSION_PATTERN)
      end

      # Matching raises on a broken or non-ASCII-compatible string; both are
      # plain mismatches here.
      def matches?(string, pattern)
        string.encoding.ascii_compatible? && string.valid_encoding? &&
          string.match?(pattern)
      end

      def check_extensions_free!(declared, id)
        taken = declared.find do |ext|
          extensions.include?(ext) || declared.count(ext) > 1
        end
        return unless taken

        raise NotationRegistrationError,
              "Notation #{id}: extension #{taken} is already claimed"
      end

      def validated_claims(plugin, id)
        require_one_positional(plugin, :claims?, id)
      end

      def validated_parse(plugin, id)
        require_one_positional(plugin, :parse, id)
      end

      def validate_types(plugin, id)
        types = member(plugin, :types, id)
        return if Array === types && types.all?(Symbol)

        raise NotationRegistrationError,
              "Notation #{id}: types must be an Array of Symbols, " \
              "got #{types.inspect}"
      end

      def member(plugin, name, id = nil)
        owner = id ? "Notation #{id}" : "Notation"
        unless public_member?(plugin, name)
          raise NotationRegistrationError, "#{owner} must respond to #{name}"
        end
        return plugin.public_send(name) if takes_no_arguments?(plugin, name)

        raise NotationRegistrationError,
              "#{owner}: #{name} must take no arguments"
      end

      def require_one_positional(plugin, name, id)
        unless public_member?(plugin, name)
          raise NotationRegistrationError,
                "Notation #{id} must respond to #{name}"
        end
        return if one_positional?(plugin, name)

        raise NotationRegistrationError,
              "Notation #{id}: #{name} must take one positional argument"
      end

      # Object's own respond_to?, so a plugin cannot answer for itself; a
      # BasicObject or a raising respond_to_missing? counts as "no".
      def public_member?(plugin, name)
        Object.instance_method(:respond_to?).bind_call(plugin, name)
      rescue StandardError then false
      end
    end
  end
end
