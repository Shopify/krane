# frozen_string_literal: true

module Krane
  class AnnotationsParser
    def self.parse(string)
      return nil if string.strip.empty?
      
      # ie. transforming "pod,ingress k1:v1,k2:v2" to 
      # { "pod" => {"k1"=>"v1", "k2"=>"v2"}, "ingress" => {"k1"=>"v1", "k2"=>"v2"}}
      resources, string_annotations = string.split(' ') # TODO: catch errors; create a validate fn?
      annotation_hash = string_annotations.split(',').each_with_object({}) do |annotation, hash|
        ann_value_pair = annotation.split(':')
        raise ArgumentError, "#{annotation} is not using `annotation:value` format" unless ann_value_pair.size == 2

        hash[ann_value_pair[0]] = ann_value_pair[1]
      end

      resources.split(',').each_with_object({}) do |resource, hash|
        hash[resource.downcase] = annotation_hash
      end
    end
  end
end
