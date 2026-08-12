require "./shards"

require "../config/server"
require "./app_database"
require "./docs_database"
require "../config/**"
require "./models/base_model"
require "./models/mixins/**"
require "./models/**"
require "./queries/mixins/**"
require "./queries/**"
require "./operations/mixins/**"
require "./operations/**"

# Pages, serializers and actions all order versions, and all of them must agree
# with the latest_version the indexer stored. Required explicitly rather than
# through a services glob: the rest of services/ is the crawler and the indexer,
# which the web app deliberately does not carry.
require "./services/version_order"
require "./serializers/base_serializer"
require "./serializers/**"
require "./emails/base_email"
require "./emails/**"
# Services ahead of the pages and workers that use them. Individual services
# still require their own dependencies; this is only so that a page can name
# one without the load order depending on some worker having pulled it in
# first.
require "./services/**"
require "./pages/**"
require "./actions/mixins/**"
require "./actions/**"
require "./workers/**"
require "../db/migrations/**"
require "./app_server"
