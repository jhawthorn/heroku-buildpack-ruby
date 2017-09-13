require "language_pack"
require "language_pack/rails42"

class LanguagePack::Solidus < LanguagePack::Rails5
  # detects if this is a Rails 5 app
  # @return [Boolean] true if it's a Rails 5 app
  def self.use?
    File.exists?("solidus.gemspec")
  end

  def compile
    puts "Compiling solidus"

    # We make an empty git directory to trick bundler into not looking for one
    # higher up and generate warnings.
    # I don't like bundler.
    sh "git init -q"

    # Ooookay....
    # What we're going to do is install railties, and then use that to generate
    # a new rails app in the current directory

    # We try to save a second by using the system libxml
    sh "NOKOGIRI_USE_SYSTEM_LIBRARIES=1 gem install --user-install --no-ri --no-rdoc railties:'~>5.1.0'"

    # We need an absolute path since the gem bin dir isn't in our path
    rails_path = `ruby -e "gem 'railties'; puts Gem.bin_path('railties', 'rails')"`.strip
    sh "#{rails_path} new sandbox --skip-bundle --database=postgresql"

    sh "cp -r sandbox/* ."
    sh "rm -rf sandbox"

    # Great..... Well maybe not great.
    # Anyways, now we want to configure some files we'll need

    # We add solidus to the Gemfile, and some other heroku niceties
    File.open("Gemfile", 'a') do |f|
      f.puts <<-GEMFILE
gem 'solidus'
gem 'solidus_auth_devise'

gem 'rails_12factor'
GEMFILE
    end

    File.write("config/initializers/devise.rb", <<RUBY)
Devise.secret_key = #{SecureRandom.hex(50).inspect }
RUBY

    File.write("Procfile", <<PROCFILE)
web: bundle exec puma -t 5:5 -p ${PORT:-3000} -e production
PROCFILE

    File.write("config/initializers/00_sandbox.rb", <<RUBY)
# Needed so database isn't hit on install
Spree::Auth::Config.use_static_preferences!

# Required to work around sample data sending emails
Rails.application.config.action_mailer.raise_delivery_errors = false
RUBY

    super
  end

  # We want to override this to run our spree install _right_ before we compile assets
  def run_assets_precompile_rake_task
    # We want to make sure we have all the migrations ready to run, but we
    # don't actually want to run them now because we don't have a database yet.
    sh "bundle exec rails g spree:install --auto-accept --user_class=Spree::User --enforce_available_locales=true --migrate=false --seed=false --sample=false"

    # We use this instead of solidus_auth:install because this won't run
    # migrations.
    sh "bundle exec rake railties:install:migrations"

    # Okay, now we want to run whatever heroku normally does for a rails app
    # This includes:
    #  * bundle install
    #  * install node.js
    #  * rake asset:precompile
    super
  end

  private

  def sh(cmd)
    system(cmd) || raise("#{cmd.inspect} failed")
  end

  def install_plugins
    # Need to skip this to avoid looking in the bundler cache before we have one
  end
end
