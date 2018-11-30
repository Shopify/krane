# frozen_string_literal: true
require 'kubernetes-deploy/container_logs'

module KubernetesDeploy
  class RemoteLogs
    attr_reader :container_logs

    def initialize(logger:, parent_id:, container_names:, namespace:, context:)
      @logger = logger
      @parent_id = parent_id
      @container_logs = container_names.map do |n|
        ContainerLogs.new(
          logger: logger,
          container_name: n,
          parent_id: parent_id,
          namespace: namespace,
          context: context
        )
      end
    end

    def empty?
      @container_logs.all?(&:empty?)
    end

    def sync
      @container_logs.each(&:sync)
    end

    def print_latest
      @container_logs.each { |cl| cl.print_latest(prefix: @container_logs.length > 1) }
    end

    def print_all(prevent_duplicate: true)
      return if @already_displayed && prevent_duplicate

      if @container_logs.all?(&:empty?)
        @logger.warn("No logs found for #{@parent_id}")
        return
      end

      @container_logs.each do |cl|
        if cl.empty?
          @logger.warn("No logs found for #{@parent_id} container '#{cl.container_name}'")
        else
          @logger.info("Logs from #{@parent_id} container '#{cl.container_name}':")
          cl.print_all
          @logger.blank_line
        end
      end

      @already_displayed = true
    end
  end
end
