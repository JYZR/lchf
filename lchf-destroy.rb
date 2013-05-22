# Launch Cassandra and Hadoop Fast #
# ------------- lchf ------------- #

# ruby lchf-destroy.rb
# Terminates the previously deployed instances

require 'aws-sdk'
require 'yaml'
require 'fileutils'

ec2 = AWS.ec2

basic_instance_info = YAML.load(File.open("lchf-instances.yaml"))

ids = basic_instance_info.map { |item| item['id'] }

soon_to_be_terminated_instances = ec2.instances.select { |instance| ids.include? instance.id }

soon_to_be_terminated_instances.each do |instance| 
	instance.terminate
	puts instance.id + ' terminated'
end

puts 'Cluster terminated'

FileUtils.rm_f "lchf-instances.yaml"
FileUtils.rm_f "lchf-cassandra.yaml"
FileUtils.rm_f "lchf-start-cassandra.sh"
