# Launch Cassandra and Hadoop Fast #
# ------------- lchf ------------- #

# ruby lchf-deploy.rb
# Creates instances on AWS

# First, set your credentials as environment variabless
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=

# Also upload public key to all regions through the AWS console

require 'aws-sdk'
require 'net/ssh'
require 'net/scp'
require 'net/ssh/multi'
require 'yaml'
require 'fileutils'

instance_type = 'm1.small'

# Amazon Linux AMI IDs Instance Store Backed (not EBS) 64-bit
AMIs = {
  'eu-west-1'      => 'ami-d9c0d6ad',
  'sa-east-1'      => 'ami-4653895b',
  'us-east-1'      => 'ami-570f603e',
  'ap-northeast-1' => 'ami-49b23d48',
  'us-west-2'      => 'ami-5359cf63',
  'us-west-1'      => 'ami-c5fed180',
  'ap-southeast-1' => 'ami-eade91b8',
  'ap-southeast-2' => 'ami-316cfc0b',
}

# Connect to all regions
ec2s = AWS.ec2.regions.map(&:name).map { |region_name| AWS::EC2.new(:region => region_name) }

puts "Creating instances..."
instances = ec2s.map do |ec2| 
  ami = AMIs[ec2.availability_zones.first.region_name]
  sg = ec2.security_groups.detect { |sg| sg.name == 'Cassandra-Public'}
  instance = ec2.instances.create(
    :image_id => ami,
    :instance_type => instance_type,
    :count => 1,
    :security_groups => sg,
    :key_pair => ec2.key_pairs['jimmy-rsa']
  )
end
puts "Instances created"

puts "Waiting for instances to finish start up phase..."
sleep 10 while instances.any? { |instance| instance.status == :pending }
puts "Instances are running"

################################################################################

# Configure cassandra.yaml with all the IP addresses
conf = YAML.load(File.open("cassandra.yaml"))
ip_addresses = instances.map { |instance| instance.public_ip_address }
conf['seed_provider'][0]['parameters'][0]['seeds'] = ip_addresses.join(",") # + ",10.144.7.72,10.152.182.111"
file = File.open("lchf-cassandra.yaml", "w")
file << conf.to_yaml
file.close
puts "lchf-cassandra.yaml created"

################################################################################

# Save info about instances to disk
instances_file = File.open("lchf-instances.yaml", "w")
basic_instance_info = instances.map do |instance| 
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
instances_file << basic_instance_info.to_yaml
instances_file.close
puts "lchf-instances.yaml created"

hosts_file = File.open("lchf-hosts", "w")
instances.map do |instance| 
  hosts_file << instance.private_ip_address + " ec2-" + instance.availability_zone[0..-2] + "\n"
end
hosts_file.close
puts "lchf-hosts created"

################################################################################

puts 'Copying files to all servers...'
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
      puts "Uploading lchf-cassandra.yaml and lchf-install.sh to " + instance.dns_name
      ssh.scp.upload! "lchf-cassandra-single.yaml", "lchf-cassandra.yaml"
      ssh.scp.upload! "lchf-install.sh", "lchf-install.sh"
      ssh.scp.upload! "../api/zocial.py", "zocial.py"
    end
  rescue SystemCallError, Timeout::Error, Net::SSH::HostKeyMismatch
    # port 22 might not be available immediately after the instance finishes launching
    sleep 1
    retry
  end
  FileUtils.rm_f "lchf-cassandra-single.yaml"
end
puts "Files are copied"

################################################################################

puts "Executing lchf-install.sh on all servers..."
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

################################################################################

puts "Starting Cassandra and Flask..."
Net::SSH::Multi.start do |session|
  instances.each { |instance| session.use 'ec2-user@' + instance.dns_name }
  session.exec "~/apache-cassandra-1.2.4/bin/cassandra"
  session.exec "/usr/bin/python ~/api/zocial.py &"
  session.loop
end
puts "Cassandra and Flask are running"

################################################################################

def create_security_group_in_each_region
  ec2s = AWS.ec2.regions.map(&:name).map { |region_name| AWS::EC2.new(:region => region_name) }
  ec2s.each do |ec2|
    sg = ec2.security_groups.create('Cassandra-Public')
    sg.authorize_ingress(:tcp, 22) # SSH
    sg.authorize_ingress(:tcp, 1024..65535) # JMX and other Cassandra stuff
    sg.authorize_ingress(:tcp, 8080) # API interface, actually unnecessary
  end
end