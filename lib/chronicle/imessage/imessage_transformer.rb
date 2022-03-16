require 'chronicle/etl'

module Chronicle
  module Imessage 
    class ImessageTransformer < Chronicle::ETL::Transformer
      register_connector do |r|
        r.provider = 'imessage'
        r.description = 'a row from a local imessage database'
      end

      def transform
        @message = @extraction.data
        @participants = @extraction.meta[:participants]
        @attachments = @extraction.meta[:attachments] || []

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
        record.contains = @attachments.map{ |a| build_attachment(a)}.compact

        record
      end

      def build_attachment(attachment)
        return unless attachment['mime_type']

        type, subtype = attachment['mime_type'].split("/")
        return unless ['image', 'audio', 'video'].include?(type)
        return unless attachment['filename']

        attachment_filename = attachment['filename'].gsub("~", Dir.home)
        return unless File.exist?(attachment_filename)

        attachment_data = ::Chronicle::ETL::Utils::BinaryAttachments.filename_to_base64(filename: attachment_filename, mimetype: attachment['mime_type'])
        recognized_text = ::Chronicle::ETL::Utils::TextRecognition.recognize_in_image(filename: attachment_filename) if type == 'image'

        record = ::Chronicle::ETL::Models::Entity.new
        record.provider = 'imessage'
        record.provider_id = attachment['guid']
        record.represents = type
        record.title = File.basename(attachment['filename'])
        record.metadata[:ocr_text] = recognized_text if recognized_text
        record.dedupe_on = [[:provider, :provider_id, :represents]]

        attachment = ::Chronicle::ETL::Models::Attachment.new
        attachment.data = attachment_data
        record.attachments = [attachment]

        record
      end

      def build_identity identity
        raise(Chronicle::ETL::UntransformableRecordError, "Could not build record due to missing identity data") unless identity

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
        case identity_provider(@message['service'])
        when 'icloud'
          build_identity_mine_icloud
        when 'phone'
          build_identity_mine_phone
        end
      end

      def build_identity_mine_icloud
        icloud_account = @extraction.meta[:my_icloud_account]
        raise(Chronicle::ETL::UntransformableRecordError, "Could not build record due to missing iCloud details. Please provide them through the extractor settings.") unless icloud_account

        record = ::Chronicle::ETL::Models::Entity.new({
          represent: 'identity',
          provider: 'icloud',
          provider_id: icloud_account[:dsid],
          title: icloud_account[:display_name],
          slug: icloud_account[:id]
        })
        record.dedupe_on << [:provider, :represents, :slug]
        record
      end

      def build_identity_mine_phone
        phone_account = @extraction.meta[:my_phone_contact]
        raise(Chronicle::ETL::UntransformableRecordError, "Could not build record due to missing phone details. Please provide them through the extractor settings.") unless phone_account

        record = ::Chronicle::ETL::Models::Entity.new({
          represent: 'identity',
          provider: 'phone',
          title: phone_account[:name],
          slug: phone_account[:phone_number]
        })
        record.dedupe_on << [:provider, :represents, :slug]
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
