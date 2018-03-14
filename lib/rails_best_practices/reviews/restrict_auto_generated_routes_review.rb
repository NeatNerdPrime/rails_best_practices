# encoding: utf-8
# frozen_string_literal: true

module RailsBestPractices
  module Reviews
    # Review a route file to make sure all auto-generated routes have corresponding actions in controller.
    #
    # See the best practice details here https://rails-bestpractices.com/posts/2011/08/19/restrict-auto-generated-routes/
    #
    # Implementation:
    #
    # Review process:
    #   check all resources and resource method calls,
    #   compare the generated routes and corresponding actions in controller,
    #   if there is a route generated, but there is not action in that controller,
    #   then you should restrict your routes.
    class RestrictAutoGeneratedRoutesReview < Review
      interesting_nodes :command, :command_call, :method_add_block
      interesting_files ROUTE_FILES
      url 'https://rails-bestpractices.com/posts/2011/08/19/restrict-auto-generated-routes/'

      def resource_methods
        if Prepares.configs['config.api_only']
          %w(show create update destroy)
        else
          %w(show new create edit update destroy)
        end
      end

      def resources_methods
        resource_methods + ['index']
      end

      def initialize(options={})
        super(options)
        @namespaces = []
        @resource_controllers = []
      end

      # check if the generated routes have the corresponding actions in controller for rails routes.
      add_callback :start_command, :start_command_call do |node|
        if 'resources' == node.message.to_s
          if (mod = module_option(node))
            @namespaces << mod
          end
          check_resources(node)
          @resource_controllers << node.arguments.all.first.to_s
        elsif 'resource' == node.message.to_s
          check_resource(node)
          @resource_controllers << node.arguments.all.first.to_s
        end
      end

      add_callback :end_command do |node|
        if 'resources' == node.message.to_s
          @resource_controllers.pop
          @namespaces.pop if module_option(node)
        elsif 'resource' == node.message.to_s
          @resource_controllers.pop
        end
      end

      # remember the namespace.
      add_callback :start_method_add_block do |node|
        case node.message.to_s
        when 'namespace'
          @namespaces << node.arguments.all.first.to_s if check_method_add_block?(node)
        when 'resources', 'resource'
          @resource_controllers << node.arguments.all.first.to_s if check_method_add_block?(node)
        when 'scope'
          if check_method_add_block?(node) && (mod = module_option(node))
            @namespaces << mod
          end
        else
        end
      end

      # end of namespace call.
      add_callback :end_method_add_block do |node|
        if check_method_add_block?(node)
          case node.message.to_s
          when 'namespace'
            @namespaces.pop
          when 'resources', 'resource'
            @resource_controllers.pop
          when 'scope'
            if check_method_add_block?(node) && module_option(node)
              @namespaces.pop
            end
          end
        end
      end

      def check_method_add_block?(node)
        :command == node[1].sexp_type || (:command_call == node[1].sexp_type && 'map' != node.receiver.to_s)
      end

      private

        # check resources call, if the routes generated by resources does not exist in the controller.
        def check_resources(node)
          _check(node, resources_methods)
        end

        # check resource call, if the routes generated by resources does not exist in the controller.
        def check_resource(node)
          _check(node, resource_methods)
        end

        # get the controller name.
        def controller_name(node)
          if option_with_hash(node)
            option_node = node.arguments.all[1]
            if hash_key_exist?(option_node,'controller')
              name = option_node.hash_value('controller').to_s
            else
              name = node.arguments.all.first.to_s.gsub('::', '').tableize
            end
          else
            name = node.arguments.all.first.to_s.gsub('::', '').tableize
          end
          namespaced_class_name(name)
        end

        # get the class name with namespace.
        def namespaced_class_name(name)
          class_name = "#{name.split("/").map(&:camelize).join("::")}Controller"
          if @namespaces.empty?
            class_name
          else
            @namespaces.map { |namespace| "#{namespace.camelize}::" }.join('') + class_name
          end
        end

        def _check(node, methods)
          controller_name = controller_name(node)
          return unless Prepares.controllers.include? controller_name
          _methods = _methods(node, methods)
          unless _methods.all? { |meth| Prepares.controller_methods.has_method?(controller_name, meth) }
            prepared_method_names = Prepares.controller_methods.get_methods(controller_name).map(&:method_name)
            only_methods = (_methods & prepared_method_names).map { |meth| ":#{meth}" }
            routes_message = if only_methods.size > 3
                               "except: [#{(methods.map { |meth| ":" + meth } - only_methods).join(', ')}]"
                             else
                               "only: [#{only_methods.join(', ')}]"
                             end
            add_error "restrict auto-generated routes #{friendly_route_name(node)} (#{routes_message})"
          end
        end

        def _methods(node, methods)
          if option_with_hash(node)
            option_node = node.arguments.all[1]
            if hash_key_exist?(option_node, 'only')
              option_node.hash_value('only').to_s == 'none' ? [] : Array(option_node.hash_value('only').to_object)
            elsif hash_key_exist?(option_node, 'except')
              if option_node.hash_value('except').to_s == 'all'
                []
              else
                (methods - Array(option_node.hash_value('except').to_object))
              end
            else
              methods
            end
          else
            methods
          end
        end

        def module_option(node)
          option_node = node.arguments[1].last
          if option_node && option_node.sexp_type == :bare_assoc_hash && hash_key_exist?(option_node, 'module')
            option_node.hash_value('module').to_s
          end
        end

        def option_with_hash(node)
          node.arguments.all.size > 1 && :bare_assoc_hash == node.arguments.all[1].sexp_type
        end

        def hash_key_exist?(node, key)
          node.hash_keys && node.hash_keys.include?(key)
        end

        def friendly_route_name(node)
          if @resource_controllers.last == node.arguments.to_s
            [@namespaces.join('/'), @resource_controllers.join('/')].delete_if(&:blank?).join('/')
          else
            [@namespaces.join('/'), @resource_controllers.join('/'), node.arguments.to_s].delete_if(&:blank?).join('/')
          end
        end
    end
  end
end
