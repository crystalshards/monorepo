require "lucky"
require "avram/lucky"

# This tells Lucky how to start the Avram database
Avram.configure do |settings|
  settings.database_to_migrate = AppDatabase
end

# Configure Lucky
Lucky.configure do |settings|
  # Set the host and port to bind to
  settings.secret_key_base = Lucky::Server.temp_config.secret_key_base
  settings.host = "0.0.0.0"
  settings.port = (ENV["PORT"]? || "3000").to_i
end

# Database configuration
class AppDatabase < Avram::Database
  settings.url = ENV["DATABASE_URL"]? || "postgres://localhost/crystalshards_development"
end

# Simple home page action
class Home::IndexPage < MainLayout
  def content
    div class: "container mx-auto px-4 py-8" do
      h1 "Crystal Shards Registry", class: "text-4xl font-bold mb-8"
      
      div class: "bg-blue-50 border border-blue-200 rounded-lg p-6 mb-8" do
        h2 "Welcome to CrystalShards.org", class: "text-2xl font-semibold mb-4"
        p "A modern package registry for Crystal language shards.", class: "text-gray-700"
      end

      div class: "grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6" do
        feature_card(
          title: "Browse Shards",
          description: "Discover popular Crystal packages",
          icon: "📦"
        )
        feature_card(
          title: "Submit Shards",
          description: "Share your Crystal packages",
          icon: "🚀"  
        )
        feature_card(
          title: "API Access", 
          description: "Programmatic access to registry",
          icon: "🔗"
        )
      end
    end
  end

  private def feature_card(title : String, description : String, icon : String)
    div class: "bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow" do
      div class: "text-4xl mb-4" do
        text icon
      end
      h3 title, class: "text-xl font-semibold mb-2"
      p description, class: "text-gray-600"
    end
  end
end

# Home controller
class Home::Index < BrowserAction
  get "/" do
    html Home::IndexPage
  end
end

# Health check endpoint
class Api::Health < ApiAction
  get "/health" do
    json({status: "ok", service: "crystal-shards-registry"})
  end
end

# Main layout
abstract class MainLayout
  include Lucky::HTMLPage

  def render
    html_doctype
    html lang: "en" do
      head do
        utf8_charset
        title "Crystal Shards Registry"
        meta name: "viewport", content: "width=device-width,initial-scale=1"
        # Include Tailwind CSS from CDN for now
        link href: "https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css", rel: "stylesheet"
      end

      body do
        content
      end
    end
  end

  abstract def content
end

# Base action classes
abstract class BrowserAction < Lucky::Action
  include Lucky::ProtectFromForgery
  accepted_formats [:html], default: :html
end

abstract class ApiAction < Lucky::Action
  accepted_formats [:json], default: :json
end

# Start the Lucky server
Lucky::Server.new.listen