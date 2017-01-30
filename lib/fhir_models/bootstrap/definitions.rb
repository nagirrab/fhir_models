require 'tempfile'
module FHIR
  class Definitions
    extend FHIR::Deprecate
    @@defns = File.expand_path '../definitions', File.dirname(File.absolute_path(__FILE__))
    @@types = nil
    @@resources = nil
    @@profiles = nil
    @@extensions = nil
    @@expansions = nil
    @@valuesets = nil
    @@search_params = nil

    # ----------------------------------------------------------------
    #  Types
    # ----------------------------------------------------------------

    def self.types
      @@types ||= begin
        # load the types
        filename = File.join(@@defns, 'structures', 'profiles-types.json')
        raw = File.open(filename, 'r:UTF-8', &:read)
        JSON.parse(raw)['entry'].map { |e| e['resource'] }
      end
    end
    deprecate :load_types, :types
    private_class_method :types

    def self.primitive_types
      # primitive data types start with a lowercase letter
      @primitive_types ||= types.select { |t| t['id'][0] =~ /[a-z]/ }
    end
    deprecate :get_primitive_types, :primitive_types

    def self.complex_types
      # complex data types start with an uppercase letter
      # and we'll filter out profiles on types (for example, Age is a profile on Quantity)
      @complex_types ||= types.select { |t| (t['id'][0] =~ /[A-Z]/) && (t['id'] == t['snapshot']['element'].first['path']) }
    end
    deprecate :get_complex_types, :complex_types

    def self.type_definition(type_name)
      return nil if type_name.nil?
      definition = types.find { |x| x['xmlId'] == type_name || x['name'] == type_name || x['url'] == type_name }
      return nil if definition.nil?
      FHIR::StructureDefinition.new(definition)
    end
    deprecate :get_type_definition, :type_definition

    # ----------------------------------------------------------------
    #  Resources, Profiles, Extensions
    # ----------------------------------------------------------------

    def self.resources
      @@resources ||= begin
        # load the resources
        filename = File.join(@@defns, 'structures', 'profiles-resources.json')
        raw = File.open(filename, 'r:UTF-8', &:read)
        JSON.parse(raw)['entry'].map { |e| e['resource'] }
      end
    end
    deprecate :load_resources, :resources
    private_class_method :resources

    def self.resource_definitions
      resources
    end
    deprecate :get_resource_definitions, :resource_definitions

    def self.resource_definition(resource_name)
      return nil if resource_name.nil?
      d = resources.find { |x| x['xmlId'] == resource_name || x['name'] == resource_name || x['url'] == resource_name }
      return nil if d.nil?
      FHIR::StructureDefinition.new(d)
    end
    deprecate :get_resource_definition, :resource_definition

    def self.profiles
      @@profiles ||= begin
        # load the built-in profiles
        filename = File.join(@@defns, 'structures', 'profiles-others.json')
        raw = File.open(filename, 'r:UTF-8', &:read)
        JSON.parse(raw)['entry'].map { |e| e['resource'] }
      end
    end
    deprecate :load_profiles, :profiles
    private_class_method :profiles

    def self.extensions
      @@extensions ||= begin
        # load the built-in extensions
        filename = File.join(@@defns, 'structures', 'extension-definitions.json')
        raw = File.open(filename, 'r:UTF-8', &:read)
        JSON.parse(raw)['entry'].map { |e| e['resource'] }
      end
    end
    deprecate :load_extensions, :extensions
    private_class_method :extensions

    def self.extension_definition(extension_name)
      return nil if extension_name.nil?
      extension = extensions.find { |x| x['xmlId'] == extension_name || x['name'] == extension_name || x['url'] == extension_name }
      return nil if extension.nil?
      FHIR::StructureDefinition.new(extension)
    end
    deprecate :get_extension_definition, :extension_definition

    # Get the basetype (String) for a given profile or extension.
    def self.basetype(uri)
      return nil if uri.nil?
      defn = profiles.detect { |x| x['url'] == uri } || extensions.detect { |x| x['url'] == uri }
      return nil if defn.nil?
      defn['baseType']
    end
    deprecate :get_basetype, :basetype

    # Get the StructureDefinition for a given profile.
    def self.profile(uri)
      return nil if uri.nil?
      defn = profiles.detect { |x| x['url'] == uri } || extensions.detect { |x| x['url'] == uri }
      return nil if defn.nil?
      FHIR::StructureDefinition.new(defn)
    end
    deprecate :get_profile, :profile

    def self.profiles_for_resource(resource_name)
      return nil if resource_name.nil?
      profiles.select { |x| x['baseType'] == resource_name }.map { |x| FHIR::StructureDefinition.new(x) }
    end
    deprecate :get_profiles_for_resource, :profile_for_resource

    # Get a dynamically generated class for a given profile.
    def self.get_profile_class(uri)
      return nil if uri.nil?
      load_profiles
      load_extensions

      defn = @@profiles.select { |x| x['url'] == uri }.first
      defn = @@extensions.select { |x| x['url'] == uri }.first if defn.nil?

      klass = nil
      unless defn.nil?
        generator = FHIR::Boot::Generator.new(false)
        type = defn['baseType']
        id = defn['id'].gsub(/-|_/, '').capitalize
        defn['id'] = type # override profile id with baseType name for generator
        template = generator.generate_class([type], defn)
        f = Tempfile.new(["profile-#{id}", '.rb'])
        f.write("module FHIR\n")
        f.write("module Profile\n")
        f.write("module #{id}\n")
        f.write(template.to_s)
        3.times { f.write("\nend") }
        f.close
        begin
          # load the profiled class
          load f
          # set the return class type
          klass = Object.const_get("FHIR::Profile::#{id}::#{type}")
        rescue
          FHIR.logger.error "Failed to generate class for profile #{uri}"
        end
        # unlink the file so it can be garbage collected
        f.unlink
      end
      klass
    end

    # ----------------------------------------------------------------
    #  ValueSet Code Expansions
    # ----------------------------------------------------------------

    def self.expansions
      @@expansions ||= begin
        # load the expansions
        filename = File.join(@@defns, 'valuesets', 'expansions.json')
        raw = File.open(filename, 'r:UTF-8', &:read)
        JSON.parse(raw)['entry'].map { |e| e['resource'] }
      end
    end
    deprecate :load_expansions, :expansions

    def self.valuesets
      @@valuesets ||= begin
        # load the valuesets
        filename = File.join(@@defns, 'valuesets', 'valuesets.json')
        raw = File.open(filename, 'r:UTF-8', &:read)
        JSON.parse(raw)['entry'].map { |e| e['resource'] }
      end
    end

    # Get codes (Array of Strings) for a given expansion.
    def self.get_codes(uri)
      return nil if uri.nil?
      codes = nil
      valueset = expansions.select { |x| x['url'] == uri }.first
      unless valueset.nil?
        codes = {}
        if !valueset['expansion'].nil? && !valueset['expansion']['contains'].nil?
          keys = valueset['expansion']['contains'].map { |x| x['system'] }.uniq
          keys.each { |x| codes[x] = [] }
          valueset['expansion']['contains'].each { |x| codes[x['system']] << x['code'] }
        end
        if !valueset['compose'].nil? && !valueset['compose']['include'].nil?
          included_systems = valueset['compose']['include'].map { |x| x['system'] }.uniq
          included_systems.each { |x| codes[x] = [] unless codes.keys.include?(x) }
          systems = valuesets.select { |x| x['resourceType'] == 'CodeSystem' && included_systems.include?(x['url']) }
          systems.each do |x|
            x['concept'].each { |y| codes[x['url']] << y['code'] } if x['concept']
          end
        end
      end
      codes
    end

    # Get the "display" (human-readable title) for a given code in a code system (uri)
    # If one can't be found, return nil
    def self.get_display(uri, code)
      return nil if uri.nil? || code.nil?
      load_expansions
      valuesets = @@expansions.select { |ex| ex['compose']['include'].detect { |i| i['system'] == uri } }
      valuesets += @@valuesets.select { |vs| vs['url'] == uri }
      code_hash = nil
      valuesets.each do |valueset|
        if valueset['expansion'] && valueset['expansion']['contains']
          # This currently only matches 'expansions', not 'valuesets'
          code_hash = valueset['expansion']['contains'].detect { |contained| contained['system'] == uri && contained['code'] == code }
        elsif valueset['compose'] && valueset['compose']['include']
          # I'm not sure this branch ever matches, see comment below.
          valueset['compose']['include'].each do |code_system|
            code_hash = code_system['concept'].detect { |con| con['code'] == code } if code_system['concept']
            break if code_hash
          end
        elsif valueset['concept']
          # This currently only matches 'valuesets', not 'expansions'
          code_hash = valueset['concept'].detect { |vs| vs['code'] == code }
        end
        break if code_hash
      end
      code_hash['display'] if code_hash
    end

    # ----------------------------------------------------------------
    #  Search Params
    # ----------------------------------------------------------------

    def self.search_params
      @@search_params ||= begin
        # load the search parameters
        filename = File.join(@@defns, 'structures', 'search-parameters.json')
        raw = File.open(filename, 'r:UTF-8', &:read)
        JSON.parse(raw)['entry'].map { |e| e['resource'] }
      end
    end
    deprecate :load_search_params, :search_params
    private_class_method :search_params

    def self.search_parameters(type_name)
      return nil if type_name.nil?
      search_params.select { |p| p['base'].include?(type_name) && p['xpath'] && !p['xpath'].include?('extension') }.map { |p| p['code'] }
    end
    deprecate :get_search_parameters, :search_parameters
  end
end
