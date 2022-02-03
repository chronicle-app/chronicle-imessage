require 'chronicle/etl'
require 'sqlite3'

module Chronicle
  module Imessage 
    class ImessageExtractor < Chronicle::ETL::Extractor
      register_connector do |r|
        r.provider = 'imessage'
        r.description = 'a local imessage database'
      end

      DEFAULT_OPTIONS = {
        db: File.join(Dir.home, 'Library', 'Messages', 'chat.db'),
        load_since: Time.now - 5000000
      }.freeze

      def initialize(options = {})
        super(DEFAULT_OPTIONS.merge(options))
        prepare_data
      end

      def extract
        @messages.each do |message|
          meta = {
            participants: @chats[message['chat_id']]
          }
          yield Chronicle::ETL::Extraction.new(data: message, meta: meta)
        end
      end

      def results_count
        @messages.count
      end

      private

      def prepare_data
        @db = SQLite3::Database.new(@options[:db], results_as_hash: true)
        @messages = load_messages(
          load_since: @options[:load_since], 
          load_until: @options[:load_until],
          limit: @options[:limit]
        )
        @chats = load_chats
      end

      def load_messages(load_since: nil, load_until: nil, limit: nil)
        load_since_ios = unix_to_ios_timestamp(load_since.to_i) * 1000000000 if load_since
        load_until_ios = unix_to_ios_timestamp(load_until.to_i) * 1000000000 if load_until

        sql = "SELECT * from message as m
          LEFT OUTER JOIN handle as h ON m.handle_id=h.ROWID
          INNER JOIN chat_message_join as cm ON m.ROWID = cm.message_id"

        conditions = []
        conditions << "date < #{load_until_ios}" if load_until
        conditions << "date > #{load_since_ios}" if load_since
        sql += " WHERE #{conditions.join(" AND ")}" if conditions.any?
        sql += " LIMIT #{limit}" if limit
        sql += " ORDER BY date DESC"

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

      def match_contacts results
        results.map do |chat|
          contact = @contacts.select{|contact| contact['number'] == chat['id']}.first
          if contact
            chat['full_name'] = "#{contact['first_name']} #{contact['last_name']}".strip.presence
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
