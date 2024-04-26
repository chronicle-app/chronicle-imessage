# Chronicle::Imessage
[![Gem Version](https://badge.fury.io/rb/chronicle-imessage.svg)](https://badge.fury.io/rb/chronicle-imessage)

Access your iMessage messages and attachments using the command line with this plugin for [chronicle-etl](https://github.com/chronicle-app/chronicle-etl).

## Usage

```sh
# Install chronicle-etl and this plugin
$ gem install chronicle-etl
$ chronicle-etl plugins:install imessage

# Load messages from the last week
$ chronicle-etl --extractor imessage --schema chronicle --since 1w

# Of the latest 1000 messages received, who were the top senders?
$ chronicle-etl -e imessage --schema chronicle --limit 1000 --fields agent.name | sort | uniq -c | sort -nr
```

## Available Connectors
### Extractors

#### `message`
Extractor for importing messages and attachments from local macOS iMessage install (via local cache at `~/Library/Messages/chat.db`)

##### Settings
- `input`: (default: ~/Library/Messages/chat.db) Local iMessage sqlite database
- `load_attachments`: (default: false) Whether to load message attachments
- `only_attachments`: (default: false) Whether to load only messages with attachments

We want messages to have sender/receiver information set properly so we try to infer your iCloud information and phone number automatically. If these fail, you can provide the necessary information with:
- `my_phone_number`: Your phone number (for setting messages's actor fields properly)
- `my_name`: Your name (for setting messages's actor fields properly)
- `icloud_account_id`: Specify an email address that represents your iCloud account ID
- `icloud_account_dsid`: Specify iCloud DSID
  - Can find in Keychain or by running `$ defaults read MobileMeAccounts Accounts`
