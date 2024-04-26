require 'chronicle/etl'
require 'chronicle/models'

module Chronicle
  module Imessage
    class ImessageTransformer < Chronicle::ETL::Transformer
      register_connector do |r|
        r.source = :imessage
        r.type = :message
        r.strategy = :local_db
        r.description = 'a row from a local imessage database'
        r.from_schema = :extraction
        r.to_schema = :chronicle
      end

      def transform(record)
        participants = record.extraction.meta[:participants].map { |p| build_identity(record.data, p) }
        my_identity = build_identity_mine(record.data, record.extraction.meta[:my_icloud_account],
          record.extraction.meta[:my_phone_contact])

        build_action(record.data, my_identity, participants)
      end

      private

      def build_action(message, my_identity, participants)
        if message['is_from_me'] == 1
          participants -= [my_identity]
          agent = my_identity
          consumers = participants
        else
          agent = participants.select { |p| p.slug == message['id'] }.first
          consumers = participants - [agent] + [my_identity]
        end

        raise Chronicle::ETL::UntransformableRecordError, 'Could not find agent' unless agent

        Chronicle::Models::CommunicateAction.new do |r|
          r.end_time = Time.at(ios_timestamp_to_unix(message['date'].to_i / 1_000_000_000))
          r.source = entity_source(message['service'])
          r.source_id = message['guid']

          r.agent = agent
          r.object = build_message(message, consumers)
          r.dedupe_on = [%i[source source_id type]]
        end
      end

      def build_message(message, consumers)
        Chronicle::Models::Message.new do |r|
          # TODO: handle text that's in `attributedBody`
          r.text = normalized_body(message)
          r.source = 'imessage'
          r.source_id = message['guid']
          r.recipient = consumers
          r.dedupe_on = [%i[source source_id type]]
        end
      end

      def build_identity_mine(message, my_icloud_account, my_phone_contact)
        case agent_source(message['service'])
        when 'icloud'
          build_identity_mine_icloud(my_icloud_account)
        when 'phone'
          build_identity_mine_phone(my_phone_contact)
        end
      end

      def build_identity_mine_icloud(icloud_account)
        unless icloud_account
          raise(Chronicle::ETL::UntransformableRecordError,
            'Could not build record due to missing iCloud details. Please provide them through the extractor settings.')
        end

        Chronicle::Models::Person.new do |r|
          r.name = icloud_account[:display_name]
          r.source = 'icloud'
          r.slug = icloud_account[:id]
          r.source_id = icloud_account[:dsid]
          r.dedupe_on = [%i[type source source_id]]
        end
      end

      def build_identity_mine_phone(phone_account)
        unless phone_account
          raise(Chronicle::ETL::UntransformableRecordError,
            'Could not build record due to missing phone details. Please provide them through the extractor settings.')
        end

        Chronicle::Models::Person.new do |r|
          r.name = phone_account[:name]
          r.source = 'phone'
          r.slug = phone_account[:phone_number]
          r.dedupe_on = [%i[type source slug]]
        end
      end

      def build_identity(message, identity)
        Chronicle::Models::Person.new do |r|
          r.name = identity['full_name']
          r.source = agent_source(message['service'])
          r.slug = identity['id']
          r.dedupe_on = [%i[type source slug]]
        end
      end

      def entity_source(service)
        service ? service.downcase : 'imessage'
      end

      def agent_source(service)
        case service
        # an SMS message is on the 'sms' provider but the provider of the identity used to send it is 'phone'
        when 'SMS'then 'phone'
        # similarly, 'imessage' provider for messages, 'icloud' provider for identity of sender
        when 'iMessage' then 'icloud'
        else 'icloud'
        end
      end

      # FIXME: refactor to shared
      def ios_timestamp_to_unix(ts)
        ts + 978_307_200
      end

      def unix_to_ios_timestamp(ts)
        ts - 978_307_200
      end

      def normalized_body(message)
        message['text'] || normalize_attributed_body(message['attributedBody'])
      end

      # Based on https://github.com/kndonlee/meds/blob/224be297e8e709e6a52aca5fa05ec42d34af1aef/all_messages.rb#L31
      def normalize_attributed_body(body)
        return unless body

        attributed_body = body.force_encoding('UTF-8').encode('UTF-8', invalid: :replace)

        return unless attributed_body.include?('NSNumber')

        attributed_body = attributed_body.split('NSNumber')[0]
        return unless attributed_body.include?('NSString')

        attributed_body = attributed_body.split('NSString')[1]
        return unless attributed_body.include?('NSDictionary')

        attributed_body = attributed_body.split('NSDictionary')[0]
        attributed_body = attributed_body[6..-13]

        if attributed_body =~ /^.[\u0000]/
          attributed_body.gsub(/^.[\u0000]/, '')
        else
          attributed_body
        end
      end

      #   def build_attachment(attachment)
      #     return unless attachment['mime_type']

      #     type, subtype = attachment['mime_type'].split('/')
      #     return unless %w[image audio video].include?(type)
      #     return unless attachment['filename']

      #     attachment_filename = attachment['filename'].gsub('~', Dir.home)
      #     return unless File.exist?(attachment_filename)

      #     attachment_data = ::Chronicle::ETL::Utils::BinaryAttachments.filename_to_base64(filename: attachment_filename,
      #       mimetype: attachment['mime_type'])
      #     if type == 'image'
      #       recognized_text = ::Chronicle::ETL::Utils::TextRecognition.recognize_in_image(filename: attachment_filename)
      #     end

      #     record = ::Chronicle::ETL::Models::Entity.new
      #     record.provider = 'imessage'
      #     record.provider_id = attachment['guid']
      #     record.represents = type
      #     record.title = File.basename(attachment['filename'])
      #     record.metadata[:ocr_text] = recognized_text if recognized_text
      #     record.dedupe_on = [%i[provider provider_id represents]]

      #     attachment = ::Chronicle::ETL::Models::Attachment.new
      #     attachment.data = attachment_data
      #     record.attachments = [attachment]

      #     record
      #   end
    end
  end
end
