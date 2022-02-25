require 'chronicle/etl'
require 'sqlite3'
require 'pry'

module Chronicle
  module Imessage 
    class ImessageExtractor < Chronicle::ETL::Extractor
      register_connector do |r|
        r.provider = 'imessage'
        r.description = 'a local imessage database'
      end

      setting :db, default: File.join(Dir.home, 'Library', 'Messages', 'chat.db'), required: true
      setting :load_attachments, default: false
      setting :only_attachments, default: false

      def prepare
        prepare_data
      end

      def extract
        @messages.each do |message|
          meta = {}
          meta[:participants] = @chats[message['chat_id']]
          meta[:attachments] = @attachments[message['message_id']] if @attachments

          yield Chronicle::ETL::Extraction.new(data: message, meta: meta)
        end
      end

      def results_count
        @messages.count
      end

      private

      def prepare_data
        @db = SQLite3::Database.new(@config.db, results_as_hash: true)
        @messages = load_messages
        @contacts = LocalContacts.new.contacts
        @chats = load_chats

        if @config.load_attachments
          @attachments = load_attachments(@messages.map{|m| m['message_id']})
        end
      end

      def load_messages
        conditions = []

        if @config.until
          load_until_ios = unix_to_ios_timestamp(@config.until.to_i) * 1000000000
          conditions << "date < #{load_until_ios}"
        end

        if @config.since
          load_since_ios = unix_to_ios_timestamp(@config.since.to_i) * 1000000000
          conditions << "date > #{load_since_ios}"
        end

        if @config.only_attachments
          conditions << "cache_has_attachments = true"
        end

        sql = "SELECT * from message as m
          LEFT OUTER JOIN handle as h ON m.handle_id=h.ROWID
          INNER JOIN chat_message_join as cm ON m.ROWID = cm.message_id"

        sql += " WHERE #{conditions.join(" AND ")}" if conditions.any?
        sql += " ORDER BY date DESC"
        sql += " LIMIT #{@config.limit}" if @config.limit

        messages = @db.execute(sql)
      end

      # In ios message schema, a message belongs to a chat (basically, a thread).
      # A chat has_many handles which represents members of the thread
      # We load the whole list of chats/handles so we can pass along the participants 
      # of a message to the Transformer
      def load_chats
        sql = "SELECT * from chat_handle_join as ch
          INNER JOIN handle as h ON ch.handle_id = h.ROWID
          INNER JOIN chat as c ON ch.chat_id = c.ROWID"
        results = @db.execute(sql)

        # collate in contact name if available
        results = match_contacts(results) if @contacts

        # group handles by id so we can pick right one easily
        chats = results.group_by{|x| x['chat_id']}
      end

      def load_attachments(message_ids)
        sql = <<-SQL
        SELECT
          *
        FROM
          message_attachment_join
          LEFT JOIN attachment ON attachment_id = attachment.rowid
        WHERE
          message_id IN(#{message_ids.join(",")})
        SQL

        results = @db.execute(sql)
        results.group_by { |r| r['message_id'] }
      end

      def match_contacts results
        results.map do |chat|
          contact = @contacts[chat['id']]
          if contact
            full_name = "#{contact['first_name']} #{contact['last_name']}".strip
            chat['full_name'] = full_name if full_name
          end
          chat
        end
      end

      def ios_timestamp_to_unix ts
        ts + 978307200
      end

      def unix_to_ios_timestamp ts
        ts - 978307200
      end
    end
  end
end
