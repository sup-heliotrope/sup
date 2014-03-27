## simple singleton module. far less complete and insane than the ruby standard
## library one, but it automatically forwards methods calls and allows for
## constructors that take arguments.
##
## classes that inherit this can define initialize. however, you cannot call
## .new on the class. To get the instance of the class, call .instance;
## to create the instance, call init.
module Redwood
  module Singleton
    module ClassMethods
      def instance; @instance; end
      def instantiated?; defined?(@instance) && !@instance.nil?; end
      def deinstantiate!; @instance = nil; end
      def method_missing meth, *a, &b
        raise "no #{name} instance defined in method call to #{meth}!" unless defined? @instance

        ## if we've been deinstantiated, just drop all calls. this is
        ## useful because threads that might be active during the
        ## cleanup process (e.g. polling) would otherwise have to
        ## special-case every call to a Singleton object
        return nil if @instance.nil?

        # Speed up further calls by defining a shortcut around method_missing
        if meth.to_s[-1,1] == '='
          # Argh! Inconsistency! Setters do not work like all the other methods.
          class_eval "def self.#{meth}(a); @instance.send :#{meth}, a; end"
        else
          class_eval "def self.#{meth}(*a, &b); @instance.send :#{meth}, *a, &b; end"
        end

        @instance.send meth, *a, &b
      end
      def init *args
        raise "there can be only one! (instance)" if instantiated?
        @instance = new(*args)
      end
    end

    def self.included klass
      klass.private_class_method :allocate, :new
      klass.extend ClassMethods
    end
  end
end
