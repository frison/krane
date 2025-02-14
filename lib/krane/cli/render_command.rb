# frozen_string_literal: true

module Krane
  module CLI
    class RenderCommand
      OPTIONS = {
        "bindings" => { type: :array, banner: "foo=bar abc=def", desc: 'Bindings for erb' },
        "filenames" => { type: :array, banner: 'config/deploy/production config/deploy/my-extra-resource.yml',
                         required: false, default: [], aliases: 'f', desc: 'Directories and files to render' },
        "stdin" => { type: :boolean, default: false,
                     desc: "[DEPRECATED] Read resources from stdin" },
        "current-sha" => { type: :string, banner: "SHA", desc: "Expose SHA `current_sha` in ERB bindings",
                           lazy_default: '' },
        "partials-dir" => { type: :string, banner: "partials", required:false, default: nil,
                            desc: "First directory to look for partials, before checking `./partials` and `../partials`" },
      }

      def self.from_options(options)
        require 'krane/render_task'
        require 'krane/bindings_parser'
        require 'krane/options_helper'

        bindings_parser = ::Krane::BindingsParser.new
        options[:bindings]&.each { |b| bindings_parser.add(b) }

        filenames = options[:filenames].dup
        filenames << "-" if options[:stdin]
        if filenames.empty?
          raise(Thor::RequiredArgumentMissingError, '--filenames must be set and not empty')
        end

        ::Krane::OptionsHelper.with_processed_template_paths(filenames, render_erb: true) do |paths|
          renderer = ::Krane::RenderTask.new(
            current_sha: options['current-sha'],
            filenames: paths,
            bindings: bindings_parser.parse,
            partials_dir: options['partials-dir'],
          )
          renderer.run!(stream: STDOUT)
        end
      end
    end
  end
end
