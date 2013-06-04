# Launch Cassandra, Hadoop & Flask #
# ------------- LCHF ------------- #

=begin
  * Name: LCHF
  * Description: Launch Cassandra, Hadoop & Flask
  * Author: Jimmy Zöger
  * Date: 2013-05-03
  * License: LGPL

  Preparations: 

    * Set your AWS credentials as environment variables.
        export AWS_ACCESS_KEY_ID=
        export AWS_SECRET_ACCESS_KEY=

    * Upload public key though the AWS console.
      The key must be uploaded to all regions where you which to deploy.

    * Specify you configuration in lchf-conf.yaml.
      Other filenames can be used like this:
        LCHF.deploy :configuration_filename => my-conf.yaml

    * Modify cassandra.yaml as you'd like.

    * Before the first time, securtity groups have to be created.
        LCHF.create_security_group_in_each_region

  Usage:

    * Creates instances on AWS
        LCHF.deploy
        LCHF.deploy :configuration_filename => my-conf.yaml
        LCHF.deploy :instances_filename => my-instances.yaml

    * Add instance to cluster
        LCHF.extend_cluster
        LCHF.extend_cluster(
          :configuration_filename => my-conf.yaml,
          :instances_filename => my-instances.yaml
        )
    
    * Destroy the previuosly created cluster
        LCHF.destroy
        LCHF.destroy :instances_filename => my-instances.yaml

    * Shrink cluster
      This method will take instances from the bottom of the list.
        LCHF.shrink_cluster :count => 1
        LCHF.shrink_cluster :count => 2, :instances_filename => my-instances.yaml

    * Generate tweets and following relationships.
        LCHF.generate
        LCHF.generate :follwing => false
        LCHF.generate :tweets => false
=end

require 'aws-sdk'
require 'net/ssh'
require 'net/scp'
require 'net/ssh/multi'
require 'yaml'
require 'fileutils'

class LCHF

### Instance methods ###

  def initialize opts={}
    options = {
      :configuration_filename => 'lchf-conf.yaml',
      :instances_filename => 'lchf-instances.yaml'
    }.merge(opts)

    @instances = []
    @ec2s = {}
    @configuration_filename = options[:configuration_filename]
    @instances_filename = options[:instances_filename]
    if File.exists? @instances_filename
      load_instances
    end
  end

  def load_instances
    YAML.load(File.open(@instances_filename)).each do |instance_info|
      region = instance_info['region']
      ec2 = @ec2s[region] ? @ec2s[region] : @ec2s[region] = AWS::EC2.new(:region => region)
      @instances.push ec2.instances[instance_info['id']]
    end
  end

  def load_configuration
    @configuration = YAML.load File.open @configuration_filename
  end

  def create_instances
    load_configuration  
    instances = (@extension ? @extension_instances = [] : @instances = [])
    puts "Creating instances..."
    @configuration['instances'].each do |instances_configuration| 
      # Load configuration data
      region = instances_configuration['region']
      ami = @configuration['AMIs'][region]
      instance_type = instances_configuration['instance_type'] ? instances_configuration['instance_type'] : 'm1.small'
      count = instances_configuration['count'] ? instances_configuration['count'] : 1
      key_pair_name = @configuration['key_pair_name']
      
      # Connect to EC2 region
      ec2 = @ec2s[region] ? @ec2s[region] : @ec2s[region] = AWS::EC2.new(:region => region)
      sg = ec2.security_groups.detect { |sg| sg.name == @configuration['security_group'] }

      created_instances = ec2.instances.create(
        :image_id => ami,
        :instance_type => instance_type,
        :count => count,
        :security_groups => sg,
        :key_pair => ec2.key_pairs[key_pair_name]
      )
      
      instances.push created_instances
      # instances is Enumerable if several instances were created
      instances.flatten!

    end
    puts "Instances created"
    puts "Waiting for instances to finish start up phase..."
    sleep 10 while instances.any? { |instance| instance.status == :pending }
    puts "Instances are running"
    if @extension
      @instances.push instances
      @instances.flatten!
    end
  end

  # Save info about instances to disk
  def save_instance_info_to_disk opts={}
    options = {
      :yaml_file => true,
      :hosts_file => true
    }.merge(opts)

    instances = (@extension ? @extension_instances : @instances)

    if options[:yaml_file]
      instances_file = File.open(@instances_filename, (@extension ? "a" : "w"))
      instance_info = instances.map do |instance|
        { 
          'id'                 => instance.id,
          'private_ip_address' => instance.private_ip_address,
          'public_ip_address'  => instance.ip_address,
          'dns_name'           => instance.dns_name,
          'image_id'           => instance.image_id,
          'instance_type'      => instance.instance_type,
          'region'             => instance.availability_zone[0..-2]
        }
      end
      instances_file << instance_info.to_yaml[4..-1] # Remove the separator '---\n'
      instances_file.close
      puts "#{@instances_filename} " + (@extension ? "updated" : "created")
    end

    if options[:hosts_file]
      hosts_file = File.open("lchf-hosts", "w")
      @instances.map do |instance|
        hosts_file << instance.ip_address + " ec2-" + instance.availability_zone[0..-2] + "\n"
      end
      hosts_file.close
      puts "lchf-hosts " + (@extension ? "updated" : "created")
    end
  end

  # Configure cassandra.yaml with all the IP addresses
  def create_cassandra_yaml
    conf = YAML.load(File.open("cassandra.yaml"))
    ip_addresses = @instances.map { |instance| instance.public_ip_address }
    conf['seed_provider'][0]['parameters'][0]['seeds'] = ip_addresses.join(",")
    file = File.open("lchf-cassandra.yaml", "w")
    file << conf.to_yaml[4..-1]
    file.close
    puts "lchf-cassandra.yaml " + (@extension ? "updated" : "created")
  end

  def copy_files_to_servers
    puts 'Copying files to all servers...'
    instances = ((@extension ? @extension_instances : @instances))
    instances.each do |instance|
      # Create "personalized" configuration file
      conf = YAML.load(File.open("lchf-cassandra.yaml"))
      conf['listen_address'] = instance.private_ip_address
      conf['broadcast_address'] = instance.public_ip_address
      file = File.open("lchf-cassandra-single.yaml", "w")
      file << conf.to_yaml
      file.close
      
      begin
        Net::SSH.start(instance.ip_address, "ec2-user") do |ssh|
          puts "Uploading lchf-cassandra.yaml, lchf-install.sh and zocial.py to " + instance.dns_name
          ssh.scp.upload! "lchf-cassandra-single.yaml", "lchf-cassandra.yaml"
          ssh.scp.upload! "lchf-install.sh", "lchf-install.sh"
          ssh.scp.upload! "../api/zocial.py", "zocial.py"
        end
      rescue SystemCallError, Timeout::Error, Net::SSH::HostKeyMismatch
        # port 22 might not be available immediately after the instance finishes launching
        puts instance.dns_name + " is not yet available via SSH"
        sleep 10
        retry
      end
      FileUtils.rm_f "lchf-cassandra-single.yaml"
    end
    puts "Files are copied"
  end

  def execute_install_script
    puts "Executing lchf-install.sh on all servers..."
    instances = (@extension ? @extension_instances : @instances)
    Net::SSH::Multi.start do |session|
      instances.each { |instance| session.use 'ec2-user@' + instance.dns_name }
      channel = session.open_channel do |channel|
        channel.request_pty do |ch, success|
          raise "Could not request pty for " + instance.id  unless success
          ch.exec "sh lchf-install.sh" do |c, success|
            raise "Could not execute install script for " + instance.id unless success
          end
        end
      end
      session.loop
    end
    puts "All servers have been installed with Cassandra and Flask"
  end

  def start_cassandra_and_flask
    puts "Starting Cassandra and Flask..."
    instances = ((@extension ? @extension_instances : @instances))
    Net::SSH::Multi.start do |session|
      instances.each { |instance| session.use 'ec2-user@' + instance.dns_name }
      session.exec "~/apache-cassandra-1.2.5/bin/cassandra > cassandra.log"
      session.exec "nohup python ~/api/zocial.py > flask.log 2>&1 &"
      session.loop
    end
    puts "Cassandra and Flask are running"
  end

  def kill_cassandra_and_flask
    puts "Killing Cassandra and Flask..."
    Net::SSH::Multi.start do |session|
      @instances.each { |instance| session.use 'ec2-user@' + instance.dns_name }
      session.exec "killall -r python"
      session.exec "for KILLPID in `ps ax | grep cassandra | awk ' { print $1;}'`; do kill -9 $KILLPID; done"
      session.loop
    end
    puts "Cassandra and Flask have been killed"
  end

  def create_keyspace_and_tables
    Net::SSH.start(@instances.first.ip_address, "ec2-user") do |ssh|
      puts "Uploading cassandra-setup.cql to " + @instances.first.dns_name + " and setting up the keyspace with tables"
      ssh.scp.upload! "../api/cassandra-setup.cql", "cassandra-setup.cql"
      ssh.exec! "cat cassandra-setup.cql | ~/apache-cassandra-1.2.5/bin/cqlsh"
    end
  end

  def get_instances
    @instances
  end

  def terminate_instances opts={}
    options = {
      :count => 0 # means all nodes are termiated
    }.merge(opts)
    count = options[:count]

    instances_to_terminate = @instances[-count..-1]
    if count != 0 # Decommision nodes 
      puts "Nodes are decommisioned, this may take some time..."
      Net::SSH::Multi.start do |session|
        instances_to_terminate.each { |instance| session.use 'ec2-user@' + instance.dns_name }
        session.exec "~/apache-cassandra-1.2.5/bin/nodetool decommision"
        session.loop
      end
      puts "Nodes were successfully decommisioned"
    end
    instances_to_terminate.each do |instance|
      instance.terminate
      @instances.delete instance
    end
    puts 'Instances are terminated'
  end

  def generate_tweets
    puts "Starting tweet generation on all servers..."
    puts "Uploading generation script to all servers..."
    @instances.each do |instance|
      Net::SSH.start(instance.dns_name, "ec2-user") do |ssh|
        ssh.scp.upload! "../api/generate_tweets.py", "api/generate_tweets.py"
      end
    end
    puts "Starting generation scripts..."
    Net::SSH::Multi.start do |session|
      @instances.each { |instance| session.use 'ec2-user@' + instance.dns_name }
      session.exec "nohup python api/generate_tweets.py > tweets_generation.log 2>&1 &"
      session.loop
    end
    puts "Tweet generation started"
  end

  def generate_following
    puts "Starting following generation on all servers..."
    puts "Uploading generation script to all servers..."
    @instances.each do |instance|
      Net::SSH.start(instance.dns_name, "ec2-user") do |ssh|
        ssh.scp.upload! "../api/generate_following.py", "api/generate_following.py"
      end
    end
    puts "Starting generation scripts..."
    Net::SSH::Multi.start do |session|
      @instances.each { |instance| session.use 'ec2-user@' + instance.dns_name }
      session.exec "nohup python api/generate_following.py > following_generation.log 2>&1 &"
      session.loop
    end
    puts "Following generation started"
  end

  def repair_ring
    puts "Starting repair process of ring..."
    instances = (@extension ? @extension_instances : @instances)
    Net::SSH::Multi.start do |session|
      instances.each { |instance| session.use 'ec2-user@' + instance.dns_name }
      session.exec "nohup ~/apache-cassandra-1.2.5/bin/nodetool repair > repair.log 2>&1 &"
      session.loop
    end
    puts "The ring will now be repaired"
  end

  def create_install_run opts={}
    options = {
      :extension => false
    }.merge(opts)

    @extension = options[:extension]
    
    create_instances
    save_instance_info_to_disk
    create_cassandra_yaml
    copy_files_to_servers
    execute_install_script
    start_cassandra_and_flask
    sleep 30 unless @extension # Wait for Cassandra to start
    create_keyspace_and_tables unless @extension
    repair_ring if @extension
    # Clean up
    @extension = false
    @extension_instances = []
  end

### Class methods ###

  def self.deploy options={}
    lchf = self.new options
    lchf.create_install_run
  end

  def self.extend_cluster options={}
    lchf = self.new options
    lchf.create_install_run :extension => true
  end

  def self.destroy options={}
    lchf = self.new options
    lchf.terminate_instances
    FileUtils.rm_f "lchf-instances.yaml"
    FileUtils.rm_f "lchf-cassandra.yaml"
    :ok
  end

  def self.shrink_cluster opts={}
    options = {
      :count => 1
    }.merge(opts)

    lchf = self.new options
    lchf.terminate_instances options
    lchf.save_instance_info_to_disk
  end

  def self.generate opts={}
    options = {
      :tweets => true,
      :following => true,
    }.merge(opts)
    lchf = self.new opts
    if options[:tweets]
      lchf.generate_tweets
    end
    if options[:following]
      lchf.generate_following
    end
  end

# Run this function the first time you are deploying a cluster
  def self.create_security_group_in_each_region
    ec2s = AWS.ec2.regions.map(&:name).map { |region_name| AWS::EC2.new(:region => region_name) }
    ec2s.each do |ec2|
      sg = ec2.security_groups.create('Cassandra-Public')
      sg.authorize_ingress(:tcp, 22) # SSH
      sg.authorize_ingress(:tcp, 1024..65535) # JMX and other Cassandra stuff
      sg.authorize_ingress(:tcp, 8080) # API interface, actually unnecessary
    end
  end
end