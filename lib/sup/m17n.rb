## Multilingualization (m17n) module for sup
module Redwood
  ## main M17n module, to be included into other classes
  ## the 'm' method can be used to translate text via
  ## m("text.key", :text_var => value)
  module M17n
    def m s, o={}
      M17nImpl::M17n[s, o]
    end
  end

  module M17nImpl
    class M17n
      include Singleton

      attr_reader :lang, :base_path, :translations

      ## default language is english
      def initialize lang=:en, base_path="i18n/"
        @lang = lang
        @base_path = base_path
        @translations = {}
        read_language_file @lang
        read_default_language
      end

      def read_language_file lang
        lang_fn = @base_path + "/#{lang}.yaml"
        if File.exists?(lang_fn)
          @translations[lang.to_sym] = YAML::load_file lang_fn
        else
          raise "Language file not found: #{lang_fn}"
        end
      end

      ## default language is english (:en)
      def read_default_language
        read_language_file :en unless @translations[:en]
      end

      ## access translation values via M17n['foo.bar']
      def [] translation_key, replacements = {}
        val = translation_for translation_key, @lang
        val = translation_for(translation_key, :en) unless val # load default translation (english) if none found
        val ||= "No translation found for: #{translation_key}"

        ## substitute values, if needed
        replacements.each do |k,v|
          val = val.gsub "#\{#{k}\}", v.to_s
        end
        val
      end

      def translation_for translation_key, lang
        val = @translations[lang]
        translation_key.split(".").each do |x|
          if val && (val.is_a? Hash)
            val = val[x]
          else
            return nil # value not found within translations
          end
        end
        val
      end
    end
  end
end
