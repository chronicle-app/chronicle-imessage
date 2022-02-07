# Chronicle::Imessage

IMessage importer for [chronicle-etl](https://github.com/chronicle-app/chronicle-etl)

## Available Connectors
### Extractors
- `imessage` - Extractor for importing messages and attachments from local macOS iMessage install (`~/Library/Messages/chat.db`)

### Transformers
- `imessage` - Transformer for processing messages into Chronicle Schema

## Usage

```bash
gem install chronicle-etl
chronicle-etl connectors:install imessage

chronicle-etl --extractor imessage --extractor-opts load_since:"2022-02-07" --transformer imessage --loader table
```
