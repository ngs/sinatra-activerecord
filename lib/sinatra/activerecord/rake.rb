require 'active_record'
require 'fileutils'

namespace :db do
  task :load_config do
    ActiveRecord::Base.configurations = YAML.load(File.read("config/database.yml"))
  end

  desc 'Create the database from config/database.yml for the current RACK_ENV (use db:create:all to create all dbs in the config)'
  task :create => :load_config do
    ActiveRecord::Base.configurations.each{|env, config|
      create_database(config)
    }
  end

  def create_database(config)
    begin
      if config['adapter'] =~ /sqlite/
        if File.exist?(config['database'])
          $stderr.puts "#{config['database']} already exists"
        else
          begin
            # Create the SQLite database
            ActiveRecord::Base.establish_connection(config)
            ActiveRecord::Base.connection
          rescue Exception => e
            $stderr.puts e, *(e.backtrace)
            $stderr.puts "Couldn't create database for #{config.inspect}"
          end
        end
        return # Skip the else clause of begin/rescue
      else
        ActiveRecord::Base.establish_connection(config)
        ActiveRecord::Base.connection
      end
    rescue
      case config['adapter']
      when /mysql/
        @charset   = ENV['CHARSET']   || 'utf8'
        @collation = ENV['COLLATION'] || 'utf8_unicode_ci'
        creation_options = {:charset => (config['charset'] || @charset), :collation => (config['collation'] || @collation)}
        error_class = config['adapter'] =~ /mysql2/ ? Mysql2::Error : Mysql::Error
        access_denied_error = 1045
        begin
          ActiveRecord::Base.establish_connection(config.merge('database' => nil))
          ActiveRecord::Base.connection.create_database(config['database'], creation_options)
          ActiveRecord::Base.establish_connection(config)
        rescue error_class => sqlerr
          if sqlerr.errno == access_denied_error
            print "#{sqlerr.error}. \nPlease provide the root password for your mysql installation\n>"
            root_password = $stdin.gets.strip
            grant_statement = "GRANT ALL PRIVILEGES ON #{config['database']}.* " \
              "TO '#{config['username']}'@'localhost' " \
              "IDENTIFIED BY '#{config['password']}' WITH GRANT OPTION;"
            ActiveRecord::Base.establish_connection(config.merge(
                'database' => nil, 'username' => 'root', 'password' => root_password))
            ActiveRecord::Base.connection.create_database(config['database'], creation_options)
            ActiveRecord::Base.connection.execute grant_statement
            ActiveRecord::Base.establish_connection(config)
          else
            $stderr.puts sqlerr.error
            $stderr.puts "Couldn't create database for #{config.inspect}, charset: #{config['charset'] || @charset}, collation: #{config['collation'] || @collation}"
            $stderr.puts "(if you set the charset manually, make sure you have a matching collation)" if config['charset']
          end
        end
      when 'postgresql'
        @encoding = config['encoding'] || ENV['CHARSET'] || 'utf8'
        begin
          ActiveRecord::Base.establish_connection(config.merge('database' => 'postgres', 'schema_search_path' => 'public'))
          ActiveRecord::Base.connection.create_database(config['database'], config.merge('encoding' => @encoding))
          ActiveRecord::Base.establish_connection(config)
        rescue Exception => e
          $stderr.puts e, *(e.backtrace)
          $stderr.puts "Couldn't create database for #{config.inspect}"
        end
      end
    else
      $stderr.puts "#{config['database']} already exists"
    end
  end

  desc "migrate your database"
  task :migrate do
    ActiveRecord::Migrator.migrate(
      'db/migrate',
      ENV["VERSION"] ? ENV["VERSION"].to_i : nil
    )
  end

  desc "create an ActiveRecord migration in ./db/migrate"
  task :create_migration do
    name = ENV['NAME']
    abort("no NAME specified. use `rake db:create_migration NAME=create_users`") if !name

    migrations_dir = File.join("db", "migrate")
    version = ENV["VERSION"] || Time.now.utc.strftime("%Y%m%d%H%M%S") 
    filename = "#{version}_#{name}.rb"
    migration_name = name.gsub(/_(.)/) { $1.upcase }.gsub(/^(.)/) { $1.upcase }

    FileUtils.mkdir_p(migrations_dir)

    open(File.join(migrations_dir, filename), 'w') do |f|
      f << (<<-EOS).gsub("      ", "")
      class #{migration_name} < ActiveRecord::Migration
        def self.up
        end

        def self.down
        end
      end
      EOS
    end
  end
end
