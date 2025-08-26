require "email"
require "http/client"
require "json"
require "./email_preferences"

# Email service abstraction for CrystalShards platform
# Supports multiple providers: SMTP, SendGrid, Postmark, etc.
abstract class EmailProvider
  abstract def send_email(email : EmailMessage) : Bool
  abstract def healthy? : Bool
end

# Email message structure
struct EmailMessage
  property to : String
  property to_name : String?
  property from : String
  property from_name : String?
  property subject : String
  property html_body : String?
  property text_body : String?
  property reply_to : String?
  property tags : Array(String)
  property attachments : Array(EmailAttachment)

  def initialize(@to : String, @from : String, @subject : String, 
                 @html_body : String? = nil, @text_body : String? = nil,
                 @to_name : String? = nil, @from_name : String? = nil,
                 @reply_to : String? = nil,
                 @tags : Array(String) = [] of String,
                 @attachments : Array(EmailAttachment) = [] of EmailAttachment)
  end
end

struct EmailAttachment
  property filename : String
  property content : String
  property content_type : String

  def initialize(@filename : String, @content : String, @content_type : String)
  end
end

# SMTP Provider (for cost-effective sending)
class SMTPProvider < EmailProvider
  def initialize(@host : String, @port : Int32, @username : String, @password : String, @use_tls : Bool = true)
  end

  def send_email(email : EmailMessage) : Bool
    begin
      # Create email using Crystal's email library
      mail = Email.new
      mail.to = email.to
      mail.from = email.from
      mail.subject = email.subject

      if email.html_body && email.text_body
        mail.message = Email::Message.new(email.html_body, email.text_body)
      elsif email.html_body
        mail.html_body = email.html_body
      else
        mail.body = email.text_body || ""
      end

      # Add optional headers
      mail.reply_to = email.reply_to if email.reply_to
      
      # Send via SMTP
      mail.deliver(@host, @port, @username, @password, @use_tls)
      true
    rescue ex
      puts "SMTP send failed: #{ex.message}"
      false
    end
  end

  def healthy? : Bool
    # Simple connectivity test
    begin
      socket = TCPSocket.new(@host, @port)
      socket.close
      true
    rescue
      false
    end
  end
end

# SendGrid Provider (cloud-based with good deliverability)
class SendGridProvider < EmailProvider
  API_BASE = "https://api.sendgrid.com/v3/mail/send"

  def initialize(@api_key : String)
    @client = HTTP::Client.new(URI.parse(API_BASE))
    @client.before_request do |request|
      request.headers["Authorization"] = "Bearer #{@api_key}"
      request.headers["Content-Type"] = "application/json"
    end
  end

  def send_email(email : EmailMessage) : Bool
    begin
      payload = build_sendgrid_payload(email)
      response = @client.post("/", body: payload.to_json)
      
      success = response.status.success?
      unless success
        puts "SendGrid API error: #{response.status} - #{response.body}"
      end
      
      success
    rescue ex
      puts "SendGrid send failed: #{ex.message}"
      false
    end
  end

  def healthy? : Bool
    begin
      # Test with SendGrid API health endpoint
      response = @client.get("/")
      response.status.success?
    rescue
      false
    end
  end

  private def build_sendgrid_payload(email : EmailMessage)
    personalizations = [{
      "to" => [{"email" => email.to, "name" => email.to_name}],
      "subject" => email.subject
    }]

    content = [] of Hash(String, String)
    if email.text_body
      content << {"type" => "text/plain", "value" => email.text_body}
    end
    if email.html_body
      content << {"type" => "text/html", "value" => email.html_body}
    end

    payload = {
      "personalizations" => personalizations,
      "from" => {"email" => email.from, "name" => email.from_name},
      "content" => content
    }

    if email.reply_to
      payload["reply_to"] = {"email" => email.reply_to}
    end

    if !email.tags.empty?
      payload["categories"] = email.tags
    end

    payload
  end
end

# Main Email Service with failover support
class EmailService
  RATE_LIMIT = 100 # emails per minute

  def initialize
    @providers = [] of EmailProvider
    @current_provider = 0
    @sent_count = 0_i64
    @failed_count = 0_i64
    @rate_limit_window = Time.utc
    @rate_limit_count = 0

    setup_providers
  end

  # Send an email with automatic provider failover and preference checking
  def send_email(email : EmailMessage, preference_type : EmailPreferences::PreferenceType? = nil) : Bool
    return false if rate_limited?

    # Check email preferences if type specified
    if preference_type && EMAIL_PREFERENCES
      if EMAIL_PREFERENCES.unsubscribed?(email.to, preference_type)
        puts "Email not sent - user unsubscribed from #{preference_type}"
        return false
      end
      
      if EMAIL_PREFERENCES.globally_suppressed?(email.to)
        puts "Email not sent - address globally suppressed: #{email.to}"
        return false
      end
    end

    @providers.each_with_index do |provider, index|
      @current_provider = index
      
      if provider.send_email(email)
        @sent_count += 1
        increment_rate_limit
        puts "Email sent successfully via #{provider.class}"
        return true
      else
        puts "Email failed via #{provider.class}, trying next provider..."
      end
    end

    @failed_count += 1
    puts "All email providers failed for: #{email.to}"
    false
  end

  # Send job posting confirmation email
  def send_job_confirmation(job_data : Hash(String, String), payment_id : String? = nil) : Bool
    unsubscribe_link = EMAIL_PREFERENCES.try(&.generate_unsubscribe_link(job_data["email"], EmailPreferences::PreferenceType::JobConfirmations)) || ""
    
    email = EmailMessage.new(
      to: job_data["email"],
      to_name: job_data["company"],
      from: "noreply@crystalgigs.com",
      from_name: "CrystalGigs",
      subject: "Job Posting Confirmation - #{job_data["title"]}",
      html_body: build_job_confirmation_html(job_data, payment_id, unsubscribe_link),
      text_body: build_job_confirmation_text(job_data, payment_id, unsubscribe_link),
      reply_to: "support@crystalgigs.com",
      tags: ["job-confirmation", payment_id ? "paid" : "free"]
    )

    send_email(email, EmailPreferences::PreferenceType::JobConfirmations)
  end

  # Send shard submission notification  
  def send_shard_notification(shard_name : String, author_email : String, github_url : String) : Bool
    email = EmailMessage.new(
      to: author_email,
      from: "noreply@crystalshards.org",
      from_name: "CrystalShards",
      subject: "Shard Submission Received - #{shard_name}",
      html_body: build_shard_notification_html(shard_name, github_url),
      text_body: build_shard_notification_text(shard_name, github_url),
      reply_to: "support@crystalshards.org", 
      tags: ["shard-notification", "submission"]
    )

    send_email(email)
  end

  # Send documentation build notification
  def send_docs_notification(shard_name : String, version : String, status : String, recipient : String) : Bool
    subject = if status == "completed"
                "Documentation Build Complete - #{shard_name} v#{version}"
              else
                "Documentation Build Failed - #{shard_name} v#{version}"
              end

    email = EmailMessage.new(
      to: recipient,
      from: "noreply@crystaldocs.org",
      from_name: "CrystalDocs",
      subject: subject,
      html_body: build_docs_notification_html(shard_name, version, status),
      text_body: build_docs_notification_text(shard_name, version, status),
      reply_to: "support@crystaldocs.org",
      tags: ["docs-notification", status]
    )

    send_email(email)
  end

  # Get service statistics
  def stats : Hash(String, Int64 | Float64 | String)
    success_rate = if (@sent_count + @failed_count) > 0
                     (@sent_count * 100.0 / (@sent_count + @failed_count))
                   else
                     100.0
                   end

    {
      "total_sent" => @sent_count,
      "total_failed" => @failed_count,
      "success_rate_percent" => success_rate,
      "current_provider" => @current_provider.to_i64,
      "providers_available" => @providers.size.to_i64,
      "rate_limit_remaining" => (RATE_LIMIT - @rate_limit_count).to_i64
    }
  end

  # Health check for all providers
  def healthy? : Bool
    @providers.any?(&.healthy?)
  end

  # Test email functionality
  def send_test_email(recipient : String) : Bool
    test_email = EmailMessage.new(
      to: recipient,
      from: "test@crystalshards.org",
      from_name: "CrystalShards Test",
      subject: "Email Service Test - #{Time.utc}",
      html_body: "<h1>Test Email</h1><p>This is a test email from CrystalShards platform.</p>",
      text_body: "Test Email\n\nThis is a test email from CrystalShards platform.",
      tags: ["test"]
    )

    send_email(test_email)
  end

  private def setup_providers
    # Setup SMTP provider if credentials available
    if smtp_host = ENV["SMTP_HOST"]?
      smtp_port = ENV.fetch("SMTP_PORT", "587").to_i
      smtp_user = ENV.fetch("SMTP_USERNAME", "")
      smtp_pass = ENV.fetch("SMTP_PASSWORD", "")
      
      if !smtp_user.empty? && !smtp_pass.empty?
        @providers << SMTPProvider.new(smtp_host, smtp_port, smtp_user, smtp_pass)
        puts "SMTP provider configured: #{smtp_host}:#{smtp_port}"
      end
    end

    # Setup SendGrid if API key available  
    if sendgrid_key = ENV["SENDGRID_API_KEY"]?
      @providers << SendGridProvider.new(sendgrid_key)
      puts "SendGrid provider configured"
    end

    if @providers.empty?
      puts "Warning: No email providers configured"
    else
      puts "Email service initialized with #{@providers.size} provider(s)"
    end
  end

  private def rate_limited? : Bool
    # Reset window every minute
    now = Time.utc
    if now - @rate_limit_window > 1.minute
      @rate_limit_window = now
      @rate_limit_count = 0
    end

    @rate_limit_count >= RATE_LIMIT
  end

  private def increment_rate_limit
    @rate_limit_count += 1
  end

  # Email template builders
  private def build_job_confirmation_html(job_data : Hash(String, String), payment_id : String?, unsubscribe_link : String) : String
    paid_status = payment_id ? "✅ Paid" : "📝 Pending Payment"
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>Job Posting Confirmation</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #667eea; color: white; padding: 20px; text-align: center; border-radius: 8px; }
            .content { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; }
            .job-details { background: white; padding: 15px; border-radius: 6px; margin: 15px 0; }
            .status { font-weight: bold; font-size: 18px; margin: 10px 0; }
            .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
            a { color: #667eea; text-decoration: none; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Job Posting Confirmation</h1>
            <p>Your job posting has been received!</p>
        </div>
        
        <div class="content">
            <div class="status">Status: #{paid_status}</div>
            
            <div class="job-details">
                <h3>#{job_data["title"]}</h3>
                <p><strong>Company:</strong> #{job_data["company"]}</p>
                <p><strong>Location:</strong> #{job_data["location"]}</p>
                <p><strong>Type:</strong> #{job_data["job_type"]}</p>
                <p><strong>Salary:</strong> #{job_data["salary"]}</p>
            </div>
            
            #{if payment_id
                "<p>✅ Payment confirmed! Your job posting will go live within 24 hours.</p>"
              else
                "<p>📋 Please complete payment to activate your job posting.</p>"
              end}
            
            <p>You can view and manage your posting at: <a href="https://crystalgigs.com/jobs">CrystalGigs.com</a></p>
        </div>
        
        <div class="footer">
            <p>Thank you for using CrystalGigs!</p>
            <p>Questions? Reply to this email or contact <a href="mailto:support@crystalgigs.com">support@crystalgigs.com</a></p>
            #{unless unsubscribe_link.empty?
                "<p><a href=\"#{unsubscribe_link}\" style=\"color: #999; font-size: 11px;\">Unsubscribe from job confirmations</a></p>"
              end}
        </div>
    </body>
    </html>
    HTML
  end

  private def build_job_confirmation_text(job_data : Hash(String, String), payment_id : String?, unsubscribe_link : String) : String
    paid_status = payment_id ? "✅ Paid" : "📝 Pending Payment"
    
    <<-TEXT
    Job Posting Confirmation
    
    Your job posting has been received!
    
    Status: #{paid_status}
    
    Job Details:
    - Title: #{job_data["title"]}
    - Company: #{job_data["company"]}  
    - Location: #{job_data["location"]}
    - Type: #{job_data["job_type"]}
    - Salary: #{job_data["salary"]}
    
    #{if payment_id
        "✅ Payment confirmed! Your job posting will go live within 24 hours."
      else
        "📋 Please complete payment to activate your job posting."
      end}
    
    View your posting at: https://crystalgigs.com/jobs
    
    Thank you for using CrystalGigs!
    Questions? Contact support@crystalgigs.com
    
    #{unless unsubscribe_link.empty?
        "To unsubscribe from job confirmations: #{unsubscribe_link}"
      end}
    TEXT
  end

  private def build_shard_notification_html(shard_name : String, github_url : String) : String
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>Shard Submission Received</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: #764abc; color: white; padding: 20px; text-align: center; border-radius: 8px; }
            .content { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Shard Submission Received</h1>
        </div>
        
        <div class="content">
            <p>Thank you for submitting <strong>#{shard_name}</strong> to CrystalShards!</p>
            <p>Your shard is now in our review queue and will be published once approved.</p>
            <p>Repository: <a href="#{github_url}">#{github_url}</a></p>
            <p>You can track the status at: <a href="https://crystalshards.org">CrystalShards.org</a></p>
        </div>
    </body>
    </html>
    HTML
  end

  private def build_shard_notification_text(shard_name : String, github_url : String) : String
    <<-TEXT
    Shard Submission Received
    
    Thank you for submitting #{shard_name} to CrystalShards!
    
    Your shard is now in our review queue and will be published once approved.
    Repository: #{github_url}
    
    Track status at: https://crystalshards.org
    TEXT
  end

  private def build_docs_notification_html(shard_name : String, version : String, status : String) : String
    icon = status == "completed" ? "✅" : "❌"
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>Documentation Build #{status.capitalize}</title>
    </head>
    <body>
        <h1>#{icon} Documentation Build #{status.capitalize}</h1>
        <p>Shard: <strong>#{shard_name}</strong> v#{version}</p>
        <p>Status: #{status.capitalize}</p>
        #{if status == "completed"
            "<p>View documentation at: <a href=\"https://crystaldocs.org/#{shard_name}/#{version}\">CrystalDocs.org</a></p>"
          else
            "<p>Please check your shard.yml and documentation format.</p>"
          end}
    </body>
    </html>
    HTML
  end

  private def build_docs_notification_text(shard_name : String, version : String, status : String) : String
    icon = status == "completed" ? "✅" : "❌"
    
    <<-TEXT
    #{icon} Documentation Build #{status.capitalize}
    
    Shard: #{shard_name} v#{version}
    Status: #{status.capitalize}
    
    #{if status == "completed"
        "View documentation at: https://crystaldocs.org/#{shard_name}/#{version}"
      else
        "Please check your shard.yml and documentation format."
      end}
    TEXT
  end
end

# Global email service instance
EMAIL_SERVICE = EmailService.new