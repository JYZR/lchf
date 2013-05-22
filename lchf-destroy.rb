# Launch Cassandra and Hadoop Fast #
# ------------- lchf ------------- #

# ruby lchf-destroy.rb
# Terminates the previously deployed instances2

require 'aws-sdk'
require 'yaml'
require 'fileutils'

YAML.load(File.open("lchf-instances.yaml")).each do |instance_info|
	ec2 = AWS::EC2.new(:region => instance_info['region'])
	ec2.instances[instance_info['id']].terminate
	puts instance_info['id'] + ' in ' + instance_info['region']  + ' terminated'
end

puts 'Cluster terminated'

FileUtils.rm_f "lchf-instances.yaml"
FileUtils.rm_f "lchf-cassandra.yaml"
FileUtils.rm_f "lchf-start-cassandra.sh"
