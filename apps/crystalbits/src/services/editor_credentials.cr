require "base64"
require "crypto/subtle"

# Who is allowed to approve content.
#
# The moderation queue is the one place where a draft becomes public, so it is
# the one place that must not be open. Credentials come from the environment
# and have no defaults: unset means the moderation routes refuse to serve at
# all and say why. A default password here would be a published back door.
#
#   BITS_EDITOR_USER      editor username
#   BITS_EDITOR_PASSWORD  editor password
module EditorCredentials
  Habitat.create do
    setting username : String? = nil
    setting password : String? = nil
  end

  UNCONFIGURED_MESSAGE = "Moderation is unavailable: BITS_EDITOR_USER and " \
                         "BITS_EDITOR_PASSWORD are not set. Set both to enable the review queue."

  REALM = "CrystalBits editors"

  def self.configured? : Bool
    !settings.username.nil? && !settings.password.nil?
  end

  # Both comparisons always run, and both are constant time, so a wrong
  # username cannot be told from a wrong password by how long the answer takes.
  def self.verify(username : String, password : String) : Bool
    expected_user = settings.username
    expected_password = settings.password
    return false if expected_user.nil? || expected_password.nil?

    user_ok = Crypto::Subtle.constant_time_compare(username, expected_user)
    password_ok = Crypto::Subtle.constant_time_compare(password, expected_password)

    user_ok && password_ok
  end

  # Parses an HTTP Basic Authorization header into a username and password.
  def self.from_basic_auth(header : String?) : {String, String}?
    return nil unless header

    scheme, _, encoded = header.partition(' ')
    return nil unless scheme.downcase == "basic"
    return nil if encoded.empty?

    decoded = begin
      String.new(Base64.decode(encoded))
    rescue
      return nil
    end

    username, separator, password = decoded.partition(':')
    return nil if separator.empty?

    {username, password}
  end
end
