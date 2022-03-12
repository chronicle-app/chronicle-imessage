require 'find'
require 'phonelib'

module Chronicle
  module Imessage 
    # Load contacts from local macOS address book
    class LocalContacts
      def initialize
        filename = find_local_icloud_address_book
        @db = SQLite3::Database.new(filename, results_as_hash: true)
      end

      def contact_identifier_to_details(identifier)
        contacts[identifier]
      end

      def contacts
        @contacts ||= begin
          c = {}
          c.merge!(load_phone_numbers)
          c.merge!(load_email_addresses)
          c
        end
      end

      def my_phone_contact
        @my_phone_contact ||= load_my_phone_contact
      end

      def my_icloud_account
        @my_icloud_account ||= load_my_icloud_account
      end

      # The synced address book doesn't have a stable folder location so we 
      # have to search for it
      def find_local_icloud_address_book
        pattern = File.join(Dir.home, '/Library/Application Support/AddressBook/Sources', '**/*.abcddb')
        Dir.glob(pattern).first
      end

      def load_my_icloud_account
        @my_icloud_account || begin
          output = `defaults read MobileMeAccounts Accounts | plutil -convert json -r -o - -- -`
          JSON.parse(output, symbolize_names: true).first
        end
      end

      def load_my_phone_contact
        sql = <<-SQL
          SELECT
            ZABCDPHONENUMBER.ZFULLNUMBER AS identifier,
            ZABCDRECORD.ZFIRSTNAME as first_name,
            ZABCDRECORD.ZLASTNAME as last_name
          FROM
            ZABCDRECORD,
            ZABCDPHONENUMBER 
          WHERE
            ZABCDRECORD.Z_PK = ZABCDPHONENUMBER.ZOWNER  
            AND ZABCDRECORD.zcontainerwherecontactisme IS NOT NULL 
        SQL

        results = @db.execute(sql)

        guessed_number = results.first
        return unless guessed_number

        {
          phone_number: Phonelib.parse(guessed_number['identifier'], "US").e164,
          full_name: "#{guessed_number['first_name']} #{guessed_number['last_name']}"
        }
      end

      def load_phone_numbers
        sql = <<-SQL
          SELECT
            ZABCDPHONENUMBER.ZFULLNUMBER AS identifier,
            ZABCDRECORD.ZFIRSTNAME as first_name,
            ZABCDRECORD.ZLASTNAME as last_name
          FROM
            ZABCDRECORD,
            ZABCDPHONENUMBER
          WHERE
            ZABCDRECORD.Z_PK = ZABCDPHONENUMBER.ZOWNER
        SQL

        results = @db.execute(sql)
        results.map do |r|
          # We normalize phone numbers (and assume US/Canada country code)
          # so that we can match identifiers from chat.db
          normalized = Phonelib.parse(r['identifier'], "US").e164
          [normalized, r]
        end.to_h
      end

      def load_email_addresses
        sql = <<-SQL
          SELECT
            ZABCDEMAILADDRESS.ZADDRESSNORMALIZED AS identifier,
            ZABCDRECORD.ZFIRSTNAME as first_name,
            ZABCDRECORD.ZLASTNAME as last_name
          FROM
            ZABCDRECORD,
            ZABCDEMAILADDRESS
          WHERE
            ZABCDRECORD.Z_PK = ZABCDEMAILADDRESS.ZOWNER
        SQL

        results = @db.execute(sql)
        results.map do |r|
          [r['identifier'], r]
        end.to_h
      end
    end
  end
end
