# frozen_string_literal: true

require 'test_helper'

class TemplateSetsTest < KubernetesDeploy::TestCase
	def valid_template_sets_is_valid
		template_paths = [
			fixture_path("hello-cloud"),
			File.join(fixture_path("ejson-cloud"), "secrets.ejson")
		]
		byebug
		template_sets = KubernetesDeploy::TemplateSets.new_from_dirs_and_files(
			paths: template_paths,
			logger: logger,
			current_sha: "12345678",
			bindings: {}
		)

		assert_equal(template_sets.validate, [1])
	end
end
