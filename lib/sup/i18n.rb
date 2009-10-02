# internationalization (i18n) module for sup
module Redwood

  class I18n
    include Singleton

    attr_reader :lang, :base_path, :translations

    ## default language is english
    def initialize lang=:en, base_path="i18n/"
      @lang = lang
      @base_path = base_path
      read_language_file
    end

    def read_language_file
      lang_fn = @base_path + "/#{@lang}.yaml"
      @translations = YAML::load_file lang_fn
    end

    ## access translation values via I18n['foo.bar']
    def [] translation_key, replacements = {}
      val = @translations
      translation_key.split(".").each do |x|
        if val.is_a? Hash
          val = val[x]
        end
      end
      ## substitute values, if needed
      replacements.each do |k,v|
        val = val.gsub "#\{#{k}\}", v.to_s
      end
      val
    end
  end

end
