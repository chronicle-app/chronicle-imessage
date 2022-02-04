require 'chronicle/etl'
require 'pry'

module Chronicle
  module Imessage 
    class ImessageTransformer < Chronicle::ETL::Transformer
      register_connector do |r|
        r.provider = 'imessage'
        r.description = 'a row from a local imessage database'
      end

      DEFAULT_OPTIONS = {
      }.freeze

      def initialize(*args)
        super(*args)
        @options = @options.reverse_merge(DEFAULT_OPTIONS)
      end

      def transform
        @message = @extraction.data
        @participants = @extraction.meta[:participants]

        set_actors
        record = build_messaged
        record
      end

      def timestamp
        Time.at(ios_timestamp_to_unix(@message['date'].to_i / 1000000000))
      end

      def id
        @message['guid']
      end

      private

      def set_actors
        me = build_identity_mine
        # Figure out the sender / receiver(s) of a message
        case @message['is_from_me']
        when 1
          @actor = me
          @consumers = @participants.collect{|p| build_identity(p)}
        else
          sender = @participants.select{|p| p['id'] == @message['id']}.first
          receivers = @participants - [sender]

          @consumers = receivers.collect{|p| build_identity(p)}
          @consumers << me
          @actor = build_identity(sender)
        end
      end

      def build_messaged
        record = ::Chronicle::ETL::Models::Activity.new
        record.end_at = timestamp
        record.verb = 'messaged'
        record.provider_id = id
        record.provider = build_provider(@message['service'])
        record.dedupe_on = [[:provider, :verb, :provider_id]]

        record.involved = build_message
        record.actor = @actor

        record
      end

      def build_message
        record = ::Chronicle::ETL::Models::Entity.new
        record.body = @message['text']
        record.provider_id = id
        record.represents = 'message'
        record.provider = build_provider(@message['service'])
        record.dedupe_on = [[:represents, :provider, :provider_id]]

        record.consumers = @consumers

        record
      end

      def build_identity identity
        record = ::Chronicle::ETL::Models::Entity.new({
          represents: 'identity',
          slug: identity['id'],
          title: identity['full_name'],
          provider: identity_provider(@message['service']),
        })
        record.dedupe_on = [[:represents, :slug, :provider]]
        record
      end

      def build_identity_mine
        record = ::Chronicle::ETL::Models::Entity.new({
          represents: 'identity',
          slug: @options[:my_phone_slug],
          title: @options[:my_name],
          provider: identity_provider(@message['service']),
          provider_id: @message['account_guid']
        })
        record.dedupe_on = [[:represents, :slug, :provider], [:represents, :provider, :provider_id]]
        record
      end

      # in the wild, this is either null or sms
      def build_provider service
        service ? service.downcase : 'imessage'
      end

      # FIXME: should probably try to preserve imessage ids instead of imessage
      def identity_provider service
        case service
        # an SMS message is on the 'sms' provider but the provider of the identity used to send it is 'phone'
        when 'SMS'then 'phone'
        # similarly, 'imessage' provider for messages, 'icloud' provider for identity of sender
        when 'iMessage' then 'icloud'
        else 'icloud'
        end
      end

      # FIXME: refactor to shared
      def ios_timestamp_to_unix ts
        ts + 978307200
      end
      def unix_to_ios_timestamp ts
        ts - 978307200
      end
    end
  end
end
