# Launch Cassandra and Hadoop Fast #
# ------------- lchf ------------- #

# ruby lchf-deploy.rb
# Creates instances on AWS

# First, set your credentials as environment variabless
# export AWS_ACCESS_KEY_ID=
# export AWS_SECRET_ACCESS_KEY=

require 'aws-sdk'
require 'net/ssh'
require 'net/scp'
require 'yaml'

# TODO: Change this and use lchf-configuration.yaml instead
region = 'us-east-1'
instance_type = 'm1.small'
number_of_instances = 2

ec2 = AWS.ec2
#ec2 = AWS::EC2.new(:ec2_endpoint => ec2.regions[region].endpoint)

# Security group: Cassandra (sg-592ed532)
# Port (Service)      Source
# 1024 - 65535        sg-592ed532 (Cassandra)
# 22 (SSH)            0.0.0.0/0
security_group = ec2.security_groups['sg-592ed532']


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

aws_key_pair = ec2.key_pairs.detect { |key| key.name == 'aws-upc' }

puts "Creating instances"
instances = ec2.instances.create(
  :image_id => AMIs[region],
  :instance_type => instance_type,
  :count => number_of_instances,
  :security_groups => security_group,
  :key_pair => aws_key_pair)

puts "Waiting for instances to finish start up phase"
sleep 10 while instances.any? { |instance| instance.status == :pending }
puts "Instances are running"

# Configure cassandra.yaml with the IP addresses
conf = YAML.load(File.open("cassandra.yaml"))
ip_addresses = instances.map { |instance| instance.private_ip_address }
conf['seed_provider'][0]['parameters'][0]['seeds'] = ip_addresses.join(",") # + ",10.144.7.72,10.152.182.111"
file = File.open("lchf-cassandra.yaml", "w")
file << conf.to_yaml
file.close
puts "lchf-cassandra.yaml created"

# Save info about instances to disk
instances_file = File.open("lchf-instances.yaml", "w")
basic_instance_info = instances.map do |instance| 
  { 
    'id'                 => instance.id,
    'private_ip_address' => instance.private_ip_address,
    'public_ip_address'  => instance.ip_address,
    'dns_name'           => instance.dns_name,
    'image_id'           => instance.image_id,
    'instance_type'      => instance.instance_type 
  }
end
instances_file << basic_instance_info.to_yaml
instances_file.close
puts "lchf-instances.yaml created"

private_key = File.open('/Users/jimmy/.ssh/aws-upc.pem').read
instances.each do |instance|
  begin
    Net::SSH.start(instance.ip_address, "ec2-user", :key_data => private_key) do |ssh|
      puts "Uploading lchf-cassandra.yaml and lchf-install.sh to " + instance.dns_name
      ssh.scp.upload! "lchf-cassandra.yaml", "lchf-cassandra.yaml"
      ssh.scp.upload! "lchf-install.sh", "lchf-install.sh"
      ssh.scp.upload! "../api/zocial.py", "zocial.py"
      puts "Executing lchf-install.sh on " + instance.dns_name
      channel = ssh.open_channel do |channel|
        channel.request_pty do |ch, success|
          raise "Could not request pty" unless success
          ch.exec "sh lchf-install.sh" do |c, success|
            raise "Could not execute install script" unless success
          end
        end
      end
      channel.wait
      ssh.loop
      puts instance.id + "is ready"
    end
  rescue SystemCallError, Timeout::Error => e
    # port 22 might not be available immediately after the instance finishes launching
    sleep 1
    retry
  end
end




puts "Cluster is set up, now run 'sh lchf-start-cassandra.sh' to start Cassandra"