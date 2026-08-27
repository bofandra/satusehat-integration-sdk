module Satusehat
    module IntegrationSdk
        module EventStatus
            QUEUED = "QUEUED"
            PROCESSING = "PROCESSING"
            SUCCESS = "SUCCESS"
            WAITING_FOR_CORRECTION = "WAITING_FOR_CORRECTION"
            RATE_LIMITED = "RATE_LIMITED"
            RETRYING = "RETRYING"
            DEAD_LETTER = "DEAD_LETTER"
            CANCELLED = "CANCELLED"

            ALL = [
                QUEUED,
                PROCESSING,
                SUCCESS,
                WAITING_FOR_CORRECTION,
                RATE_LIMITED,
                RETRYING,
                DEAD_LETTER,
                CANCELLED
            ].freeze

            TERMINAL = [
                SUCCESS,
                WAITING_FOR_CORRECTION,
                DEAD_LETTER,
                CANCELLED
            ].freeze
        end
    end
end
