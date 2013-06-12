require "test_helper"

require "sup"
require "psych"

describe "Sup's YAML util" do
  describe "Module#yaml_properties" do
    def build_class_with_name name, &b
      Class.new do
        meta_cls = class << self; self; end
        meta_cls.send(:define_method, :name) { name }
        class_exec(&b) unless b.nil?
      end
    end

    after do
      Psych.load_tags = {}
      Psych.dump_tags = {}
    end

    it "defines YAML tag for class" do
      cls = build_class_with_name 'Cls' do
        yaml_properties
      end

      expected_yaml_tag = "!supmua.org,2006-10-01/Cls"

      Psych.load_tags[expected_yaml_tag].must_equal cls
      Psych.dump_tags[cls].must_equal expected_yaml_tag

    end

    it "Loads legacy YAML format as well" do
      cls = build_class_with_name 'Cls' do
        yaml_properties :id
        attr_accessor :id
        def initialize id
          @id = id
        end
      end

      Psych.load_tags["!masanjin.net,2006-10-01/Cls"].must_equal cls

      yaml = <<EOF
--- !masanjin.net,2006-10-01/Cls
id: ID
EOF
      loaded = YAML.load(yaml)

      loaded.id.must_equal 'ID'
      loaded.must_be_kind_of cls
    end

    it "Dumps & loads w/ state re-initialized" do
      cls = build_class_with_name 'Cls' do
        yaml_properties :id
        attr_accessor :id
        attr_reader :flag

        def initialize id
          @id = id
          @flag = true
        end
      end

      instance = cls.new 'ID'

      dumped = YAML.dump(instance)
      loaded = YAML.load(dumped)

      dumped.must_equal <<-EOF
--- !supmua.org,2006-10-01/Cls
id: ID
      EOF

      loaded.id.must_equal 'ID'
      assert loaded.flag
    end
  end
end
