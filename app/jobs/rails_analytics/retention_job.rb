# frozen_string_literal: true

module RailsAnalytics
  class RetentionJob < ActiveJob::Base
    queue_as :default

    RETENTION_PERIOD = 6.months

    def perform
      cutoff = RETENTION_PERIOD.ago
      deleted_visits = 0
      deleted_events = 0

      Visit.where(Visit.arel_table[:started_at].lt(cutoff)).find_in_batches(batch_size: 1000) do |batch|
        visit_ids = batch.map(&:id)

        events_count = Event.where(visit_id: visit_ids).delete_all
        visits_count = Visit.where(id: visit_ids).delete_all

        deleted_events += events_count
        deleted_visits += visits_count
      end

      Rails.logger.info "[rails_analytics] RetentionJob: deleted #{deleted_visits} visits and #{deleted_events} events older than #{cutoff}"
    end
  end
end